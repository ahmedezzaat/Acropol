<script setup lang="ts">
// A maintenance visit was done. It cannot be saved until the person has entered
// the spare parts used (with their quantity — or ticked that none were used) and
// the visit cost; the final fees collected from the customer (visit cost + parts)
// are worked out from them. The next visit must be booked too (quick chips: after
// 6, 10 or 12 months).
const props = defineProps<{ product: CsProduct | null }>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ saved: [] }>();

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

interface PartLine {
  id: string;
  name: string;
  price: number;
  qty: number;
}

const doneOn = ref("");
const doneNote = ref("");
const visitCost = ref<number | null>(null);
// the visit cost of the customer's area, offered as the cost
const areaCostOffered = ref(false);
const parts = ref<PartLine[]>([]);
const partsLoaded = ref(false);
const noParts = ref(false);
const partSearch = ref("");
const nextMonths = ref<number | null>(null);
const nextWhen = ref("");
const nextNote = ref("");
const saving = ref(false);

const today = () => {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
};

watch(open, (isOpen) => {
  if (!isOpen) return;
  doneOn.value = today();
  doneNote.value = "";
  visitCost.value = null;
  areaCostOffered.value = false;
  parts.value = [];
  partsLoaded.value = false;
  noParts.value = false;
  partSearch.value = "";
  nextMonths.value = null;
  nextWhen.value = "";
  nextNote.value = "";
  loadParts();
  offerAreaCost();
});

// The spare parts of the product's category.
async function loadParts() {
  const categoryId = props.product?.category_id;
  if (categoryId) {
    const { data } = await supabase.from("spare_parts").select("id, name, price").eq("category_id", categoryId).order("name");
    parts.value = (data ?? []).map((p) => ({ id: p.id, name: p.name, price: Number(p.price), qty: 0 }));
  }
  partsLoaded.value = true;
}

async function offerAreaCost() {
  const customerId = props.product?.customer_id;
  if (!customerId) return;
  const { data: customer } = await supabase.from("customers").select("area_id").eq("id", customerId).maybeSingle();
  if (!customer?.area_id) return;
  const { data } = await supabase.from("area_visit_costs").select("cost").eq("area_id", customer.area_id).maybeSingle();
  // only when the person hasn't typed a cost in the meantime
  if (data && visitCost.value === null) {
    visitCost.value = Number(data.cost);
    areaCostOffered.value = true;
  }
}

// Quick choices for the next visit: the done date plus 6, 10 or 12 months, at 10:00
// (or the time already picked).
const NEXT_MONTHS = [6, 10, 12];
const pad = (n: number) => String(n).padStart(2, "0");
function applyMonths(months: number) {
  nextMonths.value = months;
  const [y, m, d] = (doneOn.value || today()).split("-").map(Number) as [number, number, number];
  const time = nextWhen.value.split("T")[1] || "10:00";
  // the same day of the month, or the last day when the month is shorter
  const target = new Date(y, m - 1 + months, 1);
  const last = new Date(target.getFullYear(), target.getMonth() + 1, 0).getDate();
  nextWhen.value = `${target.getFullYear()}-${pad(target.getMonth() + 1)}-${pad(Math.min(d, last))}T${time}`;
}
// Picking a date by hand clears the chip; changing the done date moves a chosen chip with it.
function onNextWhenInput() {
  nextMonths.value = null;
}
watch(doneOn, () => {
  if (nextMonths.value) applyMonths(nextMonths.value);
});

const shownParts = computed(() => {
  const q = partSearch.value.trim().toLowerCase();
  return q ? parts.value.filter((p) => p.name.toLowerCase().includes(q) || p.qty > 0) : parts.value;
});
const usedParts = computed(() => parts.value.filter((p) => p.qty > 0));
const partsTotal = computed(() => usedParts.value.reduce((n, p) => n + p.price * p.qty, 0));
const total = computed(() => partsTotal.value + (visitCost.value ?? 0));
const money = (v: number) => `${v.toLocaleString("en-US")} ${t("common.currency")}`;

// Parts only matter when the category has some defined.
const partsChecked = computed(() => !parts.value.length || usedParts.value.length > 0 || noParts.value);
const valid = computed(
  () =>
    !!doneOn.value &&
    partsLoaded.value &&
    partsChecked.value &&
    visitCost.value !== null &&
    visitCost.value >= 0 &&
    !!nextWhen.value,
);
watch(usedParts, (list) => {
  if (list.length) noParts.value = false;
});

