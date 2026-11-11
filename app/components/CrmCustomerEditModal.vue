<script setup lang="ts">
// Edit the customer's details from where the contract is (needs the CRM edit permission on customers/contracts):
// name, company, phones, email, area and address. The customer's own page edits the same record.
const props = defineProps<{
  customer: { id: string; name: string; company: string | null; phone: string | null; extra_phones: string[] | null; extra_phone_names: string[] | null; email: string | null; address: string | null; area_id: string | null; notes: string | null; category_id: string | null };
}>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ saved: [] }>();

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

const name = ref("");
const company = ref("");
const phone = ref<string | null>(null);
const email = ref("");
const address = ref("");
const areaId = ref<string | null>(null);
const notes = ref("");
const categoryId = ref<string | null>(null);
const { loadCategories, categoryOptions } = useCustomerCategories();
loadCategories();
const extraContacts = ref(toExtraContacts(null, null));
const saving = ref(false);

// each time the window opens it starts from the customer as it is now
watch(open, (isOpen) => {
  if (!isOpen) return;
  const c = props.customer;
  name.value = c.name ?? "";
  company.value = c.company ?? "";
  phone.value = c.phone ?? null;
  email.value = c.email ?? "";
  address.value = c.address ?? "";
  areaId.value = c.area_id ?? null;
  notes.value = c.notes ?? "";
  categoryId.value = c.category_id ?? null;
  extraContacts.value = toExtraContacts(c.extra_phones, c.extra_phone_names);
}, { immediate: true });

const valid = computed(() => !!name.value.trim());

async function save() {
  if (!valid.value) return;
  saving.value = true;
  const { data, error } = await supabase
    .from("customers")
    .update({
      name: name.value.trim(),
      company: company.value.trim() || null,
      phone: trimOrNull(phone.value),
      ...fromExtraContacts(extraContacts.value),
      email: email.value.trim() || null,
      address: address.value.trim() || null,
      area_id: areaId.value || null,
      notes: notes.value.trim() || null,
      category_id: categoryId.value || null,
    })
    .eq("id", props.customer.id)
    .select("id");
  saving.value = false;
  // an update the database refuses silently changes no row
  if (error || !data?.length) {
    toast.add({ title: t("crm.customers.saveFailed"), description: error?.message, color: "error" });
    return;
  }
  toast.add({ title: t("crm.customers.customerSaved"), color: "success" });
  open.value = false;
  emit("saved");
}
</script>

<template>
  <UModal v-model:open="open" :title="t('crm.contracts.editCustomerTitle')" :ui="{ content: 'max-w-xl' }">
    <template #body>
      <div class="space-y-4">
        <div class="grid gap-3 sm:grid-cols-2">
          <UFormField :label="t('common.name')" required><UInput v-model="name" class="w-full" /></UFormField>
          <UFormField :label="t('crm.customers.company')"><UInput v-model="company" class="w-full" /></UFormField>
        </div>
        <UFormField :label="t('crm.leads.category')"><USelect v-model="categoryId" :items="categoryOptions" value-key="value" icon="i-lucide-layers" class="w-full" /></UFormField>
        <UFormField :label="t('common.phone')"><PhoneInput v-model="phone" /></UFormField>
        <UFormField :label="t('common.extraPhones')"><ExtraPhones v-model="extraContacts" /></UFormField>
        <UFormField :label="t('common.email')"><UInput v-model="email" type="email" class="w-full" /></UFormField>
        <UFormField :label="t('cs.customers.area')"><AreaSelect v-model="areaId" /></UFormField>
        <UFormField :label="t('crm.customers.address')"><UTextarea v-model="address" :rows="2" class="w-full" /></UFormField>
        <UFormField :label="t('crm.customers.notes')"><UTextarea v-model="notes" :rows="3" class="w-full" /></UFormField>
        <UButton :label="t('common.save')" :loading="saving" :disabled="!valid" block @click="save" />
      </div>
    </template>
  </UModal>
</template>
