<script setup lang="ts">
// A maintenance visit was done (one or several of the customer's products serviced
// together). It cannot be saved until the person has entered
// the spare parts used (with their quantity — or ticked that none were used) and
// the visit cost; the final fees collected from the customer (visit cost + parts)
// are worked out from them. The next visit must be booked too (quick chips: after
// 6, 10 or 12 months).
const props = defineProps<{ products: CsProduct[] }>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ saved: [] }>();

const supabase = useSupabaseClient();
const me = useSupabaseUser();
const toast = useToast();
const { t } = useI18n();

const doneOn = ref("");
const doneNote = ref("");
// spare parts, visit fee and total: starts from what was set when the visit was confirmed
// (one set per product; the visit fee is entered once, on the first product)
const emptyFees = (): FeesState => ({ parts: [], fee: null, total: 0, checked: false, loaded: false });
const feesList = ref<FeesState[]>([]);
const initialPartsOf = (p: CsProduct) => (p.maintenance_confirm_parts as FeePart[] | null | undefined) ?? null;
// the visit fee settled at confirmation: on any of the products
const initialFee = computed(() => props.products.find((p) => p.maintenance_confirm_fee !== null && p.maintenance_confirm_fee !== undefined)?.maintenance_confirm_fee ?? null);
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
  feesList.value = props.products.map(emptyFees);
  doneOn.value = today();
  doneNote.value = "";
  signed.value = false;
  noSignature.value = false;
  signaturePad.value?.clear();
  nextMonths.value = null;
  nextWhen.value = "";
  nextNote.value = "";
});

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

const money = (v: number) => `${v.toLocaleString("en-US")} ${t("common.currency")}`;
// The customer signs on the technician's phone; for the technician assigned to this
// visit the signature is required, for anyone else it is optional.
const signed = ref(false);
// nobody was there to sign for the customer: the visit is saved without a signature
const noSignature = ref(false);
const signaturePad = ref<{ toBlob: () => Promise<Blob | null>; clear: () => void } | null>(null);
const mustSign = computed(() => props.products.some((p) => !!p.maintenance_technician_id && p.maintenance_technician_id === me.value?.sub));

const valid = computed(
  () =>
    props.products.length > 0 &&
    feesList.value.length === props.products.length &&
    (!mustSign.value || signed.value || noSignature.value) &&
    !!doneOn.value &&
    feesList.value.every((f) => f.loaded && f.checked) &&
    feesList.value[0]!.fee !== null &&
    feesList.value[0]!.fee >= 0 &&
    !!nextWhen.value,
);

async function save() {
  const products = props.products;
  const customerId = products[0]?.customer_id;
  if (!customerId || !valid.value) return;
  saving.value = true;
  const next = new Date(nextWhen.value).toISOString();
  const fail = (title: string, description?: string) => {
    saving.value = false;
    toast.add({ title, description, color: "error" });
  };

  // the customer's signature, kept in a private bucket
  let signaturePath: string | null = null;
  if (signed.value && !noSignature.value) {
    const blob = await signaturePad.value?.toBlob();
    if (blob) {
      const path = `${customerId}/${Date.now()}.png`;
      const { error: uploadError } = await supabase.storage.from("visit-signatures").upload(path, blob, { contentType: "image/png" });
      if (uploadError) return fail(t("cs.maintenance.signatureFailed"), uploadError.message);
      signaturePath = path;
    }
  }

  // one visit for the products serviced together; its note is the note written here
  const { data: visit, error: visitError } = await supabase
    .from("maintenance_visits")
    .insert({ customer_id: customerId, visit_at: new Date(`${doneOn.value}T12:00:00`).toISOString(), note: doneNote.value.trim() || null })
    .select("id")
    .single();
  if (visitError || !visit) return fail(t("cs.maintenance.saveFailed"), visitError?.message);

  for (const [i, product] of products.entries()) {
    const f = feesList.value[i]!;
    // the entry's cost is the final fees collected: the parts, plus the visit fee on the first product
    const fee = i === 0 ? f.fee : null;
    const { error } = await supabase
      .from("customer_products")
      .update({ last_maintenance_on: doneOn.value, next_maintenance_at: next, next_maintenance_note: nextNote.value.trim() || null })
      .eq("id", product.id);
    if (error) return fail(t("cs.maintenance.saveFailed"), error.message);

    const { data: entry, error: logError } = await supabase
      .from("product_maintenance_log")
      .insert({
        product_id: product.id,
        visit_id: visit.id,
        kind: "done",
        done_on: doneOn.value,
        cost: f.total,
        visit_cost: fee,
        technician_id: product.maintenance_technician_id ?? null,
        marked_done: true,
        signature_path: signaturePath,
      })
      .select("id")
      .single();
    if (logError || !entry) return fail(t("cs.maintenance.saveFailed"), logError?.message);
    if (f.parts.length) {
      await supabase
        .from("maintenance_used_parts")
        .insert(f.parts.map((p) => ({ log_id: entry.id, spare_part_id: p.id, name: p.name, unit_price: p.price, quantity: p.qty })));
    }
    await supabase.from("product_maintenance_log").insert({ product_id: product.id, kind: "scheduled", scheduled_for: next, note: nextNote.value.trim() || null });
  }

  saving.value = false;
  toast.add({ title: t("cs.maintenance.doneSaved"), color: "success" });
  open.value = false;
  emit("saved");
}
</script>

<template>
  <UModal v-model:open="open" :title="t('cs.maintenance.markDone')">
    <template #body>
      <div v-if="products.length" class="space-y-4">
        <p v-if="products.length === 1" class="text-sm font-medium text-highlighted">{{ products[0]!.name }}</p>

        <UFormField :label="t('cs.maintenance.doneOn')" required>
          <UInput v-model="doneOn" type="date" class="w-full" />
        </UFormField>

        <!-- Spare parts, visit fee and total, as set at confirmation (can be changed) -->
        <template v-if="feesList.length === products.length">
          <div v-for="(p, i) in products" :key="p.id" :class="products.length > 1 && 'space-y-3 rounded-[10px] border border-default p-3'">
            <p v-if="products.length > 1" class="text-sm font-semibold text-highlighted">{{ p.name }}</p>
            <MaintenanceFeesEditor v-model="feesList[i]!" :product="p" :active="open" :initial-parts="initialPartsOf(p)" :initial-fee="i === 0 ? initialFee : null" :show-fee="i === 0" required />
          </div>
        </template>

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

        <!-- The customer signs with a finger -->
        <div class="space-y-2 border-t border-default pt-4">
          <p class="text-sm font-medium text-highlighted">{{ t("cs.maintenance.customerSignature") }} <span v-if="mustSign" class="text-error">*</span></p>
          <UCheckbox v-model="noSignature" :label="t('cs.maintenance.noOneToSign')" />
          <SignaturePad v-show="!noSignature" ref="signaturePad" v-model:signed="signed" />
          <p v-if="mustSign && !signed && !noSignature" class="text-xs text-warning">{{ t("cs.maintenance.signatureRequired") }}</p>
        </div>

        <p class="flex items-start gap-2 rounded-[10px] bg-success/10 p-3 text-sm text-success">
          <UIcon name="i-lucide-send" class="mt-0.5 size-4 shrink-0" />
          <span>{{ t("cs.maintenance.copySentNote") }}</span>
        </p>

        <UButton :label="t('common.save')" :loading="saving" :disabled="!valid" size="lg" block @click="save" />
      </div>
    </template>
  </UModal>
</template>
