<script setup lang="ts">
// Schedule the next maintenance visit of a product, or reschedule it: a date
// and time plus a note. (Declining maintenance for good is its own dialog.)
const props = defineProps<{ product: CsProduct | null }>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ saved: [] }>();

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

const when = ref("");
const note = ref("");
const saving = ref(false);

// <input type="datetime-local"> works in local time without a zone.
function toLocalInput(iso: string | null | undefined) {
  if (!iso) return "";
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

watch(open, (isOpen) => {
  if (!isOpen) return;
  when.value = toLocalInput(props.product?.next_maintenance_at);
  note.value = props.product?.next_maintenance_note ?? "";
});

const rescheduling = computed(() => !!props.product?.next_maintenance_at);

async function save() {
  if (!props.product || !when.value) return;
  saving.value = true;
  const at = new Date(when.value).toISOString();
  const { error } = await supabase
    .from("customer_products")
    .update({ next_maintenance_at: at, next_maintenance_note: note.value.trim() || null })
    .eq("id", props.product.id);
  if (!error) {
    await supabase.from("product_maintenance_log").insert({
      product_id: props.product.id,
      kind: rescheduling.value ? "rescheduled" : "scheduled",
      scheduled_for: at,
      note: note.value.trim() || null,
    });
  }
  saving.value = false;
  if (error) {
    toast.add({ title: t("cs.maintenance.saveFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t(rescheduling.value ? "cs.maintenance.rescheduled" : "cs.maintenance.saved"), color: "success" });
  open.value = false;
  emit("saved");
}
</script>

<template>
  <UModal v-model:open="open" :title="t(rescheduling ? 'cs.maintenance.reschedule' : 'cs.maintenance.schedule')">
    <template #body>
      <div v-if="product" class="space-y-4">
        <p class="text-sm font-medium text-highlighted">{{ product.name }}</p>
        <UFormField :label="t('cs.maintenance.whenLabel')" required>
          <UInput v-model="when" type="datetime-local" class="w-full" />
        </UFormField>
        <UFormField :label="t('cs.maintenance.note')">
          <UTextarea v-model="note" :rows="3" class="w-full" />
        </UFormField>
        <UButton :label="t('common.save')" :loading="saving" :disabled="!when" size="lg" block @click="save" />
      </div>
    </template>
  </UModal>
</template>
