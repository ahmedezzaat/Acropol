<script setup lang="ts">
// Add a maintenance visit from a customer's profile. The team visits the customer
// once and may service several products in that visit: pick the products, and
// for each one write what happened and (optionally) its cost. The visit is one of
// done / scheduled / cancelled, with one date.
// preselectIds / initialType open the form ready for a known visit (for example
// "mark this confirmed visit as done" with its products ticked).
const props = defineProps<{ customerId: string; products: CsProduct[]; preselectIds?: string[]; initialType?: "done" | "scheduled" | "cancelled" }>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ saved: [] }>();

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();
const { hasPermission } = usePermissions();
const { stageById } = useCs();

type RecordType = "done" | "scheduled" | "cancelled";
const typeAllowed: Record<RecordType, ComputedRef<boolean>> = {
  done: computed(() => hasPermission("cs_maintenance", "complete")),
  scheduled: computed(() => hasPermission("cs_maintenance", "schedule")),
  cancelled: computed(() => hasPermission("cs_maintenance", "cancel")),
};
const typeItems = computed(() =>
  (["done", "scheduled", "cancelled"] as const)
    .filter((k) => typeAllowed[k].value)
    .map((k) => ({ label: t(`cs.maintenance.stat.${k === "cancelled" ? "declined" : k}`), value: k })),
);
const canUpdateProduct = computed(() => hasPermission("cs_customers", "edit"));

