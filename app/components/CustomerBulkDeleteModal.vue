<script setup lang="ts">
// Delete the selected customers. A customer that still has products is skipped
// unless "also delete their products" is ticked, which removes the products with
// their contracts, visits and maintenance history too.
const props = defineProps<{ customers: CsCustomer[]; productCounts: Record<string, number> }>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ deleted: [] }>();

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();
const { hasPermission } = usePermissions();

const withProducts = ref(false);
const saving = ref(false);
const canDeleteProducts = computed(() => hasPermission("cs_customers", "edit"));

watch(open, (isOpen) => {
  if (isOpen) withProducts.value = false;
});

const withProductsCount = computed(() => props.customers.filter((c) => (props.productCounts[c.id] ?? 0) > 0).length);
const productTotal = computed(() => props.customers.reduce((sum, c) => sum + (props.productCounts[c.id] ?? 0), 0));
const willDelete = computed(() => (withProducts.value ? props.customers.length : props.customers.length - withProductsCount.value));

function close() {
  open.value = false;
}

async function confirm() {
  if (!willDelete.value) return;
  saving.value = true;
  const { data, error } = await supabase.rpc("cs_delete_customers", { p_ids: props.customers.map((c) => c.id), p_with_products: withProducts.value });
  saving.value = false;
  if (error) {
    toast.add({ title: t("cs.customers.deleteFailed"), description: error.message, color: "error" });
    return;
  }
  const result = data as { deleted: number; skipped: number };
  toast.add({
    title: t("cs.customers.bulkDeleted", { count: result.deleted }),
    description: result.skipped ? t("cs.customers.bulkSkipped", { count: result.skipped }) : undefined,
    color: result.skipped ? "warning" : "success",
  });
  open.value = false;
  emit("deleted");
}
</script>

<template>
  <UModal v-model:open="open" :title="t('cs.customers.bulkDeleteTitle')">
    <template #body>
      <div class="space-y-4">
        <p class="text-sm text-muted">{{ t("cs.customers.bulkDeleteConfirm", { count: customers.length }) }}</p>

        <ul class="max-h-48 space-y-1 overflow-y-auto rounded-[10px] border border-default p-2 text-sm">
          <li v-for="c in customers" :key="c.id" class="flex items-center justify-between gap-2">
            <span class="truncate">{{ customerTitle(c) }}</span>
            <span v-if="productCounts[c.id]" class="shrink-0 text-xs text-warning">{{ t("cs.customers.productsCount", { count: productCounts[c.id] }) }}</span>
          </li>
        </ul>

        <template v-if="withProductsCount">
          <UAlert
            icon="i-lucide-triangle-alert"
            color="warning"
            variant="subtle"
            :description="t('cs.customers.bulkHasProducts', { count: withProductsCount, products: productTotal })"
          />
          <USwitch v-if="canDeleteProducts" v-model="withProducts" :label="t('cs.customers.bulkWithProducts')" />
        </template>

        <div class="flex gap-2">
          <UButton color="neutral" variant="outline" :label="t('common.cancel')" class="flex-1 justify-center" @click="close" />
          <UButton
            color="error"
            icon="i-lucide-trash"
            :label="t('cs.customers.bulkDeleteButton', { count: willDelete })"
            :loading="saving"
            :disabled="!willDelete"
            class="flex-1 justify-center"
            @click="confirm"
          />
        </div>
      </div>
    </template>
  </UModal>
</template>
