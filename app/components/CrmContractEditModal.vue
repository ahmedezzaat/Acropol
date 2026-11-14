<script setup lang="ts">
// Edit a contract (needs the CRM edit permission on contracts): its code, date, value, notes, the deal it belongs to
// and its file. Its products keep following the code and date by themselves.
const props = defineProps<{
  contract: { id: string; code: string; signed_on: string | null; value: number | null; notes: string | null; deal_id: string | null; file_name: string | null; file_path: string | null; customer_id: string; sales_person_id: string | null };
  // the deals of other contracts of this customer, which cannot be chosen again
  takenDealIds: string[];
}>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ saved: [] }>();

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

const code = ref("");
const signedOn = ref("");
const value = ref<number | null>(null);
const notes = ref("");
const dealId = ref<string | null>(null);
const salesPersonId = ref<string | null>(null);
const people = ref<{ label: string; value: string | null }[]>([]);
const newFile = ref<File | null>(null);
const removeFile = ref(false);
const saving = ref(false);

const dealOptions = ref<{ label: string; value: string }[]>([]);
watch(open, async (isOpen) => {
  if (!isOpen) return;
  code.value = props.contract.code ?? "";
  signedOn.value = props.contract.signed_on ?? "";
  value.value = props.contract.value;
  notes.value = props.contract.notes ?? "";
  dealId.value = props.contract.deal_id;
  salesPersonId.value = props.contract.sales_person_id;
  newFile.value = null;
  removeFile.value = false;
  const { data: staff } = await supabase.from("profiles").select("id, full_name, email").eq("is_active", true).order("full_name");
  people.value = [{ label: t("crm.contracts.noAgent"), value: null }, ...(staff ?? []).map((u) => ({ label: (u.full_name as string) || (u.email as string), value: u.id as string }))];
  const { data } = await supabase.from("deals").select("id, title").eq("customer_id", props.contract.customer_id).order("created_at", { ascending: false });
  dealOptions.value = (data ?? [])
    .filter((d) => d.id === props.contract.deal_id || !props.takenDealIds.includes(d.id as string))
    .map((d) => ({ label: (d.title as string) || "—", value: d.id as string }));
});

const valid = computed(() => !!code.value.trim() && !!signedOn.value);

async function save() {
  if (!valid.value) return;
  saving.value = true;
  const patch: Record<string, unknown> = {
    code: code.value.trim(),
    signed_on: signedOn.value,
    value: value.value,
    notes: notes.value.trim() || null,
    deal_id: dealId.value,
    // only sent when changed: an untouched contract keeps showing the agent of its products or deal
    ...(salesPersonId.value !== props.contract.sales_person_id ? { sales_person_id: salesPersonId.value } : {}),
  };
  // a new file goes first, into the private bucket, under the contract's own folder
  let uploaded: string | null = null;
  if (newFile.value) {
    uploaded = `${props.contract.id}/${Date.now()}-${newFile.value.name}`;
    const { error: uploadError } = await supabase.storage.from("contract-files").upload(uploaded, newFile.value);
    if (uploadError) {
      saving.value = false;
      toast.add({ title: t("crm.contracts.fileFailed"), description: uploadError.message, color: "error" });
      return;
    }
    patch.file_path = uploaded;
    patch.file_name = newFile.value.name;
  } else if (removeFile.value) {
    patch.file_path = null;
    patch.file_name = null;
  }
  const { error } = await supabase.rpc("crm_update_contract", { p_contract_id: props.contract.id, p_patch: patch as never });
  saving.value = false;
  if (error) {
    if (uploaded) await supabase.storage.from("contract-files").remove([uploaded]);
    toast.add({ title: t("crm.contracts.editFailed"), description: error.message, color: "error" });
    return;
  }
  // the replaced or removed file is not needed any more
  if ((newFile.value || removeFile.value) && props.contract.file_path) await supabase.storage.from("contract-files").remove([props.contract.file_path]);
  toast.add({ title: t("crm.contracts.edited"), color: "success" });
  open.value = false;
  emit("saved");
}
</script>

<template>
  <UModal v-model:open="open" :title="t('crm.contracts.editTitle')" :ui="{ content: 'max-w-xl' }">
    <template #body>
      <div class="space-y-4">
        <div class="grid gap-3 sm:grid-cols-2">
          <UFormField :label="t('crm.contracts.code')" required><UInput v-model="code" dir="ltr" class="w-full" /></UFormField>
          <UFormField :label="t('crm.contracts.signedOn')" required><UInput v-model="signedOn" type="date" class="w-full" /></UFormField>
        </div>
        <UFormField :label="t('crm.contracts.value')"><UInputNumber v-model="value" :min="0" class="w-full" /></UFormField>
        <UFormField v-if="dealOptions.length" :label="t('crm.contracts.deal')">
          <USelect v-model="dealId" :items="dealOptions" value-key="value" icon="i-lucide-handshake" :placeholder="t('crm.contracts.noDeal')" class="w-full" />
          <UButton v-if="dealId" size="xs" color="neutral" variant="link" :label="t('crm.contracts.clearDeal')" class="mt-1 px-0" @click="dealId = null" />
        </UFormField>
        <UFormField :label="t('crm.contracts.agent')"><USelect v-model="salesPersonId" :items="people" value-key="value" icon="i-lucide-user" class="w-full" /></UFormField>
        <UFormField :label="t('crm.contracts.notes')"><UTextarea v-model="notes" :rows="3" class="w-full" /></UFormField>
        <UFormField :label="t('crm.contracts.file')">
          <div v-if="contract.file_path && !newFile" class="mb-2 flex items-center justify-between gap-2 rounded-[10px] bg-muted px-3 py-2 text-sm">
            <span class="flex min-w-0 items-center gap-2" :class="removeFile && 'line-through opacity-60'"><UIcon name="i-lucide-paperclip" class="size-4 shrink-0 text-primary" /><bdi class="truncate">{{ contract.file_name || t("crm.contracts.file") }}</bdi></span>
            <UButton size="xs" color="neutral" variant="ghost" :label="removeFile ? t('common.cancel') : t('crm.contracts.removeFile')" @click="removeFile = !removeFile" />
          </div>
          <UFileUpload v-model="newFile" class="w-full" />
          <p v-if="contract.file_path && newFile" class="mt-1 text-xs text-muted">{{ t("crm.contracts.replaceFile") }}</p>
        </UFormField>
        <UButton :label="t('common.save')" :loading="saving" :disabled="!valid" block @click="save" />
      </div>
    </template>
  </UModal>
</template>
