<script setup lang="ts">
// Push a customer from the CRM to Customer Service: fill what is missing (area, address),
// hand the customer to a Customer Service agent and, optionally, record the products
// the customer bought. For people with the "push to Customer Service" permission.
const props = defineProps<{ customerId: string; customerName: string }>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ pushed: [] }>();

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

const areaId = ref<string | null>(null);
const address = ref("");
const agentId = ref<string | null>(null);
const boughtProducts = ref<WonProductDraft[]>([]);
const agents = ref<{ id: string; full_name: string | null; email: string }[]>([]);
const loading = ref(false);
const saving = ref(false);

const agentItems = computed(() => [
  { label: t("cs.customers.noAgent"), value: null as string | null },
  ...agents.value.map((u) => ({ label: u.full_name || u.email, value: u.id as string | null })),
]);

watch(open, async (isOpen) => {
  if (!isOpen) return;
  loading.value = true;
  boughtProducts.value = [];
  const [{ data: c }, { data: list, error }] = await Promise.all([
    supabase.from("customers").select("area_id, address, cs_agent_id").eq("id", props.customerId).maybeSingle(),
    supabase.rpc("crm_cs_agents"),
  ]);
  loading.value = false;
  areaId.value = c?.area_id ?? null;
  address.value = c?.address ?? "";
  agentId.value = c?.cs_agent_id ?? null;
  agents.value = list ?? [];
  if (error) toast.add({ title: t("crm.customers.pushFailed"), description: error.message, color: "error" });
});

const productsOk = computed(() => boughtProducts.value.every(wonProductValid));
const valid = computed(() => !loading.value && !!agentId.value && productsOk.value);

async function save() {
  if (!valid.value) return;
  saving.value = true;
  const { error } = await supabase.rpc("crm_push_customer_to_cs", {
    p_customer_id: props.customerId,
    p_area_id: areaId.value,
    p_address: address.value,
    p_cs_agent_id: agentId.value,
    p_products: boughtProducts.value.map((p) => ({
      name: p.name.trim(),
      category_id: p.category_id,
      contract_code: p.contract_code.trim(),
      contract_date: p.contract_date,
      sales_person_id: p.sales_person_id,
      warranty_status: p.warranty_status,
      warranty_details: p.warranty_details.trim(),
      payment_status: p.payment_status,
      notes: p.notes.trim(),
    })),
  });
  saving.value = false;
  if (error) {
    toast.add({ title: t("crm.customers.pushFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("crm.customers.pushed"), color: "success" });
  open.value = false;
  emit("pushed");
}
</script>

<template>
  <UModal v-model:open="open" :title="t('crm.customers.pushTitle', { name: customerName })">
    <template #body>
      <div class="space-y-4">
        <p class="text-sm text-muted">{{ t("crm.customers.pushHint") }}</p>
        <UFormField :label="t('cs.customers.agentCs')" required>
          <USelect v-model="agentId" :items="agentItems" :loading="loading" value-key="value" icon="i-lucide-user-round" class="w-full" />
        </UFormField>
        <UFormField :label="t('cs.customers.area')">
          <AreaSelect v-model="areaId" />
        </UFormField>
        <UFormField :label="t('cs.customers.address')">
          <UTextarea v-model="address" :rows="3" class="w-full" />
        </UFormField>
        <div class="space-y-2 border-t border-default pt-4">
          <h3 class="text-sm font-semibold text-highlighted">{{ t("cs.customers.boughtProducts") }}</h3>
          <WonProductsFields v-model="boughtProducts" optional />
        </div>
        <UButton :label="t('crm.customers.pushConfirm')" icon="i-lucide-send" :loading="saving" :disabled="!valid" size="lg" block @click="save" />
      </div>
    </template>
  </UModal>
</template>
