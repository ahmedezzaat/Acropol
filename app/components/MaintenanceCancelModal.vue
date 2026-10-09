<script setup lang="ts">
// The customer does not want maintenance, now or ever: the product leaves the
// periodic due dates and the overdue lists until maintenance is resumed.
const props = defineProps<{ product: CsProduct | null }>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ saved: [] }>();

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

const reason = ref("");
const saving = ref(false);

watch(open, (isOpen) => {
  if (isOpen) reason.value = "";
});

function close() {
  open.value = false;
}

async function save() {
  if (!props.product) return;
  saving.value = true;
  const { error } = await supabase
    .from("customer_products")
    .update({ maintenance_declined_at: new Date().toISOString(), next_maintenance_at: null, next_maintenance_note: null })
    .eq("id", props.product.id);
  if (!error) {
    await supabase.from("product_maintenance_log").insert({
      product_id: props.product.id,
      kind: "declined",
      scheduled_for: props.product.next_maintenance_at,
      note: reason.value.trim() || null,
    });
  }
  saving.value = false;
  if (error) {
    toast.add({ title: t("cs.maintenance.saveFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("cs.maintenance.declinedSaved"), color: "success" });
  open.value = false;
  emit("saved");
}
</script>

<template>
  <UModal v-model:open="open" :title="t('cs.maintenance.cancelTitle')">
    <template #body>
      <div v-if="product" class="space-y-4">
        <p class="text-sm font-medium text-highlighted">{{ product.name }}</p>
        <p class="text-sm text-muted">{{ t("cs.maintenance.cancelHint") }}</p>
        <UFormField :label="t('cs.maintenance.cancelReason')">
          <UTextarea v-model="reason" :rows="3" class="w-full" />
        </UFormField>
        <div class="flex gap-2">
          <UButton color="neutral" variant="outline" :label="t('common.cancel')" class="flex-1 justify-center" @click="close" />
          <UButton color="error" :label="t('cs.maintenance.cancelConfirm')" :loading="saving" class="flex-1 justify-center" @click="save" />
        </div>
      </div>
    </template>
  </UModal>
</template>
