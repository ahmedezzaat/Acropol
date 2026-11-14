<script setup lang="ts">
// The contract form, the same wherever a contract is made (winning a deal, or "إنشاء عقد"): the contract itself
// (code, date, value, sales person, file, notes) and the products bought. The products take the contract's code and
// date, and its sales person (one choice for the contract and all its products).
const draft = defineModel<ContractDraft>({ required: true });

const supabase = useSupabaseClient();
const { t } = useI18n();

const { data: people } = useAsyncData("contract-form-people", async () => {
  const { data } = await supabase.from("profiles").select("id, full_name, email").eq("is_active", true).order("full_name");
  return data ?? [];
});
const peopleItems = computed(() => [
  { label: t("crm.contracts.noAgent"), value: null as string | null },
  ...(people.value ?? []).map((u) => ({ label: (u.full_name as string) || (u.email as string), value: u.id as string | null })),
]);

// the products follow the contract's code and date
watch(
  () => [draft.value.code, draft.value.signedOn, draft.value.products.length],
  () => {
    for (const p of draft.value.products) {
      p.contract_code = draft.value.code.trim();
      p.contract_date = draft.value.signedOn;
    }
  },
  { immediate: true },
);
// ...and its sales person: the contract's المسؤول عن العقد is the seller of every product (one choice, not two)
watch(
  () => [draft.value.salesPersonId, draft.value.products.length],
  () => {
    for (const p of draft.value.products) p.sales_person_id = draft.value.salesPersonId;
  },
  { immediate: true },
);
const productDefaults = computed(() => ({ contract_code: draft.value.code.trim(), contract_date: draft.value.signedOn, sales_person_id: draft.value.salesPersonId }));
</script>

<template>
  <div class="space-y-4">
    <div>
      <p class="text-sm font-semibold text-highlighted">{{ t("crm.contracts.contractSection") }}</p>
      <p class="text-xs text-muted">{{ t("crm.contracts.numberAuto") }}</p>
    </div>
    <div class="grid gap-3 sm:grid-cols-2">
      <UFormField :label="t('crm.contracts.code')" required><UInput v-model="draft.code" dir="ltr" class="w-full" /></UFormField>
      <UFormField :label="t('crm.contracts.signedOn')" required><UInput v-model="draft.signedOn" type="date" class="w-full" /></UFormField>
      <UFormField :label="t('crm.contracts.value')" required><UInputNumber v-model="draft.value" :min="0" class="w-full" /></UFormField>
      <UFormField :label="t('crm.contracts.agent')"><USelect v-model="draft.salesPersonId" :items="peopleItems" value-key="value" icon="i-lucide-user" class="w-full" /></UFormField>
    </div>
    <UFormField :label="t('crm.contracts.file')" :help="t('crm.contracts.fileHint')"><UFileUpload v-model="draft.file" class="w-full" /></UFormField>
    <UFormField :label="t('crm.contracts.notes')"><UTextarea v-model="draft.notes" :rows="2" class="w-full" /></UFormField>
    <div class="border-t border-default pt-4">
      <WonProductsFields v-model="draft.products" hide-contract hide-seller :defaults="productDefaults" />
    </div>
  </div>
</template>