async function save() {
  if (!props.product || !valid.value) return;
  saving.value = true;
  const next = new Date(nextWhen.value).toISOString();

  const { error } = await supabase
    .from("customer_products")
    .update({
      last_maintenance_on: doneOn.value,
      next_maintenance_at: next,
      next_maintenance_note: nextNote.value.trim() || null,
    })
    .eq("id", props.product.id);
  if (error) {
    saving.value = false;
    toast.add({ title: t("cs.maintenance.saveFailed"), description: error.message, color: "error" });
    return;
  }

  // the entry's cost is the final fees collected: the visit cost plus the parts
  const { data: entry, error: logError } = await supabase
    .from("product_maintenance_log")
    .insert({
      product_id: props.product.id,
      kind: "done",
      done_on: doneOn.value,
      note: doneNote.value.trim() || null,
      cost: total.value,
      visit_cost: visitCost.value,
      technician_id: props.product.maintenance_technician_id ?? null,
      marked_done: true,
    })
    .select("id")
    .single();
  if (logError || !entry) {
    saving.value = false;
    toast.add({ title: t("cs.maintenance.saveFailed"), description: logError?.message, color: "error" });
    return;
  }
  if (usedParts.value.length) {
    await supabase
      .from("maintenance_used_parts")
      .insert(usedParts.value.map((p) => ({ log_id: entry.id, spare_part_id: p.id, name: p.name, unit_price: p.price, quantity: p.qty })));
  }
  await supabase
    .from("product_maintenance_log")
    .insert({ product_id: props.product.id, kind: "scheduled", scheduled_for: next, note: nextNote.value.trim() || null });

  saving.value = false;
  toast.add({ title: t("cs.maintenance.doneSaved"), color: "success" });
  open.value = false;
  emit("saved");
}
</script>

<template>
  <UModal v-model:open="open" :title="t('cs.maintenance.markDone')">
    <template #body>
      <div v-if="product" class="space-y-4">
        <p class="text-sm font-medium text-highlighted">{{ product.name }}</p>

        <UFormField :label="t('cs.maintenance.doneOn')" required>
          <UInput v-model="doneOn" type="date" class="w-full" />
        </UFormField>

        <!-- Spare parts used -->
        <div class="space-y-2">
          <div class="flex items-center justify-between gap-2">
            <p class="text-sm font-medium text-highlighted">{{ t("cs.maintenance.sparePartsUsed") }} <span class="text-error">*</span></p>
            <UInput v-if="parts.length > 8" v-model="partSearch" icon="i-lucide-search" size="sm" :placeholder="t('cs.maintenance.filterParts')" class="w-44" />
          </div>
          <p v-if="partsLoaded && !parts.length" class="text-xs text-muted">{{ t("cs.maintenance.noSparePartsDefined") }}</p>
          <template v-else>
            <ul class="max-h-64 divide-y divide-default overflow-y-auto border border-default">
              <li v-for="p in shownParts" :key="p.id" class="flex items-center justify-between gap-3 px-3 py-2">
                <div class="min-w-0">
                  <div class="truncate text-sm font-medium text-highlighted">{{ p.name }}</div>
                  <div class="text-xs text-muted">{{ money(p.price) }}</div>
                </div>
                <UInputNumber v-model="p.qty" :min="0" size="sm" :aria-label="t('cs.maintenance.partQty')" class="w-28 shrink-0" />
              </li>
            </ul>
            <UCheckbox v-model="noParts" :disabled="usedParts.length > 0" :label="t('cs.maintenance.noPartsUsed')" />
            <p v-if="parts.length && !partsChecked" class="text-xs text-warning">{{ t("cs.maintenance.partsRequired") }}</p>
          </template>
        </div>

        <UFormField :label="t('cs.maintenance.visitCost')" :help="areaCostOffered ? t('cs.visitCosts.applied') : undefined" required>
          <UInputNumber v-model="visitCost" :min="0" class="w-full" />
        </UFormField>

        <!-- What the customer pays -->
        <dl class="space-y-1 rounded-[10px] bg-muted p-3 text-sm">
          <div class="flex justify-between"><dt class="text-muted">{{ t("cs.maintenance.visitCost") }}</dt><dd>{{ money(visitCost ?? 0) }}</dd></div>
          <div class="flex justify-between"><dt class="text-muted">{{ t("cs.maintenance.partsTotal") }}</dt><dd>{{ money(partsTotal) }}</dd></div>
          <div class="flex justify-between border-t border-default pt-1 text-base font-semibold text-highlighted"><dt>{{ t("cs.maintenance.finalFees") }}</dt><dd>{{ money(total) }}</dd></div>
        </dl>

        <UFormField :label="t('cs.maintenance.doneNote')">
          <UTextarea v-model="doneNote" :rows="3" class="w-full" />
        </UFormField>

        <div class="space-y-3 border-t border-default pt-4">
          <p class="text-sm font-medium text-highlighted">{{ t("cs.maintenance.scheduleNext") }} <span class="text-error">*</span></p>
          <div class="flex flex-wrap gap-2">
            <button
              v-for="m in NEXT_MONTHS"
              :key="m"
              type="button"
              class="kords-chip"
              :class="nextMonths === m && 'kords-chip-on'"
              @click="applyMonths(m)"
            >
              {{ t("cs.maintenance.afterMonths", { n: m }) }}
            </button>
          </div>
          <UFormField :label="t('cs.maintenance.whenLabel')" required>
            <UInput v-model="nextWhen" type="datetime-local" class="w-full" @input="onNextWhenInput" />
          </UFormField>
          <UFormField :label="t('cs.maintenance.note')">
            <UTextarea v-model="nextNote" :rows="2" class="w-full" />
          </UFormField>
        </div>

        <UButton :label="t('common.save')" :loading="saving" :disabled="!valid" size="lg" block @click="save" />
      </div>
    </template>
  </UModal>
</template>
