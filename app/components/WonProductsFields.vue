<script setup lang="ts">
// The products bought in a deal, asked for when the deal is won: name, category,
// contract details, who sold it, warranty and payment. One block per product.
const list = defineModel<WonProductDraft[]>({ required: true });
const props = defineProps<{ defaults?: Partial<WonProductDraft> }>();

const supabase = useSupabaseClient();
const { t } = useI18n();

const { data: categories } = useAsyncData<{ id: string; name: string }[]>("won-products-categories", async () => {
  const { data } = await supabase.from("product_categories").select("id, name").order("sort_order");
  return data ?? [];
});
const { data: people } = useAsyncData<{ id: string; full_name: string | null; email: string }[]>("won-products-people", async () => {
  const { data } = await supabase.from("profiles").select("id, full_name, email").eq("is_active", true).order("full_name");
  return data ?? [];
});

const categoryItems = computed(() => (categories.value ?? []).map((c) => ({ label: c.name, value: c.id })));
const personItems = computed(() => [
  { label: t("cs.profile.noSalesPerson"), value: null as string | null },
  ...(people.value ?? []).map((u) => ({ label: u.full_name || u.email, value: u.id as string | null })),
]);
const yesNo = computed(() => [
  { label: t("cs.profile.notSet"), value: null as string | null },
  { label: t("cs.profile.yes"), value: "y" as string | null },
  { label: t("cs.profile.no"), value: "n" as string | null },
]);
// Stored as in_warranty / out_of_warranty and paid / unpaid.
const warrantyValue = (p: WonProductDraft) => (p.warranty_status === "in_warranty" ? "y" : p.warranty_status === "out_of_warranty" ? "n" : null);
const paymentValue = (p: WonProductDraft) => (p.payment_status === "paid" ? "y" : p.payment_status === "unpaid" ? "n" : null);

function add() {
  list.value = [...list.value, newWonProduct({ ...props.defaults, name: "" })];
}
function remove(index: number) {
  list.value = list.value.filter((_, i) => i !== index);
}
</script>

<template>
  <div class="space-y-3">
    <UAlert
      icon="i-lucide-package-check"
      color="primary"
      variant="subtle"
      :title="t('crm.deals.wonProducts.title')"
      :description="t('crm.deals.wonProducts.hint')"
    />

    <div v-for="(p, index) in list" :key="index" class="space-y-3 border border-default bg-default p-3">
      <div class="flex items-center justify-between gap-2">
        <span class="text-sm font-semibold text-highlighted">{{ t("crm.deals.wonProducts.product", { n: index + 1 }) }}</span>
        <UButton v-if="list.length > 1" icon="i-lucide-trash" size="xs" color="error" variant="ghost" :aria-label="t('common.delete')" @click="remove(index)" />
      </div>

      <UFormField :label="t('cs.profile.productName')" required>
        <UInput v-model="p.name" class="w-full" />
      </UFormField>
      <div class="grid gap-3 sm:grid-cols-2">
        <UFormField :label="t('cs.profile.category')" required>
          <USelect
            :model-value="p.category_id ?? undefined"
            :items="categoryItems"
            value-key="value"
            class="w-full"
            @update:model-value="(v: string | undefined) => (p.category_id = v ?? null)"
          />
        </UFormField>
        <UFormField :label="t('cs.profile.salesPerson')">
          <USelect v-model="p.sales_person_id" :items="personItems" value-key="value" class="w-full" />
        </UFormField>
        <UFormField :label="t('cs.profile.contractDate')" required>
          <UInput v-model="p.contract_date" type="date" class="w-full" />
        </UFormField>
        <UFormField :label="t('cs.profile.contractCode')">
          <UInput v-model="p.contract_code" dir="ltr" class="w-full" />
        </UFormField>
        <UFormField :label="t('cs.profile.warrantyLabel')">
          <USelect
            :model-value="warrantyValue(p)"
            :items="yesNo"
            value-key="value"
            class="w-full"
            @update:model-value="(v: string | null) => (p.warranty_status = v === 'y' ? 'in_warranty' : v === 'n' ? 'out_of_warranty' : null)"
          />
        </UFormField>
        <UFormField :label="t('cs.profile.paymentLabel')">
          <USelect
            :model-value="paymentValue(p)"
            :items="yesNo"
            value-key="value"
            class="w-full"
            @update:model-value="(v: string | null) => (p.payment_status = v === 'y' ? 'paid' : v === 'n' ? 'unpaid' : null)"
          />
        </UFormField>
      </div>
      <UFormField :label="t('cs.profile.warrantyDetails')">
        <UTextarea v-model="p.warranty_details" :rows="2" class="w-full" />
      </UFormField>
      <UFormField :label="t('cs.profile.notes')">
        <UTextarea v-model="p.notes" :rows="2" class="w-full" />
      </UFormField>
    </div>

    <UButton icon="i-lucide-plus" color="neutral" variant="soft" :label="t('crm.deals.wonProducts.add')" @click="add" />
  </div>
</template>
