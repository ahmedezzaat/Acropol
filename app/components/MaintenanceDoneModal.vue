<script setup lang="ts">
// A maintenance visit was done: record the date and a note, and optionally book
// the next one right away (date and time + note).
const props = defineProps<{ product: CsProduct | null }>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ saved: [] }>();

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

const doneOn = ref("");
const doneNote = ref("");
const cost = ref<number | null>(null);
const scheduleNext = ref(false);
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
  cost.value = null;
  scheduleNext.value = false;
  nextWhen.value = "";
  nextNote.value = "";
});

const valid = computed(() => !!doneOn.value && (!scheduleNext.value || !!nextWhen.value));

async function save() {
  if (!props.product || !valid.value) return;
  saving.value = true;
  const next = scheduleNext.value ? new Date(nextWhen.value).toISOString() : null;

  const { error } = await supabase
    .from("customer_products")
    .update({
      last_maintenance_on: doneOn.value,
      next_maintenance_at: next,
      next_maintenance_note: scheduleNext.value ? nextNote.value.trim() || null : null,
    })
    .eq("id", props.product.id);
  if (error) {
    saving.value = false;
    toast.add({ title: t("cs.maintenance.saveFailed"), description: error.message, color: "error" });
    return;
  }

  const log = [
    { product_id: props.product.id, kind: "done", done_on: doneOn.value, note: doneNote.value.trim() || null, cost: cost.value },
    ...(next
      ? [{ product_id: props.product.id, kind: "scheduled", scheduled_for: next, note: nextNote.value.trim() || null }]
      : []),
  ];
  await supabase.from("product_maintenance_log").insert(log);

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
        <UFormField :label="t('cs.maintenance.cost')">
          <UInputNumber v-model="cost" :min="0" class="w-full" />
        </UFormField>
        <UFormField :label="t('cs.maintenance.doneNote')">
          <UTextarea v-model="doneNote" :rows="3" class="w-full" />
        </UFormField>

        <div class="space-y-3 border-t border-default pt-4">
          <USwitch v-model="scheduleNext" :label="t('cs.maintenance.scheduleNext')" />
          <template v-if="scheduleNext">
            <UFormField :label="t('cs.maintenance.whenLabel')" required>
              <UInput v-model="nextWhen" type="datetime-local" class="w-full" />
            </UFormField>
            <UFormField :label="t('cs.maintenance.note')">
              <UTextarea v-model="nextNote" :rows="2" class="w-full" />
            </UFormField>
          </template>
        </div>

        <UButton :label="t('common.save')" :loading="saving" :disabled="!valid" size="lg" block @click="save" />
      </div>
    </template>
  </UModal>
</template>
