<script setup lang="ts">
// Move the selected customers to one area (or to no area) in a single step.
const props = defineProps<{ customers: CsCustomer[] }>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ saved: [] }>();

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

const areaId = ref<string | null>(null);
const saving = ref(false);

watch(open, (isOpen) => {
  if (isOpen) areaId.value = null;
});

async function save() {
  const ids = props.customers.map((c) => c.id);
  if (!ids.length) return;
  saving.value = true;
  const { error } = await supabase.from("customers").update({ area_id: areaId.value }).in("id", ids);
  saving.value = false;
  if (error) {
    toast.add({ title: t("cs.customers.bulkAreaFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("cs.customers.bulkAreaSaved", { count: ids.length }), color: "success" });
  open.value = false;
  emit("saved");
}
</script>

<template>
  <UModal v-model:open="open" :title="t('cs.customers.bulkAreaTitle')">
    <template #body>
      <div class="space-y-4">
        <p class="text-sm text-muted">{{ t("cs.customers.bulkAreaHint", { count: customers.length }) }}</p>
        <UFormField :label="t('cs.customers.area')">
          <AreaSelect v-model="areaId" />
        </UFormField>
        <UButton :label="t('common.save')" :loading="saving" :disabled="!customers.length" size="lg" block @click="save" />
      </div>
    </template>
  </UModal>
</template>
