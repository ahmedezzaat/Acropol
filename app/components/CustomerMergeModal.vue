<script setup lang="ts">
// Merge two or more customers into one. Pick the customer to keep; the others
// are merged into it (their products, contracts, visits, deals and quotes move
// over, their phone numbers become additional contacts) and then removed.
const props = defineProps<{ customers: CsCustomer[]; productCounts: Record<string, number> }>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ merged: [keepId: string] }>();

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

const keepId = ref<string | null>(null);
const saving = ref(false);

// Start with the customer that has the most products (then the oldest one).
watch(open, (isOpen) => {
  if (!isOpen) return;
  const sorted = [...props.customers].sort(
    (a, b) =>
      (props.productCounts[b.id] ?? 0) - (props.productCounts[a.id] ?? 0) ||
      new Date(a.created_at ?? 0).getTime() - new Date(b.created_at ?? 0).getTime(),
  );
  keepId.value = sorted[0]?.id ?? null;
});

const others = computed(() => props.customers.filter((c) => c.id !== keepId.value));
const movingProducts = computed(() => others.value.reduce((sum, c) => sum + (props.productCounts[c.id] ?? 0), 0));

function close() {
  open.value = false;
}

async function merge() {
  if (!keepId.value || !others.value.length) return;
  saving.value = true;
  const { error } = await supabase.rpc("cs_merge_customers", { p_keep: keepId.value, p_merge: others.value.map((c) => c.id) });
  saving.value = false;
  if (error) {
    toast.add({ title: t("cs.customers.mergeFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("cs.customers.merged"), color: "success" });
  open.value = false;
  emit("merged", keepId.value);
}
</script>

<template>
  <UModal v-model:open="open" :title="t('cs.customers.mergeTitle')">
    <template #body>
      <div class="space-y-4">
        <p class="text-sm text-muted">{{ t("cs.customers.mergeHint") }}</p>

        <div class="space-y-2">
          <button
            v-for="c in customers"
            :key="c.id"
            type="button"
            class="flex w-full items-center gap-3 rounded-[10px] border p-3 text-start transition-colors"
            :class="c.id === keepId ? 'border-primary bg-primary/5' : 'border-default hover:bg-elevated'"
            @click="keepId = c.id"
          >
            <span class="flex size-5 shrink-0 items-center justify-center rounded-full border" :class="c.id === keepId ? 'border-primary bg-primary text-inverted' : 'border-accented'">
              <UIcon v-if="c.id === keepId" name="i-lucide-check" class="size-3.5" />
            </span>
            <KAvatar :name="isCompanyCustomer(c) ? null : customerTitle(c)" kind="contact" :icon="isCompanyCustomer(c) ? 'i-lucide-building-2' : undefined" size="sm" />
            <span class="min-w-0 flex-1">
              <span class="block truncate font-medium text-highlighted">{{ customerTitle(c) }}</span>
              <span class="flex flex-wrap items-center gap-x-2 text-xs text-muted">
                <bdi v-if="c.phone" dir="ltr">{{ c.phone }}</bdi>
                <span>{{ t("cs.customers.productsCount", { count: productCounts[c.id] ?? 0 }) }}</span>
              </span>
            </span>
            <KBadge v-if="c.id === keepId" :label="t('cs.customers.mergeKeep')" tone="success" />
          </button>
        </div>

        <UAlert
          v-if="others.length"
          icon="i-lucide-info"
          color="neutral"
          variant="subtle"
          :description="t('cs.customers.mergeSummary', { count: others.length, products: movingProducts })"
        />

        <div class="flex gap-2">
          <UButton color="neutral" variant="outline" :label="t('common.cancel')" class="flex-1 justify-center" @click="close" />
          <UButton
            icon="i-lucide-git-merge"
            :label="t('cs.customers.mergeConfirm', { count: customers.length })"
            :loading="saving"
            :disabled="!keepId || !others.length"
            class="flex-1 justify-center"
            @click="merge"
          />
        </div>
      </div>
    </template>
  </UModal>
</template>
