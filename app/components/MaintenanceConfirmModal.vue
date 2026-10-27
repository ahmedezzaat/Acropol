<script setup lang="ts">
import type { Json } from "~/types/database.types";
// Confirm a scheduled maintenance visit: someone called the customer and agreed
// it. The date can be corrected here (the customer may agree another time), a
// note records who confirmed, and the customer's other appointments on the same
// day can be confirmed in the same call. A visit has to be confirmed before it
// can be marked as done. A technician can be assigned in the same step (optional).
const props = defineProps<{ product: CsProduct | null }>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ saved: [] }>();

const supabase = useSupabaseClient();
const me = useSupabaseUser();
const toast = useToast();
const { t } = useI18n();
const { formatDateTime } = useCs();

const when = ref("");
const note = ref("");
const fees = ref<FeesState>({ parts: [], fee: null, total: 0, checked: false, loaded: false });
const initialParts = computed(() => (props.product?.maintenance_confirm_parts as FeePart[] | null | undefined) ?? null);
const reason = ref("");
const saving = ref(false);

interface Sibling {
  id: string;
  name: string;
  next_maintenance_at: string;
  on: boolean;
}
const siblings = ref<Sibling[]>([]);

// Optional: the technician who will do the visit.
interface Technician {
  id: string;
  full_name: string | null;
  email: string;
}
const technicians = ref<Technician[]>([]);
const technicianId = ref<string | null>(null);
const technicianItems = computed(() => [
  { label: t("cs.maintenance.unassigned"), value: null as string | null },
  ...technicians.value.map((u) => ({ label: u.full_name || u.email, value: u.id as string | null })),
]);

function toLocalInput(iso: string | null | undefined) {
  if (!iso) return "";
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}
const sameDay = (a: string, b: string) => new Date(a).toDateString() === new Date(b).toDateString();

watch(open, async (isOpen) => {
  if (!isOpen || !props.product) return;
  when.value = toLocalInput(props.product.next_maintenance_at);
  note.value = "";
  reason.value = "";
  technicianId.value = null;
  siblings.value = [];
  const { data: techs } = await supabase.from("profiles").select("id, full_name, email").eq("is_technician", true).eq("is_active", true).order("full_name");
  technicians.value = (techs ?? []) as Technician[];
  // The same customer's other unconfirmed appointments that day: one call, one visit.
  const { data } = await supabase
    .from("customer_products")
    .select("id, name, next_maintenance_at, maintenance_confirmed_at")
    .eq("customer_id", props.product.customer_id)
    .neq("id", props.product.id)
    .not("next_maintenance_at", "is", null)
    .is("maintenance_confirmed_at", null);
  siblings.value = (data ?? [])
    .filter((p) => p.next_maintenance_at && props.product?.next_maintenance_at && sameDay(p.next_maintenance_at, props.product.next_maintenance_at))
    .map((p) => ({ id: p.id, name: p.name, next_maintenance_at: p.next_maintenance_at!, on: true }));
});

// The appointment is being moved (the customer agreed another time): say why.
const willMove = computed(
  () => !!props.product?.next_maintenance_at && !!when.value && new Date(props.product.next_maintenance_at).getTime() !== new Date(when.value).getTime(),
);
const canSave = computed(() => !!when.value && (!willMove.value || !!reason.value.trim()));

