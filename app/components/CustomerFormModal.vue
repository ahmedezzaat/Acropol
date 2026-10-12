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
const { hasPermission } = usePermissions();
const me = useSupabaseUser();
const canAssign = computed(() => hasPermission("cs_customers", "assign"));
const people = ref<{ id: string; full_name: string | null; email: string }[]>([]);
const agentId = ref<string | null>(null);
// Products the customer bought, entered together with a new customer (optional).
const boughtProducts = ref<WonProductDraft[]>([]);

const editing = computed(() => !!props.customer);
const saving = ref(false);

const type = ref<"individual" | "company">("individual");
const name = ref("");
const company = ref("");
const phone = ref("");
const extraPhones = ref<string[]>([]);
const email = ref("");
const address = ref("");
const areaId = ref<string | null>(null);

watch(open, async (isOpen) => {
  if (!isOpen) return;
  await Promise.all([
    loadAreas(),
    canAssign.value
      ? supabase.rpc("cs_assignable_agents").then(({ data }) => (people.value = data ?? []))
      : Promise.resolve(),
  ]);
  const c = props.customer;
  // A new customer an agent adds starts with that agent (so they keep seeing it).
  agentId.value = c ? (c.cs_agent_id ?? null) : ((me.value?.sub as string | undefined) ?? null);
  boughtProducts.value = [];
  type.value = c ? (isCompanyCustomer(c) ? "company" : "individual") : "individual";
  name.value = c?.name ?? "";
  company.value = c?.company ?? "";
  phone.value = c?.phone ?? "";
  extraPhones.value = [...(c?.extra_phones ?? [])];
  email.value = c?.email ?? "";
  address.value = c?.address ?? "";
  areaId.value = c?.area_id ?? null;
});

const areaItems = computed(() => [
  { label: t("cs.customers.noArea"), value: null },
  ...areas.value.map((a) => ({ label: a.name, value: a.id })),
]);
const agentItems = computed(() => [
  { label: t("cs.customers.noAgent"), value: null as string | null },
  ...people.value.map((u) => ({ label: u.full_name || u.email, value: u.id as string | null })),
]);
const typeItems = computed(() => [
  { label: t("crm.leads.type.individual"), value: "individual" },
  { label: t("crm.leads.type.company"), value: "company" },
]);
// A company needs its name; the contact person is optional-but-expected, so
// only the company name is enforced there.
const valid = computed(
  () =>
    (type.value === "company" ? company.value.trim().length > 0 && name.value.trim().length > 0 : name.value.trim().length > 0) &&
    // Any product that was started must be complete.
    boughtProducts.value.every(wonProductValid),
);
const todayIso = () => {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
};
const productDefaults = computed(() => ({ contract_date: todayIso(), sales_person_id: (me.value?.sub as string | undefined) ?? null }));

async function save() {
  if (!valid.value) return;
  saving.value = true;
  const body = {
    name: name.value.trim(),
    // Individuals carry no company name — that is what makes a customer an individual.
    company: type.value === "company" ? company.value.trim() || null : null,
    phone: trimOrNull(phone.value),
    extra_phones: extraPhones.value.map((p) => p.trim()).filter((p) => p.length > 0),
    email: email.value.trim() || null,
    address: address.value.trim() || null,
    area_id: areaId.value,
    // Only someone allowed to assign sends the agent; for a new customer the
    // database defaults the rest to the creator's own view.
    ...(canAssign.value ? { cs_agent_id: agentId.value } : props.customer ? {} : { cs_agent_id: (me.value?.sub as string | undefined) ?? null }),
  };
  const { data, error } = props.customer
    ? await supabase.from("customers").update(body).eq("id", props.customer.id).select("id").single()
    : await supabase.from("customers").insert(body).select("id").single();
  saving.value = false;

  if (error || !data) {
    toast.add({ title: t("cs.customers.saveFailed"), description: error?.message, color: "error" });
    return;
  }
  // New customer: record the products they bought, if any were entered.
  if (!props.customer && boughtProducts.value.length) {
    const { error: productsError } = await supabase.from("customer_products").insert(
      boughtProducts.value.map((p) => ({
        customer_id: data.id,
        name: p.name.trim(),
        category_id: p.category_id,
        contract_code: p.contract_code.trim() || null,
        contract_date: p.contract_date || null,
        sales_person_id: p.sales_person_id,
        warranty_status: p.warranty_status,
        warranty_details: p.warranty_details.trim() || null,
        payment_status: p.payment_status,
        notes: p.notes.trim() || null,
      })),
    );
    if (productsError) {
      toast.add({ title: t("cs.customers.productsFailed"), description: productsError.message, color: "warning" });
    }
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
        <UFormField v-if="canAssign" :label="t('cs.customers.agent')" :help="t('cs.customers.agentHint')">
          <USelect v-model="agentId" :items="agentItems" value-key="value" icon="i-lucide-user-round" class="w-full" />
        </UFormField>
        <UFormField :label="t('common.extraPhones')">
          <ExtraPhones v-model="extraPhones" />
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
        <!-- Products the customer already bought (optional, new customers only) -->
        <div v-if="!editing" class="space-y-2 border-t border-default pt-4">
          <h3 class="text-sm font-semibold text-highlighted">{{ t("cs.customers.boughtProducts") }}</h3>
          <WonProductsFields v-model="boughtProducts" optional :defaults="productDefaults" />
        </div>
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