const pad = (n: number) => String(n).padStart(2, "0");
const todayIso = () => {
  const d = new Date();
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
};
const nowLocal = () => {
  const d = new Date();
  return `${todayIso()}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
};

// One line per product of the customer: ticked or not, with its own note and cost.
interface Line {
  product: CsProduct;
  on: boolean;
  note: string;
  cost: number | null;
}
const lines = ref<Line[]>([]);
const type = ref<RecordType>("done");
const doneOn = ref("");
const when = ref("");
const visitNote = ref("");
const saving = ref(false);

watch(open, (isOpen) => {
  if (!isOpen) return;
  // Start with the products in operation ticked (the ones maintenance is about),
  // or the first product when none has reached that stage yet.
  const operating = props.products.filter((p) => !!stageById(p.stage_id)?.is_final);
  const preselected = props.preselectIds?.length ? props.products.filter((p) => props.preselectIds!.includes(p.id)) : [];
  const start = preselected.length ? preselected : operating.length ? operating : props.products.slice(0, 1);
  lines.value = props.products.map((p) => ({ product: p, on: start.some((s) => s.id === p.id), note: "", cost: null }));
  type.value = typeItems.value.find((i) => i.value === props.initialType)?.value ?? typeItems.value[0]?.value ?? "done";
  doneOn.value = todayIso();
  when.value = nowLocal();
  visitNote.value = "";
});

const picked = computed(() => lines.value.filter((l) => l.on));
const valid = computed(
  () =>
    picked.value.length > 0 &&
    (type.value === "done" ? !!doneOn.value : !!when.value) &&
    picked.value.every((l) => l.cost === null || l.cost >= 0),
);
const total = computed(() => picked.value.reduce((sum, l) => sum + (l.cost ?? 0), 0));
const money = (v: number) => `${v.toLocaleString("en-US")} ${t("common.currency")}`;

const sameDay = (a: string, b: string) => new Date(a).toDateString() === new Date(b).toDateString();

async function save() {
  if (!valid.value) return;
  saving.value = true;

  const at = type.value === "done" ? null : new Date(when.value).toISOString();
  const futureAppointment = type.value === "scheduled" && !!at && new Date(at).getTime() > Date.now();

  const { data: visit, error: visitError } = await supabase
    .from("maintenance_visits")
    .insert({
      customer_id: props.customerId,
      visit_at: type.value === "done" ? new Date(`${doneOn.value}T12:00:00`).toISOString() : at,
      note: visitNote.value.trim() || null,
    })
    .select("id")
    .single();
  if (visitError || !visit) {
    saving.value = false;
    toast.add({ title: t("cs.maintenance.saveFailed"), description: visitError?.message, color: "error" });
    return;
  }

  const rows = picked.value.map((l) => ({
    product_id: l.product.id,
    visit_id: visit.id,
    kind: type.value === "scheduled" && l.product.next_maintenance_at && futureAppointment ? "rescheduled" : type.value,
    done_on: type.value === "done" ? doneOn.value : null,
    scheduled_for: at,
    note: l.note.trim() || null,
    cost: l.cost,
    // who did a visit: the technician it was assigned to
    technician_id: type.value === "done" ? (l.product.maintenance_technician_id ?? null) : null,
  }));
  const { error } = await supabase.from("product_maintenance_log").insert(rows);
  if (error) {
    saving.value = false;
    toast.add({ title: t("cs.maintenance.saveFailed"), description: error.message, color: "error" });
    return;
  }

  // Keep each product's own maintenance state in step with what was recorded.
  if (canUpdateProduct.value) {
    for (const l of picked.value) {
      const product = l.product;
      const patch: { last_maintenance_on?: string; next_maintenance_at?: string | null; next_maintenance_note?: string | null } = {};
      if (type.value === "done") {
        if (!product.last_maintenance_on || doneOn.value > product.last_maintenance_on) patch.last_maintenance_on = doneOn.value;
        // The booked appointment has been carried out.
        if (product.next_maintenance_at && product.next_maintenance_at.slice(0, 10) <= doneOn.value) {
          patch.next_maintenance_at = null;
          patch.next_maintenance_note = null;
        }
      } else if (futureAppointment) {
        patch.next_maintenance_at = at;
        patch.next_maintenance_note = l.note.trim() || visitNote.value.trim() || null;
      } else if (type.value === "cancelled" && at && product.next_maintenance_at && sameDay(product.next_maintenance_at, at)) {
        patch.next_maintenance_at = null;
        patch.next_maintenance_note = null;
      }
      if (Object.keys(patch).length) await supabase.from("customer_products").update(patch).eq("id", product.id);
    }
  }

  saving.value = false;
  toast.add({ title: t("cs.profile.recordSaved"), color: "success" });
  open.value = false;
  emit("saved");
}
</script>

<template>
  <UModal v-model:open="open" :title="t('cs.profile.addMaintenanceRecord')">
    <template #body>
      <div class="space-y-4">
        <UFormField :label="t('cs.profile.recordType')" required>
          <URadioGroup v-model="type" orientation="horizontal" :items="typeItems" value-key="value" />
        </UFormField>

        <UFormField :label="t('cs.profile.recordDate')" required>
          <UInput v-if="type === 'done'" v-model="doneOn" type="date" class="w-full" />
          <UInput v-else v-model="when" type="datetime-local" class="w-full" />
        </UFormField>

        <!-- The products serviced in this visit, each with its own note and cost -->
        <div class="space-y-2">
          <div class="flex items-center justify-between gap-2">
            <span class="text-sm font-medium text-highlighted">{{ t("cs.profile.visitProducts") }}</span>
            <span v-if="total" class="text-xs font-semibold text-muted">{{ t("cs.profile.visitTotal", { amount: money(total) }) }}</span>
          </div>
          <div v-for="l in lines" :key="l.product.id" class="rounded-[10px] border p-3" :class="l.on ? 'border-primary/40 bg-primary/5' : 'border-default'">
            <UCheckbox v-model="l.on">
              <template #label>
                <span class="font-medium">{{ l.product.name }}</span>
                <span v-if="(l.product.quantity ?? 1) > 1" class="ms-1 text-xs text-muted">× {{ l.product.quantity }}</span>
                <bdi v-if="l.product.contract_code" dir="ltr" class="ms-2 text-xs text-muted">#{{ l.product.contract_code }}</bdi>
              </template>
            </UCheckbox>
            <div v-if="l.on" class="mt-3 grid gap-3 sm:grid-cols-[1fr_9rem]">
              <UFormField :label="t('cs.profile.whatHappened')">
                <UTextarea v-model="l.note" :rows="2" class="w-full" />
              </UFormField>
              <UFormField :label="t('cs.profile.costOptional')">
                <UInputNumber v-model="l.cost" :min="0" class="w-full" />
              </UFormField>
            </div>
          </div>
          <p v-if="!picked.length" class="text-xs text-error">{{ t("cs.profile.visitPickProducts") }}</p>
        </div>

        <UFormField :label="t('cs.profile.visitNote')">
          <UTextarea v-model="visitNote" :rows="2" class="w-full" />
        </UFormField>

        <UButton :label="t('common.save')" :loading="saving" :disabled="!valid" size="lg" block @click="save" />
      </div>
    </template>
  </UModal>
</template>
