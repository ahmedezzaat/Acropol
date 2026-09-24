<script setup lang="ts">
definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "crm_customers" },
});

const route = useRoute();
const customerId = route.params.id as string;
const supabase = useSupabaseClient();
const toast = useToast();
const { hasPermission } = usePermissions();
const { t } = useI18n();

interface Customer {
  id: string;
  name: string;
  company: string | null;
  phone: string | null;
  email: string | null;
  address: string | null;
}

interface Deal {
  id: string;
  title: string;
  stage: string;
  value: number | null;
}

interface Quote {
  id: string;
  quote_number: string;
  status: string;
  total: number;
}

const customer = ref<Customer | null>(null);
const saving = ref(false);
const canEdit = computed(() => hasPermission("crm_customers", "edit"));
const canDelete = computed(() => hasPermission("crm_customers", "delete"));

const { status } = await useAsyncData(`crm-customer-${customerId}`, async () => {
  const { data, error } = await supabase.from("customers").select("*").eq("id", customerId).single();
  if (error) throw error;
  customer.value = data;
  return true;
});

const { data: deals } = await useAsyncData<Deal[]>(`crm-customer-${customerId}-deals`, async () => {
  const { data, error } = await supabase
    .from("deals")
    .select("id, title, stage, value")
    .eq("customer_id", customerId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data ?? [];
});

const { data: quotes } = await useAsyncData<Quote[]>(`crm-customer-${customerId}-quotes`, async () => {
  const { data, error } = await supabase
    .from("quotes")
    .select("id, quote_number, status, total")
    .eq("customer_id", customerId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data ?? [];
});

async function save() {
  if (!customer.value) return;
  saving.value = true;
  const { error } = await supabase
    .from("customers")
    .update({
      name: customer.value.name,
      company: customer.value.company,
      phone: customer.value.phone,
      email: customer.value.email,
      address: customer.value.address,
    })
    .eq("id", customerId);
  saving.value = false;

  if (error) {
    toast.add({ title: t("crm.customers.saveFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("crm.customers.customerSaved"), color: "success" });
}

async function remove() {
  const { error } = await supabase.from("customers").delete().eq("id", customerId);
  if (error) {
    toast.add({ title: t("crm.customers.deleteFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("crm.customers.customerDeleted"), color: "success" });
  navigateTo("/crm/customers");
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="customer?.name ?? t('crm.customers.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton v-if="canDelete" icon="i-lucide-trash" color="error" variant="soft" @click="remove" />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>

      <div v-else-if="customer" class="max-w-2xl space-y-8">
        <UPageCard :title="t('common.details')">
          <div class="space-y-4">
            <UFormField :label="t('common.name')">
              <UInput v-model="customer.name" :disabled="!canEdit" class="w-full" />
            </UFormField>
            <UFormField :label="t('crm.customers.company')">
              <UInput v-model="customer.company" :disabled="!canEdit" class="w-full" />
            </UFormField>
            <UFormField :label="t('common.phone')">
              <UInput v-model="customer.phone" :disabled="!canEdit" class="w-full" />
            </UFormField>
            <UFormField :label="t('common.email')">
              <UInput v-model="customer.email" type="email" :disabled="!canEdit" class="w-full" />
            </UFormField>
            <UFormField :label="t('crm.customers.address')">
              <UTextarea v-model="customer.address" :disabled="!canEdit" class="w-full" />
            </UFormField>
            <UButton v-if="canEdit" :label="t('common.save')" :loading="saving" @click="save" />
          </div>
        </UPageCard>

        <UPageCard :title="t('crm.customers.dealsTitle')">
          <div v-if="!deals?.length" class="text-sm text-muted">{{ t("crm.customers.noDealsYet") }}</div>
          <ul v-else class="divide-y divide-default">
            <li v-for="deal in deals" :key="deal.id" class="py-2">
              <ULink :to="`/crm/deals/${deal.id}`" class="flex items-center justify-between">
                <span>{{ deal.title }}</span>
                <span class="text-sm text-muted">{{ t(`crm.deals.stageValues.${deal.stage}`) }} · {{ deal.value ?? "—" }}</span>
              </ULink>
            </li>
          </ul>
        </UPageCard>

        <UPageCard :title="t('crm.customers.quotesTitle')">
          <div v-if="!quotes?.length" class="text-sm text-muted">{{ t("crm.customers.noQuotesYet") }}</div>
          <ul v-else class="divide-y divide-default">
            <li v-for="quote in quotes" :key="quote.id" class="py-2">
              <ULink :to="`/crm/quotes/${quote.id}`" class="flex items-center justify-between">
                <span>{{ quote.quote_number }}</span>
                <span class="text-sm text-muted">{{ t(`crm.quotes.statusValues.${quote.status}`) }} · {{ quote.total }}</span>
              </ULink>
            </li>
          </ul>
        </UPageCard>
      </div>
    </template>
  </UDashboardPanel>
</template>
