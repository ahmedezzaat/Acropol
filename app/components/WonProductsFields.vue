<script setup lang="ts">
// The products bought in a deal, asked for when the deal is won: name, category,
// contract details, who sold it, warranty and payment. One block per product.
const list = defineModel<WonProductDraft[]>({ required: true });
const props = defineProps<{
  defaults?: Partial<WonProductDraft>;
  // For forms where products are optional: no intro banner, and even the last
  // product can be removed again.
  optional?: boolean;
}>();

const supabase = useSupabaseClient();
const { t } = useI18n();

const { data: categories } = useAsyncData<{ id: string; name: string; warranty_policies: WarrantyPolicy[] }[]>("won-products-categories", async () => {
  const { data } = await supabase.from("product_categories").select("id, name, warranty_policies").order("sort_order");
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

// The category's warranty policies (one per kind of product): a single policy
// fills the details when the category is picked and they are still empty; with
// several, you choose which one this product has.
function policiesOf(p: WonProductDraft) {
  return categories.value?.find((c) => c.id === p.category_id)?.warranty_policies ?? [];
}
const policyChoice = reactive<Record<number, number | undefined>>({});
function setCategory(p: WonProductDraft, id: string | undefined, index: number) {
  p.category_id = id ?? null;
  policyChoice[index] = undefined;
  const list = policiesOf(p);
  if (list.length === 1 && !p.warranty_details.trim()) p.warranty_details = list[0]!.text;
}
function choosePolicy(p: WonProductDraft, index: number, choice: number | undefined) {
  policyChoice[index] = choice;
  const policy = choice === undefined ? undefined : policiesOf(p)[choice];
  if (policy) p.warranty_details = policy.text;
}

// One contract holds all the products below: its code and date are entered once
// and copied onto every product (the first product is where they are read from).
function setContract(field: "contract_code" | "contract_date", value: string) {
  for (const p of list.value) p[field] = value;
}
function add() {
  const first = list.value[0];
  list.value = [
    ...list.value,
    newWonProduct({ ...props.defaults, name: "", ...(first ? { contract_code: first.contract_code, contract_date: first.contract_date } : {}) }),
  ];
}
function remove(index: number) {
  list.value = list.value.filter((_, i) => i !== index);
}
</script>

<template>
  <div class="space-y-3">
    <UAlert
      v-if="!optional"
      icon="i-lucide-package-check"
      color="primary"
      variant="subtle"
      :title="t('crm.deals.wonProducts.title')"
      :description="t('crm.deals.wonProducts.hint')"
    />

    <!-- The contract: once for all the products -->
    <div v-if="list.length" class="space-y-3 border border-primary/30 bg-primary/5 p-3">
      <div class="flex items-center gap-2 text-sm font-semibold text-highlighted">
        <UIcon name="i-lucide-file-signature" class="size-4" />{{ t("cs.profile.contract") }}
      </div>
      <div class="grid gap-3 sm:grid-cols-2">
        <UFormField :label="t('cs.profile.contractDate')" required>
          <UInput :model-value="list[0]!.contract_date" type="date" class="w-full" @update:model-value="(v: string | number) => setContract('contract_date', String(v))" />
        </UFormField>
        <UFormField :label="t('cs.profile.contractCode')">
          <UInput :model-value="list[0]!.contract_code" dir="ltr" class="w-full" @update:model-value="(v: string | number) => setContract('contract_code', String(v))" />
        </UFormField>
      </div>
      <p class="text-xs text-muted">{{ t("cs.profile.contractHint") }}</p>
    </div>

    <div v-for="(p, index) in list" :key="index" class="space-y-3 border border-default bg-default p-3">
      <div class="flex items-center justify-between gap-2">
        <span class="text-sm font-semibold text-highlighted">{{ t("crm.deals.wonProducts.product", { n: index + 1 }) }}</span>
        <UButton v-if="list.length > 1 || optional" icon="i-lucide-trash" size="xs" color="error" variant="ghost" :aria-label="t('common.delete')" @click="remove(index)" />
      </div>

      <div class="grid gap-3 sm:grid-cols-[1fr_7rem]">
        <UFormField :label="t('cs.profile.productName')" required>
          <UInput v-model="p.name" class="w-full" />
        </UFormField>
        <UFormField :label="t('cs.profile.quantity')" required>
          <UInput v-model.number="p.quantity" type="number" :min="1" step="1" class="w-full" />
        </UFormField>
      </div>
      <div class="grid gap-3 sm:grid-cols-2">
        <UFormField :label="t('cs.profile.category')" required>
          <USelect
            :model-value="p.category_id ?? undefined"
            :items="categoryItems"
            value-key="value"
            class="w-full"
            @update:model-value="(v: string | undefined) => setCategory(p, v, index)"
          />
        </UFormField>
        <UFormField :label="t('cs.profile.salesPerson')">
          <USelect v-model="p.sales_person_id" :items="personItems" value-key="value" class="w-full" />
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
        <USelect
          v-if="policiesOf(p).length"
          :model-value="policyChoice[index]"
          :items="policiesOf(p).map((x, i) => ({ label: x.name, value: i }))"
          value-key="value"
          :placeholder="t('cs.profile.chooseWarrantyPolicy')"
          icon="i-lucide-shield-check"
          size="sm"
          class="mt-1.5 w-full"
          @update:model-value="(v: number | undefined) => choosePolicy(p, index, v)"
        />
      </UFormField>
      <UFormField :label="t('cs.profile.notes')">
        <UTextarea v-model="p.notes" :rows="2" class="w-full" />
      </UFormField>
    </div>

    <UButton
      icon="i-lucide-plus"
      color="neutral"
      variant="soft"
      :label="optional && !list.length ? t('cs.customers.addBoughtProduct') : t('crm.deals.wonProducts.add')"
      @click="add"
    />
  </div>
</template>
