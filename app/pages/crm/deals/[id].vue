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
  pipeline_id: string;
  stage_id: string;
  stage_reason_id: string | null;
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

interface Pipeline {
  id: string;
  name: string;
}

interface Stage {
  id: string;
  pipeline_id: string;
  name: string;
  is_closed: boolean;
  reason_category: "archive" | "competitor" | null;
}

interface Reason {
  id: string;
  pipeline_id: string;
  category: "archive" | "competitor";
  name: string;
}

const deal = ref<Deal | null>(null);
const saving = ref(false);
const deleting = ref(false);
const canEdit = computed(() => hasPermission("crm_deals", "edit"));
const canDelete = computed(() => hasPermission("crm_deals", "delete"));
const canCreateQuote = computed(() => hasPermission("crm_quotes", "create"));

const { data: pipelines } = await useAsyncData<Pipeline[]>("crm-deal-pipelines", async () => {
  const { data, error } = await supabase.from("pipelines").select("id, name").order("sort_order");
  if (error) throw error;
  return data ?? [];
});
const { data: allStages } = await useAsyncData<Stage[]>("crm-deal-stages", async () => {
  const { data, error } = await supabase
    .from("pipeline_stages")
    .select("id, pipeline_id, name, is_closed, reason_category")
    .order("sort_order");
  if (error) throw error;
  return data ?? [];
});
const { data: allReasons } = await useAsyncData<Reason[]>("crm-deal-reasons", async () => {
  const { data, error } = await supabase
    .from("pipeline_stage_reasons")
    .select("id, pipeline_id, category, name")
    .order("sort_order");
  if (error) throw error;
  return data ?? [];
});

const pipelineOptions = computed(() => (pipelines.value ?? []).map((p) => ({ label: p.name, value: p.id })));
const stageOptions = computed(() =>
  (allStages.value ?? [])
    .filter((s) => s.pipeline_id === deal.value?.pipeline_id)
    .map((s) => ({ label: s.name, value: s.id })),
);
const currentStage = computed(() => allStages.value?.find((s) => s.id === deal.value?.stage_id));
const reasonOptions = computed(() =>
  (allReasons.value ?? [])
    .filter((r) => r.pipeline_id === deal.value?.pipeline_id && r.category === currentStage.value?.reason_category)
    .map((r) => ({ label: r.name, value: r.id })),
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

const { data: quotes } = await useAsyncData<Quote[]>(
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

function onPipelineChange() {
  if (!deal.value) return;
  const firstStage = allStages.value?.find((s) => s.pipeline_id === deal.value!.pipeline_id);
  deal.value.stage_id = firstStage?.id ?? "";
  deal.value.stage_reason_id = null;
}

function onStageChange() {
  if (!deal.value) return;
  deal.value.stage_reason_id = null;
}

async function save() {
  if (!deal.value) return;
  saving.value = true;
  const { error } = await supabase
    .from("deals")
    .update({
      title: deal.value.title,
      pipeline_id: deal.value.pipeline_id,
      stage_id: deal.value.stage_id,
      stage_reason_id: deal.value.stage_reason_id,
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
            <UFormField :label="t('crm.deals.pipeline')">
              <USelect
                v-model="deal.pipeline_id"
                :items="pipelineOptions"
                value-key="value"
                :disabled="!canEdit"
                class="w-full"
                @update:model-value="onPipelineChange"
              />
            </UFormField>
            <UFormField :label="t('crm.deals.stage')">
              <USelect
                v-model="deal.stage_id"
                :items="stageOptions"
                value-key="value"
                :disabled="!canEdit"
                class="w-full"
                @update:model-value="onStageChange"
              />
            </UFormField>
            <UFormField v-if="currentStage?.reason_category" :label="t('crm.deals.reason')">
              <USelect v-model="deal.stage_reason_id" :items="reasonOptions" value-key="value" :disabled="!canEdit" class="w-full" />
              <p v-if="!deal.stage_reason_id" class="mt-1 text-xs text-warning">{{ t("crm.deals.reasonRequired") }}</p>
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
