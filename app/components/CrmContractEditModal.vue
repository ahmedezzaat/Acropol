<script setup lang="ts">
// Edit a contract (needs the CRM edit permission on contracts): its code, date, value, notes, the deal it belongs to
// and its file. Its products keep following the code and date by themselves.
const props = defineProps<{
  contract: { id: string; contract_no?: string; code: string; signed_on: string | null; value: number | null; notes: string | null; deal_id: string | null; file_name: string | null; file_path: string | null; customer_id: string; sales_person_id: string | null };
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
// the contract's files: the ones it has (any can be marked for removal) and any number of new ones
interface ExistingFile { id: string; file_name: string; storage_path: string }
const existingFiles = ref<ExistingFile[]>([]);
const removeIds = ref<string[]>([]);
const newFiles = ref<File[]>([]);
const toggleRemove = (id: string) => (removeIds.value = removeIds.value.includes(id) ? removeIds.value.filter((x) => x !== id) : [...removeIds.value, id]);
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
  newFiles.value = [];
  removeIds.value = [];
  const { data: cf } = await supabase.from("contract_files").select("id, file_name, storage_path").eq("contract_id", props.contract.id).order("created_at").order("id");
  existingFiles.value = (cf ?? []) as ExistingFile[];
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
  // new files go first, into the private bucket, under the contract's own folder
  const base = Date.now();
  const uploaded: { name: string; path: string }[] = [];
  for (const [i, f] of newFiles.value.entries()) {
    const path = `${props.contract.id}/${base + i}-${storageSafeName(f.name)}`;
    const { error: uploadError } = await supabase.storage.from("contract-files").upload(path, f);
    if (uploadError) {
      if (uploaded.length) await supabase.storage.from("contract-files").remove(uploaded.map((u) => u.path));
      saving.value = false;
      toast.add({ title: t("crm.contracts.fileFailed"), description: `${f.name}: ${uploadError.message}`, color: "error" });
      return;
    }
    uploaded.push({ name: f.name, path });
  }
  const { error } = await supabase.rpc("crm_update_contract", { p_contract_id: props.contract.id, p_patch: patch as never });
  if (error) {
    if (uploaded.length) await supabase.storage.from("contract-files").remove(uploaded.map((u) => u.path));
    saving.value = false;
    toast.add({ title: t("crm.contracts.editFailed"), description: error.message, color: "error" });
    return;
  }
  // the files: the new ones are added, the ones marked are removed (the first remaining one stays the contract's main file)
  let filesError: string | null = null;
  if (uploaded.length) {
    const { error: addError } = await supabase.from("contract_files").insert(uploaded.map((u, i) => ({ contract_id: props.contract.id, file_name: u.name, storage_path: u.path, created_at: new Date(base + i).toISOString() })));
    if (addError) {
      filesError = addError.message;
      await supabase.storage.from("contract-files").remove(uploaded.map((u) => u.path));
    }
  }
  const removing = existingFiles.value.filter((f) => removeIds.value.includes(f.id));
  if (removing.length) {
    const { error: delError } = await supabase.from("contract_files").delete().in("id", removing.map((f) => f.id));
    if (delError) filesError = delError.message;
    else await supabase.storage.from("contract-files").remove(removing.map((f) => f.storage_path));
  }
  saving.value = false;
  if (filesError) toast.add({ title: t("crm.contracts.filesFailed"), description: filesError, color: "warning" });
  toast.add({ title: t("crm.contracts.edited"), color: "success" });
  open.value = false;
  emit("saved");
}
</script>

<template>
  <UModal v-model:open="open" :title="t('crm.contracts.editTitle')" :ui="{ content: 'max-w-xl' }">
    <template #body>
      <div class="space-y-4">
        <p v-if="contract.contract_no" class="rounded-[10px] bg-muted px-3 py-2 text-sm">{{ t("crm.contracts.number") }}: <bdi dir="ltr" class="font-semibold">{{ contract.contract_no }}</bdi></p>
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
          <ul v-if="existingFiles.length" class="mb-2 space-y-1.5">
            <li v-for="f in existingFiles" :key="f.id" class="flex items-center justify-between gap-2 rounded-[10px] bg-muted px-3 py-2 text-sm">
              <span class="flex min-w-0 items-center gap-2" :class="removeIds.includes(f.id) && 'line-through opacity-60'"><UIcon name="i-lucide-paperclip" class="size-4 shrink-0 text-primary" /><bdi class="truncate">{{ f.file_name }}</bdi></span>
              <UButton size="xs" color="neutral" variant="ghost" :label="removeIds.includes(f.id) ? t('common.cancel') : t('crm.contracts.removeFile')" @click="toggleRemove(f.id)" />
            </li>
          </ul>
          <UFileUpload v-model="newFiles" multiple class="w-full" />
        </UFormField>
        <UButton :label="t('common.save')" :loading="saving" :disabled="!valid" block @click="save" />
      </div>
    </template>
  </UModal>
</template>
