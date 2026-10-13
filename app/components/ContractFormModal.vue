<script setup lang="ts">
// Add or edit a contract of a customer: its code, its date and a note. A
// contract holds one or more of the customer's products; the code and date are
// kept here once and shown on each product.
const props = defineProps<{ customerId: string; contract?: CsContract | null }>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ saved: [id: string] }>();

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

const code = ref("");
const signedOn = ref("");
const notes = ref("");
const saving = ref(false);
const editing = computed(() => !!props.contract);

const todayIso = () => {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
};

watch(open, (isOpen) => {
  if (!isOpen) return;
  code.value = props.contract?.code ?? "";
  signedOn.value = props.contract?.signed_on ?? (props.contract ? "" : todayIso());
  notes.value = props.contract?.notes ?? "";
});

async function save() {
  saving.value = true;
  const body = { code: code.value.trim() || null, signed_on: signedOn.value || null, notes: notes.value.trim() || null };
  const { data, error } = props.contract
    ? await supabase.from("contracts").update(body).eq("id", props.contract.id).select("id").single()
    : await supabase.from("contracts").insert({ ...body, customer_id: props.customerId }).select("id").single();
  saving.value = false;
  if (error || !data) {
    toast.add({ title: t("cs.profile.contractSaveFailed"), description: error?.message, color: "error" });
    return;
  }
  toast.add({ title: t("cs.profile.contractSaved"), color: "success" });
  open.value = false;
  emit("saved", data.id);
}
</script>

<template>
  <UModal v-model:open="open" :title="t(editing ? 'cs.profile.editContract' : 'cs.profile.addContract')">
    <template #body>
      <div class="space-y-4">
        <div class="grid gap-3 sm:grid-cols-2">
          <UFormField :label="t('cs.profile.contractCode')">
            <UInput v-model="code" dir="ltr" class="w-full" />
          </UFormField>
          <UFormField :label="t('cs.profile.contractDate')">
            <UInput v-model="signedOn" type="date" class="w-full" />
          </UFormField>
        </div>
        <UFormField :label="t('cs.profile.contractNotes')">
          <UTextarea v-model="notes" :rows="3" class="w-full" />
        </UFormField>
        <UButton :label="t('common.save')" :loading="saving" size="lg" block @click="save" />
      </div>
    </template>
  </UModal>
</template>
