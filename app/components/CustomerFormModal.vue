<script setup lang="ts">
// Create or edit a customer from Customer Service. Beyond the CRM fields it
// takes the address (free text) and the area (from the list in Settings).
const props = defineProps<{ customer?: CsCustomer | null }>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ saved: [id: string] }>();

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();
const { areas, loadAreas } = useCs();

const editing = computed(() => !!props.customer);
const saving = ref(false);

const type = ref<"individual" | "company">("individual");
const name = ref("");
const company = ref("");
const phone = ref("");
const email = ref("");
const address = ref("");
const areaId = ref<string | null>(null);

watch(open, async (isOpen) => {
  if (!isOpen) return;
  await loadAreas();
  const c = props.customer;
  type.value = c ? (isCompanyCustomer(c) ? "company" : "individual") : "individual";
  name.value = c?.name ?? "";
  company.value = c?.company ?? "";
  phone.value = c?.phone ?? "";
  email.value = c?.email ?? "";
  address.value = c?.address ?? "";
  areaId.value = c?.area_id ?? null;
});

const areaItems = computed(() => [
  { label: t("cs.customers.noArea"), value: null },
  ...areas.value.map((a) => ({ label: a.name, value: a.id })),
]);
const typeItems = computed(() => [
  { label: t("crm.leads.type.individual"), value: "individual" },
  { label: t("crm.leads.type.company"), value: "company" },
]);
// A company needs its name; the contact person is optional-but-expected, so
// only the company name is enforced there.
const valid = computed(() =>
  type.value === "company" ? company.value.trim().length > 0 && name.value.trim().length > 0 : name.value.trim().length > 0,
);

async function save() {
  if (!valid.value) return;
  saving.value = true;
  const body = {
    name: name.value.trim(),
    // Individuals carry no company name — that is what makes a customer an individual.
    company: type.value === "company" ? company.value.trim() || null : null,
    phone: trimOrNull(phone.value),
    email: email.value.trim() || null,
    address: address.value.trim() || null,
    area_id: areaId.value,
  };
  const { data, error } = props.customer
    ? await supabase.from("customers").update(body).eq("id", props.customer.id).select("id").single()
    : await supabase.from("customers").insert(body).select("id").single();
  saving.value = false;

  if (error || !data) {
    toast.add({ title: t("cs.customers.saveFailed"), description: error?.message, color: "error" });
    return;
  }
  toast.add({ title: t(editing.value ? "cs.customers.saved" : "cs.customers.created"), color: "success" });
  open.value = false;
  emit("saved", data.id);
}
</script>

<template>
  <UModal v-model:open="open" :title="t(editing ? 'cs.customers.edit' : 'cs.customers.new')">
    <template #body>
      <div class="space-y-4">
        <UFormField :label="t('crm.leads.leadType')">
          <URadioGroup v-model="type" orientation="horizontal" :items="typeItems" value-key="value" />
        </UFormField>
        <UFormField v-if="type === 'company'" :label="t('crm.leads.companyName')" required>
          <UInput v-model="company" class="w-full" />
        </UFormField>
        <UFormField :label="type === 'company' ? t('crm.leads.contactPerson') : t('common.name')" required>
          <UInput v-model="name" class="w-full" />
        </UFormField>
        <UFormField :label="t('common.phone')">
          <PhoneInput v-model="phone" />
        </UFormField>
        <UFormField :label="t('common.email')">
          <UInput v-model="email" type="email" class="w-full" />
        </UFormField>
        <UFormField :label="t('cs.customers.area')">
          <USelect v-model="areaId" :items="areaItems" value-key="value" class="w-full" />
        </UFormField>
        <UFormField :label="t('cs.customers.address')">
          <UTextarea v-model="address" :rows="3" class="w-full" />
        </UFormField>
        <UButton
          :label="t(editing ? 'common.save' : 'cs.customers.create')"
          :loading="saving"
          :disabled="!valid"
          size="lg"
          block
          @click="save"
        />
      </div>
    </template>
  </UModal>
</template>
