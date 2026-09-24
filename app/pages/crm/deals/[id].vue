<script setup lang="ts">
definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "crm_deals" },
});

const route = useRoute();
const dealId = route.params.id as string;
const supabase = useSupabaseClient();
const toast = useToast();
const { hasPermission } = usePermissions();
const { t } = useI18n();

interface Deal {
  id: string;
  title: string;
  stage: string;
  value: number | null;
  expected_close_date: string | null;
  customer_id: string;
}

interface Customer {
  id: string;
  name: string;
}

interface Quote {
  id: string;
  quote_number: string;
  status: string;
  total: number;
}

const deal = ref<Deal | null>(null);
const saving = ref(false);
const deleting = ref(false);
const canEdit = computed(() => hasPermission("crm_deals", "edit"));
const canDelete = computed(() => hasPermission("crm_deals", "delete"));
const canCreateQuote = computed(() => hasPermission("crm_quotes", "create"));

const stageKeys = ["open", "proposal", "negotiation", "won", "lost"] as const;
const stageOptions = computed(() =>
  stageKeys.map((s) => ({ label: t(`crm.deals.stageValues.${s}`), value: s })),
);

const { status } = await useAsyncData(`crm-deal-${dealId}`, async () => {
  const { data, error } = await supabase.from("deals").select("*").eq("id", dealId).single();
  if (error) throw error;
  deal.value = data;
  return true;
});

const { data: customer } = await useAsyncData<Customer | null>(`crm-deal-${dealId}-customer`, async () => {
  if (!deal.value) return null;
  const { data, error } = await supabase
    .from("customers")
    .select("id, name")
    .eq("id", deal.value.customer_id)
    .single();
  if (error) throw error;
  return data;
});

const { data: quotes, refresh: refreshQuotes } = await useAsyncData<Quote[]>(
  `crm-deal-${dealId}-quotes`,
  async () => {
    const { data, error } = await supabase
      .from("quotes")
      .select("id, quote_number, status, total")
      .eq("deal_id", dealId)
      .order("created_at", { ascending: false });
    if (error) throw error;
    return data ?? [];
  },
);

async function save() {
  if (!deal.value) return;
  saving.value = true;
  const { error } = await supabase
    .from("deals")
    .update({
      title: deal.value.title,
      stage: deal.value.stage,
      value: deal.value.value,
      expected_close_date: deal.value.expected_close_date,
    })
    .eq("id", dealId);
  saving.value = false;

  if (error) {
    toast.add({ title: t("crm.deals.saveFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("crm.deals.dealSaved"), color: "success" });
}

async function remove() {
  deleting.value = true;
  const { error } = await supabase.from("deals").delete().eq("id", dealId);
  deleting.value = false;

  if (error) {
    toast.add({ title: t("crm.deals.deleteFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("crm.deals.dealDeleted"), color: "success" });
  navigateTo("/crm/deals");
}

const creatingQuote = ref(false);
async function createQuote() {
  if (!deal.value) return;
  creatingQuote.value = true;
  const { data, error } = await supabase
    .from("quotes")
    .insert({ deal_id: dealId, customer_id: deal.value.customer_id })
    .select()
    .single();
  creatingQuote.value = false;

  if (error) {
    toast.add({ title: t("crm.deals.createQuoteFailed"), description: error.message, color: "error" });
    return;
  }
  navigateTo(`/crm/quotes/${data.id}`);
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="deal?.title ?? t('crm.deals.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton v-if="canDelete" icon="i-lucide-trash" color="error" variant="soft" :loading="deleting" @click="remove" />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>

      <div v-else-if="deal" class="max-w-2xl space-y-8">
        <UPageCard :title="t('common.details')">
          <div class="space-y-4">
            <UFormField :label="t('crm.deals.customer')">
              <ULink :to="`/crm/customers/${deal.customer_id}`" class="text-primary">
                {{ customer?.name }}
              </ULink>
            </UFormField>
            <UFormField :label="t('crm.deals.dealTitle')">
              <UInput v-model="deal.title" :disabled="!canEdit" class="w-full" />
            </UFormField>
            <UFormField :label="t('crm.deals.stage')">
              <USelect v-model="deal.stage" :items="stageOptions" value-key="value" :disabled="!canEdit" class="w-full" />
            </UFormField>
            <UFormField :label="t('crm.deals.value')">
              <UInputNumber v-model="deal.value" :disabled="!canEdit" class="w-full" />
            </UFormField>
            <UFormField :label="t('crm.deals.expectedCloseDate')">
              <UInput v-model="deal.expected_close_date" type="date" :disabled="!canEdit" class="w-full" />
            </UFormField>
            <UButton v-if="canEdit" :label="t('common.save')" :loading="saving" @click="save" />
          </div>
        </UPageCard>

        <UPageCard :title="t('crm.deals.quotesTitle')">
          <template #footer v-if="canCreateQuote">
            <UButton :label="t('crm.deals.newQuote')" icon="i-lucide-plus" variant="soft" :loading="creatingQuote" @click="createQuote" />
          </template>
          <div v-if="!quotes?.length" class="text-sm text-muted">{{ t("crm.deals.noQuotesYet") }}</div>
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
