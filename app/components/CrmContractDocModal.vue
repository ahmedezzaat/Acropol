<script setup lang="ts">
// Make (or change) the printed contract of a contract: the user types the values the template needs and the system
// issues the reference number when a new one is saved. The document then opens on its print page (Save as PDF).
const props = defineProps<{
  // the contract the document is made on, or the deal (before it has a contract)
  contractId?: string | null;
  dealId?: string | null;
  template: string;
  // what the form starts with (from the contract, its customer and its products)
  defaults: ContractDocVars;
  // an existing document being changed: its number stays
  document?: { id: string; ref: string; vars: ContractDocVars } | null;
}>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ saved: [id: string] }>();

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

const tpl = computed(() => templateByKey(props.template));
const form = reactive<ContractDocVars>({ ...props.defaults });
const saving = ref(false);
// each time the window opens it starts from the document being changed, or from the defaults
watch(open, (isOpen) => {
  if (isOpen) Object.assign(form, props.document?.vars ?? props.defaults);
});

const capacityItems = computed(() => (tpl.value?.capacities ?? []).map((c) => ({ label: `${c} ${t("crm.contracts.doc.litre")}`, value: c })));
const rest = computed(() => 100 - (form.advancePct ?? 0));
const valid = computed(() => !!form.date && form.ownerName.trim() && form.unitAddress.trim() && (form.value ?? 0) > 0 && (form.count ?? 0) > 0 && form.capacity > 0 && form.advancePct >= 0 && form.advancePct <= 100);

async function save() {
  if (!valid.value) return;
  saving.value = true;
  const { data, error } = await supabase.rpc("crm_save_contract_document", {
    p_contract_id: (props.contractId ?? null) as never,
    p_deal_id: (props.dealId ?? null) as never,
    p_document_id: (props.document?.id ?? null) as never,
    p_template: props.template,
    p_date: form.date,
    p_variables: { ...form, ownerName: form.ownerName.trim(), unitAddress: form.unitAddress.trim(), customerPhone: form.customerPhone.trim(), representative: form.representative.trim(), offerNo: form.offerNo.trim(), extras: form.extras.trim() } as never,
  });
  saving.value = false;
  if (error) {
    toast.add({ title: t("crm.contracts.doc.saveFailed"), description: error.message, color: "error" });
    return;
  }
  open.value = false;
  emit("saved", (data as { id: string }).id);
}
</script>

<template>
  <UModal v-model:open="open" :title="document ? t('crm.contracts.doc.editTitle') : t('crm.contracts.doc.newTitle')" :ui="{ content: 'max-w-2xl' }">
    <template #body>
      <div class="space-y-4">
        <p class="rounded-[10px] bg-muted px-3 py-2 text-sm text-toned">
          <template v-if="document">{{ t("crm.contracts.doc.refKept") }} <bdi dir="ltr" class="font-semibold">{{ document.ref }}</bdi></template>
          <template v-else>{{ t("crm.contracts.doc.refAuto") }}</template>
        </p>

        <div class="grid gap-3 sm:grid-cols-2">
          <UFormField :label="t('crm.contracts.doc.date')" required><UInput v-model="form.date" type="date" class="w-full" /></UFormField>
          <UFormField :label="t('crm.contracts.doc.offerNo')" :hint="t('crm.contracts.doc.offerNoHint')"><UInput v-model="form.offerNo" dir="ltr" class="w-full" /></UFormField>
        </div>

        <p class="text-sm font-medium text-highlighted">{{ t("crm.contracts.doc.partyOne") }}</p>
        <div class="grid gap-3 sm:grid-cols-2">
          <UFormField :label="t('crm.contracts.doc.ownerName')" required><UInput v-model="form.ownerName" class="w-full" /></UFormField>
          <UFormField :label="t('crm.contracts.doc.customerPhone')"><UInput v-model="form.customerPhone" dir="ltr" class="w-full" /></UFormField>
        </div>
        <UFormField :label="t('crm.contracts.doc.unitAddress')" required><UTextarea v-model="form.unitAddress" :rows="2" class="w-full" /></UFormField>

        <p class="text-sm font-medium text-highlighted">{{ t("crm.contracts.doc.partyTwo") }}</p>
        <UFormField :label="t('crm.contracts.doc.representative')" :hint="t('crm.contracts.doc.representativeHint')"><UInput v-model="form.representative" class="w-full" /></UFormField>

        <p class="text-sm font-medium text-highlighted">{{ t("crm.contracts.doc.equipment") }}</p>
        <div class="grid gap-3 sm:grid-cols-3">
          <UFormField :label="t('crm.contracts.doc.count')" required><UInputNumber v-model="form.count" :min="1" class="w-full" /></UFormField>
          <UFormField :label="t('crm.contracts.doc.capacity')" required><USelect v-model="form.capacity" :items="capacityItems" value-key="value" class="w-full" /></UFormField>
          <UFormField :label="t('crm.contracts.doc.extras')" :hint="t('crm.contracts.doc.extrasHint')"><UInput v-model="form.extras" class="w-full" /></UFormField>
        </div>

        <p class="text-sm font-medium text-highlighted">{{ t("crm.contracts.doc.payment") }}</p>
        <div class="grid gap-3 sm:grid-cols-2">
          <UFormField :label="t('crm.contracts.doc.value')" required><UInputNumber v-model="form.value" :min="0" class="w-full" /></UFormField>
          <UFormField :label="t('crm.contracts.doc.advance')" :hint="t('crm.contracts.doc.restHint', { rest })"><UInputNumber v-model="form.advancePct" :min="0" :max="100" class="w-full" /></UFormField>
        </div>

        <UButton :label="document ? t('common.save') : t('crm.contracts.doc.create')" icon="i-lucide-file-text" :loading="saving" :disabled="!valid" block @click="save" />
      </div>
    </template>
  </UModal>
</template>