async function save() {
  const product = props.product;
  if (!product || !canSave.value) return;
  saving.value = true;
  const newAt = new Date(when.value).toISOString();
  const moved = !!product.next_maintenance_at && new Date(product.next_maintenance_at).getTime() !== new Date(newAt).getTime();
  const targets = [{ id: product.id, from: product.next_maintenance_at }, ...siblings.value.filter((s) => s.on).map((s) => ({ id: s.id, from: s.next_maintenance_at }))];
  const text = note.value.trim() || null;
  const nowIso = new Date().toISOString();
  const by = (me.value?.sub as string | undefined) ?? null;

  for (const target of targets) {
    // Confirming together with a changed time keeps the confirmation (a plain
    // change of time would remove it).
    const patch: {
      maintenance_confirmed_at: string;
      maintenance_confirmed_by: string | null;
      maintenance_confirm_note: string | null;
      next_maintenance_at?: string;
      maintenance_technician_id?: string;
      maintenance_assigned_at?: string;
      maintenance_confirm_parts?: Json | null;
      maintenance_confirm_fee?: number | null;
    } = {
      maintenance_confirmed_at: nowIso,
      maintenance_confirmed_by: by,
      maintenance_confirm_note: text,
      ...(moved ? { next_maintenance_at: newAt } : {}),
      // what the visit is expected to cost is settled on the visit itself, not its same-day companions
      ...(target.id === product.id ? { maintenance_confirm_parts: fees.value.parts.length ? (fees.value.parts as unknown as Json) : null, maintenance_confirm_fee: fees.value.fee } : {}),
      ...(technicianId.value ? { maintenance_technician_id: technicianId.value, maintenance_assigned_at: nowIso } : {}),
    };
    const { error } = await supabase.from("customer_products").update(patch).eq("id", target.id);
    if (error) {
      saving.value = false;
      toast.add({ title: t("cs.maintenance.confirmFailed"), description: error.message, color: "error" });
      return;
    }
    const logs = [
      ...(moved ? [{ product_id: target.id, kind: "rescheduled", scheduled_for: newAt, previous_scheduled_for: target.from, reschedule_reason: reason.value.trim(), note: text }] : []),
      { product_id: target.id, kind: "confirmed", scheduled_for: moved ? newAt : target.from, note: text },
      ...(technicianId.value
        ? [{ product_id: target.id, kind: "assigned", scheduled_for: moved ? newAt : target.from, technician_id: technicianId.value, note: null }]
        : []),
    ];
    await supabase.from("product_maintenance_log").insert(logs);
  }

  saving.value = false;
  toast.add({ title: t("cs.maintenance.confirmedSaved"), color: "success" });
  open.value = false;
  emit("saved");
}

function close() {
  open.value = false;
}
</script>

<template>
  <UModal v-model:open="open" :title="t('cs.maintenance.confirmTitle')">
    <template #body>
      <div v-if="product" class="space-y-4">
        <p class="text-sm font-medium text-highlighted">{{ product.name }}</p>
        <p class="text-sm text-muted">{{ t("cs.maintenance.confirmHint") }}</p>
        <!-- Optional: who will do the visit (also applies to the same-day visits ticked below) -->
        <UFormField :label="t('cs.maintenance.assignOptional')" :help="technicians.length ? undefined : t('cs.maintenance.noTechnicians')">
          <USelect
            :model-value="technicianId"
            :items="technicianItems"
            value-key="value"
            icon="i-lucide-hard-hat"
            class="w-full"
            @update:model-value="(v: string | null) => (technicianId = v)"
          />
        </UFormField>
        <UFormField :label="t('cs.maintenance.confirmWhen')" required>
          <UInput v-model="when" type="datetime-local" class="w-full" />
        </UFormField>
        <UFormField v-if="willMove" :label="t('cs.maintenance.rescheduleReason')" required>
          <UTextarea v-model="reason" :rows="2" :placeholder="t('cs.maintenance.rescheduleReasonHint')" class="w-full" />
        </UFormField>
        <MaintenanceFeesEditor v-model="fees" planning :product="product" :active="open" :initial-parts="initialParts" :initial-fee="product.maintenance_confirm_fee ?? null" />
        <UFormField :label="t('cs.maintenance.confirmNote')">
          <UTextarea v-model="note" :rows="2" class="w-full" />
        </UFormField>
        <div v-if="siblings.length" class="space-y-2 rounded-[10px] border border-default p-3">
          <p class="text-xs font-medium text-muted">{{ t("cs.maintenance.confirmAlso") }}</p>
          <UCheckbox v-for="s in siblings" :key="s.id" v-model="s.on" :label="`${s.name} · ${formatDateTime(s.next_maintenance_at)}`" />
        </div>

        <div class="flex gap-2">
          <UButton color="neutral" variant="outline" :label="t('common.cancel')" class="flex-1 justify-center" @click="close" />
          <UButton icon="i-lucide-phone-call" :label="t('cs.maintenance.confirmCta')" :loading="saving" :disabled="!canSave" class="flex-1 justify-center" @click="save" />
        </div>
      </div>
    </template>
  </UModal>
</template>
