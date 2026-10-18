<script setup lang="ts">
// Confirm a scheduled maintenance visit: someone called the customer and agreed
// it. The date can be corrected here (the customer may agree another time), a
// note records who confirmed, and the customer's other appointments on the same
// day can be confirmed in the same call. A visit has to be confirmed before it
// can be marked as done.
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
const saving = ref(false);

interface Sibling {
  id: string;
  name: string;
  next_maintenance_at: string;
  on: boolean;
}
const siblings = ref<Sibling[]>([]);

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
  siblings.value = [];
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

async function save() {
  const product = props.product;
  if (!product || !when.value) return;
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
    const patch: { maintenance_confirmed_at: string; maintenance_confirmed_by: string | null; maintenance_confirm_note: string | null; next_maintenance_at?: string } = {
      maintenance_confirmed_at: nowIso,
      maintenance_confirmed_by: by,
      maintenance_confirm_note: text,
      ...(moved ? { next_maintenance_at: newAt } : {}),
    };
    const { error } = await supabase.from("customer_products").update(patch).eq("id", target.id);
    if (error) {
      saving.value = false;
      toast.add({ title: t("cs.maintenance.confirmFailed"), description: error.message, color: "error" });
      return;
    }
    const logs = [
      ...(moved ? [{ product_id: target.id, kind: "rescheduled", scheduled_for: newAt, note: text }] : []),
      { product_id: target.id, kind: "confirmed", scheduled_for: moved ? newAt : target.from, note: text },
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
        <UFormField :label="t('cs.maintenance.confirmWhen')" required>
          <UInput v-model="when" type="datetime-local" class="w-full" />
        </UFormField>
        <UFormField :label="t('cs.maintenance.confirmNote')">
          <UTextarea v-model="note" :rows="2" class="w-full" />
        </UFormField>

        <div v-if="siblings.length" class="space-y-2 rounded-[10px] border border-default p-3">
          <p class="text-xs font-medium text-muted">{{ t("cs.maintenance.confirmAlso") }}</p>
          <UCheckbox v-for="s in siblings" :key="s.id" v-model="s.on" :label="`${s.name} · ${formatDateTime(s.next_maintenance_at)}`" />
        </div>

        <div class="flex gap-2">
          <UButton color="neutral" variant="outline" :label="t('common.cancel')" class="flex-1 justify-center" @click="close" />
          <UButton icon="i-lucide-phone-call" :label="t('cs.maintenance.confirm')" :loading="saving" :disabled="!when" class="flex-1 justify-center" @click="save" />
        </div>
      </div>
    </template>
  </UModal>
</template>
