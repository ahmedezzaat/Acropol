<script setup lang="ts">
definePageMeta({ layout: "dashboard" });

const supabase = useSupabaseClient();
const { hasAnyModulePermission, hasPermission, loaded, load } = usePermissions();
const { t } = useI18n();

// This page isn't gated by a single crmPermission meta (it's open to
// anyone with access to any CRM resource), so the global middleware never
// triggers usePermissions().load() for it — load explicitly, same as
// crm/index.vue.
if (!loaded.value) await load();

const canLeads = computed(() => hasPermission("crm_leads", "view"));
const canDeals = computed(() => hasAnyModulePermission("crm_deals"));
const canCustomers = computed(() => hasAnyModulePermission("crm_customers"));
const canQuotes = computed(() => hasAnyModulePermission("crm_quotes"));
const hasAnyAccess = computed(
  () => canLeads.value || canDeals.value || canCustomers.value || canQuotes.value,
);

// --- Date range (scopes every count below to created_at within it) ---
function isoDate(d: Date) {
  return d.toISOString().slice(0, 10);
}
function rangeStartIso(d: string) {
  return new Date(`${d}T00:00:00`).toISOString();
}
function rangeEndIso(d: string) {
  return new Date(`${d}T23:59:59.999`).toISOString();
}

const monthAgo = new Date();
monthAgo.setDate(monthAgo.getDate() - 30);
const fromDate = ref(isoDate(monthAgo));
const toDate = ref(isoDate(new Date()));

function setPreset(preset: "7d" | "30d" | "month" | "all") {
  const now = new Date();
  if (preset === "all") {
    fromDate.value = "2000-01-01";
    toDate.value = isoDate(now);
    return;
  }
  if (preset === "month") {
    fromDate.value = isoDate(new Date(now.getFullYear(), now.getMonth(), 1));
    toDate.value = isoDate(now);
    return;
  }
  const days = preset === "7d" ? 7 : 30;
  const start = new Date();
  start.setDate(start.getDate() - days);
  fromDate.value = isoDate(start);
  toDate.value = isoDate(now);
}

// --- Data (RLS scopes every query to what the current user can see —
// including team visibility, same as everywhere else in the app) ---
interface LeadRow {
  id: string;
  lead_type: "individual" | "company";
}
interface DealRow {
  id: string;
  stage_id: string;
  pipeline_id: string;
  assigned_to: string | null;
}
interface Profile {
  id: string;
  full_name: string | null;
  email: string;
  team_id: string | null;
}
interface Team {
  id: string;
  name: string;
}
interface Stage {
  id: string;
  name: string;
  pipeline_id: string;
  sort_order: number;
}
interface Pipeline {
  id: string;
  name: string;
  sort_order: number;
}

const __ad1 = useAsyncData<LeadRow[]>(
  "dashboard-leads",
  async () => {
    if (!canLeads.value) return [];
    const { data, error } = await supabase
      .from("leads")
      .select("id, lead_type")
      .gte("created_at", rangeStartIso(fromDate.value))
      .lte("created_at", rangeEndIso(toDate.value));
    if (error) throw error;
    return data ?? [];
  },
  { watch: [fromDate, toDate] },
);
const { data: leadsData, status: leadsStatus } = __ad1;

const __ad2 = useAsyncData<DealRow[]>(
  "dashboard-deals",
  async () => {
    if (!canDeals.value) return [];
    const { data, error } = await supabase
      .from("deals")
      .select("id, stage_id, pipeline_id, assigned_to")
      .gte("created_at", rangeStartIso(fromDate.value))
      .lte("created_at", rangeEndIso(toDate.value));
    if (error) throw error;
    return data ?? [];
  },
  { watch: [fromDate, toDate] },
);
const { data: dealsData, status: dealsStatus } = __ad2;

const __ad3 = useAsyncData<number>(
  "dashboard-customers-count",
  async () => {
    if (!canCustomers.value) return 0;
    const { count, error } = await supabase
      .from("customers")
      .select("id", { count: "exact", head: true })
      .gte("created_at", rangeStartIso(fromDate.value))
      .lte("created_at", rangeEndIso(toDate.value));
    if (error) throw error;
    return count ?? 0;
  },
  { watch: [fromDate, toDate] },
);
const { data: customersCount } = __ad3;

const __ad4 = useAsyncData<number>(
  "dashboard-quotes-count",
  async () => {
    if (!canQuotes.value) return 0;
    const { count, error } = await supabase
      .from("quotes")
      .select("id", { count: "exact", head: true })
      .gte("created_at", rangeStartIso(fromDate.value))
      .lte("created_at", rangeEndIso(toDate.value));
    if (error) throw error;
    return count ?? 0;
  },
  { watch: [fromDate, toDate] },
);
const { data: quotesCount } = __ad4;

// Reference data — not date-filtered, just used to label the breakdowns.
const __ad5 = useAsyncData<Pipeline[]>("dashboard-pipelines", async () => {
  if (!canDeals.value) return [];
  const { data, error } = await supabase.from("pipelines").select("id, name, sort_order").order("sort_order");
  if (error) throw error;
  return data ?? [];
});
const { data: pipelines } = __ad5;
const __ad6 = useAsyncData<Stage[]>("dashboard-stages", async () => {
  if (!canDeals.value) return [];
  const { data, error } = await supabase
    .from("pipeline_stages")
    .select("id, name, pipeline_id, sort_order")
    .order("sort_order");
  if (error) throw error;
  return data ?? [];
});
const { data: stages } = __ad6;
const __ad7 = useAsyncData<Profile[]>("dashboard-profiles", async () => {
  if (!canDeals.value && !canCustomers.value) return [];
  const { data, error } = await supabase
    .from("profiles")
    .select("id, full_name, email, team_id")
    .eq("is_active", true);
  if (error) throw error;
  return data ?? [];
});
const { data: profiles } = __ad7;
const __ad8 = useAsyncData<Team[]>("dashboard-teams", async () => {
  if (!canDeals.value && !canCustomers.value) return [];
  const { data, error } = await supabase.from("teams").select("id, name");
  if (error) throw error;
  return data ?? [];
});
const { data: teams } = __ad8;

// Sales volume: the value of the contracts made in the period (by the contract's own date, else when it was made).
// A contract's value is its own, else its deal's.
interface ContractRow {
  id: string;
  signed_on: string | null;
  created_at: string;
  value: number | null;
  deal: { value: number | null; assigned_to: string | null } | null;
  products: { sales_person_id: string | null }[] | null;
}
const __ad9 = useAsyncData<ContractRow[]>(
  "dashboard-contracts",
  async () => {
    if (!canCustomers.value) return [];
    const a = fromDate.value;
    const b = toDate.value;
    return fetchAll<ContractRow>((from, to) =>
      supabase
        .from("contracts")
        .select("id, signed_on, created_at, value, deal:deals(value, assigned_to), products:customer_products(sales_person_id)")
        .or(`and(signed_on.gte.${a},signed_on.lte.${b}),and(signed_on.is.null,created_at.gte.${rangeStartIso(a)},created_at.lte.${rangeEndIso(b)})`)
        .order("id")
        .range(from, to) as never,
    );
  },
  { watch: [fromDate, toDate] },
);
const { data: contractsData } = __ad9;

// Load everything at once instead of one request after another.
await Promise.all([__ad1, __ad2, __ad3, __ad4, __ad5, __ad6, __ad7, __ad8, __ad9]);

const isLoading = computed(
  () => !loaded.value || leadsStatus.value === "pending" || dealsStatus.value === "pending",
);

// --- Aggregates (small datasets — aggregating client-side is simpler than
// a bespoke RPC per breakdown, and RLS already did the real filtering) ---
const leadsIndividualCount = computed(
  () => (leadsData.value ?? []).filter((l) => l.lead_type === "individual").length,
);
const leadsCompanyCount = computed(
  () => (leadsData.value ?? []).filter((l) => l.lead_type === "company").length,
);

function profileLabel(id: string | null) {
  if (!id) return t("common.unassigned");
  const p = profiles.value?.find((p) => p.id === id);
  return p?.full_name || p?.email || "?";
}
function teamName(id: string | null) {
  if (!id) return t("crm.dashboard.noTeam");
  return teams.value?.find((tm) => tm.id === id)?.name ?? "—";
}

// --- Sales volume (from contracts) ---
const { locale } = useI18n();
const money = (v: number) => formatReportMoney(v, t("common.currency"));
const contractValue = (c: ContractRow) => (c.value != null ? Number(c.value) : c.deal?.value != null ? Number(c.deal.value) : 0);
const salesTotal = computed(() => (contractsData.value ?? []).reduce((n, c) => n + contractValue(c), 0));
const salesCount = computed(() => contractsData.value?.length ?? 0);
const salesAverage = computed(() => (salesCount.value ? Math.round(salesTotal.value / salesCount.value) : 0));

interface SalesRow {
  label: string;
  value: number;
  count: number;
}
const monthFmt = computed(() => new Intl.DateTimeFormat(locale.value, { month: "long", year: "numeric" }));
const salesByMonth = computed<SalesRow[]>(() => {
  const m = new Map<string, SalesRow>();
  for (const c of contractsData.value ?? []) {
    const key = (c.signed_on ?? c.created_at).slice(0, 7);
    const row = m.get(key) ?? { label: key, value: 0, count: 0 };
    row.value += contractValue(c);
    row.count += 1;
    m.set(key, row);
  }
  return [...m.values()]
    .sort((a, b) => a.label.localeCompare(b.label))
    .map((r) => ({ ...r, label: monthFmt.value.format(new Date(`${r.label}-01T12:00:00`)) }));
});
const salesByMonthMax = computed(() => Math.max(1, ...salesByMonth.value.map((r) => r.value)));

// the salespeople recorded on a contract's products share its value; none recorded: its deal's agent; none: unassigned
function contractAgents(c: ContractRow): (string | null)[] {
  const ids = [...new Set((c.products ?? []).map((p) => p.sales_person_id).filter((x): x is string => !!x))];
  if (ids.length) return ids;
  return [c.deal?.assigned_to ?? null];
}
const salesByAgent = computed<(SalesRow & { share: number })[]>(() => {
  const m = new Map<string, SalesRow>();
  for (const c of contractsData.value ?? []) {
    const agents = contractAgents(c);
    for (const id of agents) {
      const key = id ?? "unassigned";
      const row = m.get(key) ?? { label: id ? profileLabel(id) : t("common.unassigned"), value: 0, count: 0 };
      row.value += contractValue(c) / agents.length;
      row.count += 1 / agents.length;
      m.set(key, row);
    }
  }
  return [...m.values()].sort((a, b) => b.value - a.value).map((r) => ({ ...r, share: salesTotal.value ? r.value / salesTotal.value : 0 }));
});
const salesByTeam = computed<(SalesRow & { share: number })[]>(() => {
  const m = new Map<string, SalesRow>();
  for (const c of contractsData.value ?? []) {
    const agents = contractAgents(c);
    for (const id of agents) {
      const teamId = id ? profiles.value?.find((p) => p.id === id)?.team_id ?? null : null;
      const key = teamId ?? "no-team";
      const row = m.get(key) ?? { label: teamId ? teamName(teamId) : t("crm.dashboard.noTeam"), value: 0, count: 0 };
      row.value += contractValue(c) / agents.length;
      row.count += 1 / agents.length;
      m.set(key, row);
    }
  }
  return [...m.values()].sort((a, b) => b.value - a.value).map((r) => ({ ...r, share: salesTotal.value ? r.value / salesTotal.value : 0 }));
});

interface StageCount {
  pipeline: string;
  stage: string;
  pipelineSort: number;
  stageSort: number;
  // Position within its own pipeline's stage order (0-based) — a stage is
  // ordinal, not nominal: swapping two stages changes the funnel's meaning,
  // so its color should encode "how far along", not just "which one".
  stageRank: number;
  count: number;
}
const dealsByStage = computed<StageCount[]>(() => {
  const counts = new Map<string, number>();
  for (const d of dealsData.value ?? []) {
    counts.set(d.stage_id, (counts.get(d.stage_id) ?? 0) + 1);
  }
  const rows: StageCount[] = [];
  for (const [stageId, count] of counts) {
    const stage = stages.value?.find((s) => s.id === stageId);
    const pipeline = pipelines.value?.find((p) => p.id === stage?.pipeline_id);
    const pipelineStages = (stages.value ?? [])
      .filter((s) => s.pipeline_id === stage?.pipeline_id)
      .sort((a, b) => a.sort_order - b.sort_order);
    rows.push({
      pipeline: pipeline?.name ?? "—",
      stage: stage?.name ?? "—",
      pipelineSort: pipeline?.sort_order ?? 0,
      stageSort: stage?.sort_order ?? 0,
      stageRank: Math.max(0, pipelineStages.findIndex((s) => s.id === stageId)),
      count,
    });
  }
  return rows.sort((a, b) => a.pipelineSort - b.pipelineSort || a.stageSort - b.stageSort);
});

const dealsByStageMax = computed(() => Math.max(1, ...dealsByStage.value.map((r) => r.count)));

// Ordinal ramp: one hue (the app's own brand primary), monotone lightness
// per stage position — light/dark pairs so each mode independently reads
// as a clear light->dark progression against its own surface.
const stageOrdinalSteps = [
  "bg-kords-primary-200 dark:bg-kords-primary-900",
  "bg-kords-primary-300 dark:bg-kords-primary-800",
  "bg-kords-primary-400 dark:bg-kords-primary-700",
  "bg-kords-primary-500 dark:bg-kords-primary-600",
  "bg-kords-primary-600 dark:bg-kords-primary-500",
  "bg-kords-primary-700 dark:bg-kords-primary-400",
  "bg-kords-primary-800 dark:bg-kords-primary-300",
  "bg-kords-primary-900 dark:bg-kords-primary-200",
  "bg-kords-primary-950 dark:bg-kords-primary-100",
];
function stageBarClass(rank: number) {
  return stageOrdinalSteps[Math.min(rank, stageOrdinalSteps.length - 1)];
}

interface AgentCount {
  agent: string;
  count: number;
}
const dealsByAgent = computed<AgentCount[]>(() => {
  const counts = new Map<string, number>();
  for (const d of dealsData.value ?? []) {
    const key = d.assigned_to ?? "unassigned";
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  return [...counts.entries()]
    .map(([id, count]) => ({
      agent: id === "unassigned" ? t("common.unassigned") : profileLabel(id),
      count,
    }))
    .sort((a, b) => b.count - a.count);
});

interface TeamCount {
  team: string;
  count: number;
}
const dealsByTeam = computed<TeamCount[]>(() => {
  const counts = new Map<string, number>();
  for (const d of dealsData.value ?? []) {
    const profile = d.assigned_to ? profiles.value?.find((p) => p.id === d.assigned_to) : null;
    const key = profile?.team_id ?? "no-team";
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  return [...counts.entries()]
    .map(([id, count]) => ({ team: id === "no-team" ? t("crm.dashboard.noTeam") : teamName(id), count }))
    .sort((a, b) => b.count - a.count);
});
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="t('crm.dashboard.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
      </UDashboardNavbar>

      <UDashboardToolbar v-if="hasAnyAccess">
        <template #left>
          <UFormField :label="t('crm.dashboard.fromDate')">
            <UInput v-model="fromDate" type="date" />
          </UFormField>
          <UFormField :label="t('crm.dashboard.toDate')">
            <UInput v-model="toDate" type="date" />
          </UFormField>
        </template>
        <template #right>
          <UButton
            :label="t('crm.dashboard.last7Days')"
            color="neutral"
            variant="soft"
            size="sm"
            @click="setPreset('7d')"
          />
          <UButton
            :label="t('crm.dashboard.last30Days')"
            color="neutral"
            variant="soft"
            size="sm"
            @click="setPreset('30d')"
          />
          <UButton
            :label="t('crm.dashboard.thisMonth')"
            color="neutral"
            variant="soft"
            size="sm"
            @click="setPreset('month')"
          />
          <UButton
            :label="t('crm.dashboard.allTime')"
            color="neutral"
            variant="soft"
            size="sm"
            @click="setPreset('all')"
          />
        </template>
      </UDashboardToolbar>
    </template>

    <template #body>
      <div v-if="!hasAnyAccess" class="py-16 text-center text-muted">{{ t("crm.noAccess") }}</div>

      <div v-else-if="isLoading" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>

      <div v-else class="space-y-6">
        <div class="grid grid-cols-2 gap-4 md:grid-cols-4">
          <UPageCard class="kords-card" v-if="canLeads" to="/crm/leads">
            <div class="text-2xl font-bold text-highlighted">{{ leadsData?.length ?? 0 }}</div>
            <div class="text-sm text-muted">{{ t("crm.dashboard.totalLeads") }}</div>
          </UPageCard>
          <UPageCard class="kords-card" v-if="canDeals" to="/crm/deals?assignee=all">
            <div class="text-2xl font-bold text-highlighted">{{ dealsData?.length ?? 0 }}</div>
            <div class="text-sm text-muted">{{ t("crm.dashboard.totalDeals") }}</div>
          </UPageCard>
          <UPageCard class="kords-card" v-if="canCustomers" to="/crm/customers">
            <div class="text-2xl font-bold text-highlighted">{{ customersCount ?? 0 }}</div>
            <div class="text-sm text-muted">{{ t("crm.dashboard.totalCustomers") }}</div>
          </UPageCard>
          <!-- Quotes stat card hidden alongside the rest of the Quotes
          feature — see crm/deals/[id].vue and layouts/dashboard.vue. -->
        </div>

        <!-- Sales volume: the value of the contracts made in the period -->
        <template v-if="canCustomers">
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
            <UPageCard class="kords-card" to="/crm/contracts">
              <div class="text-2xl font-bold text-highlighted">{{ money(salesTotal) }}</div>
              <div class="text-sm text-muted">{{ t("crm.dashboard.salesVolume") }}</div>
            </UPageCard>
            <UPageCard class="kords-card" to="/crm/contracts">
              <div class="text-2xl font-bold text-highlighted">{{ salesCount }}</div>
              <div class="text-sm text-muted">{{ t("crm.dashboard.contractsCount") }}</div>
            </UPageCard>
            <UPageCard class="kords-card">
              <div class="text-2xl font-bold text-highlighted">{{ money(salesAverage) }}</div>
              <div class="text-sm text-muted">{{ t("crm.dashboard.avgContract") }}</div>
            </UPageCard>
          </div>

          <UPageCard class="kords-card" :title="t('crm.dashboard.salesByMonth')" :description="t('crm.dashboard.salesBasis')">
            <div v-if="!salesByMonth.length" class="text-sm text-muted">{{ t("crm.dashboard.noData") }}</div>
            <div v-else class="space-y-3">
              <div v-for="row in salesByMonth" :key="row.label" class="space-y-1">
                <div class="flex items-baseline justify-between gap-2 text-xs">
                  <span class="text-highlighted">{{ row.label }} <span class="text-muted">· {{ t("crm.dashboard.contractsN", { n: row.count }) }}</span></span>
                  <span class="font-medium text-highlighted">{{ money(row.value) }}</span>
                </div>
                <div class="h-2.5 w-full overflow-hidden rounded-full bg-elevated">
                  <div class="h-full rounded-full bg-kords-primary-500" :style="{ width: `${(row.value / salesByMonthMax) * 100}%` }" />
                </div>
              </div>
            </div>
          </UPageCard>

          <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
            <UPageCard v-for="block in [{ key: 'agent', title: t('crm.dashboard.salesByAgent'), rows: salesByAgent, head: t('crm.dashboard.agent') }, { key: 'team', title: t('crm.dashboard.salesByTeam'), rows: salesByTeam, head: t('crm.dashboard.team') }]" :key="block.key" class="kords-card" :title="block.title">
              <div v-if="!block.rows.length" class="text-sm text-muted">{{ t("crm.dashboard.noData") }}</div>
              <table v-else class="w-full text-sm">
                <thead>
                  <tr class="text-start text-muted">
                    <th class="py-1 text-start font-medium">{{ block.head }}</th>
                    <th class="py-1 text-end font-medium">{{ t("crm.dashboard.contractsCount") }}</th>
                    <th class="py-1 text-end font-medium">{{ t("crm.dashboard.salesVolume") }}</th>
                    <th class="py-1 text-end font-medium">%</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="row in block.rows" :key="row.label" class="border-t border-default">
                    <td class="py-1.5 text-highlighted">{{ row.label }}</td>
                    <td class="py-1.5 text-end">{{ Math.round(row.count * 10) / 10 }}</td>
                    <td class="whitespace-nowrap py-1.5 text-end font-medium text-highlighted">{{ money(row.value) }}</td>
                    <td class="py-1.5 text-end text-muted">{{ Math.round(row.share * 100) }}%</td>
                  </tr>
                </tbody>
              </table>
            </UPageCard>
          </div>
        </template>

        <UPageCard class="kords-card" v-if="canLeads" :title="t('crm.dashboard.leadsByType')">
          <div v-if="!leadsData?.length" class="text-sm text-muted">{{ t("crm.dashboard.noData") }}</div>
          <div v-else class="flex gap-8">
            <div>
              <div class="text-xl font-semibold text-highlighted">{{ leadsIndividualCount }}</div>
              <div class="text-sm text-muted">{{ t("crm.dashboard.individuals") }}</div>
            </div>
            <div>
              <div class="text-xl font-semibold text-highlighted">{{ leadsCompanyCount }}</div>
              <div class="text-sm text-muted">{{ t("crm.dashboard.companies") }}</div>
            </div>
          </div>
        </UPageCard>

        <UPageCard class="kords-card" v-if="canDeals" :title="t('crm.dashboard.dealsByStage')">
          <div v-if="!dealsByStage.length" class="text-sm text-muted">{{ t("crm.dashboard.noData") }}</div>
          <template v-else>
            <!-- One hue, lightness stepped by position in the funnel (a
                 stage is ordinal, not just "which one") — darker/lighter
                 means further along, not a different category. -->
            <div class="space-y-3">
              <div v-for="row in dealsByStage" :key="`${row.pipeline}-${row.stage}`" class="space-y-1">
                <div class="flex items-baseline justify-between gap-2 text-xs">
                  <span class="text-muted">{{ row.pipeline }} · <span class="text-highlighted">{{ row.stage }}</span></span>
                  <span class="font-medium text-highlighted">{{ row.count }}</span>
                </div>
                <div class="h-2.5 w-full overflow-hidden rounded-full bg-elevated">
                  <div
                    class="h-full rounded-full"
                    :class="stageBarClass(row.stageRank)"
                    :style="{ width: `${(row.count / dealsByStageMax) * 100}%` }"
                  />
                </div>
              </div>
            </div>

            <table class="mt-6 w-full text-sm">
              <thead>
                <tr class="text-start text-muted">
                  <th class="py-1 text-start font-medium">{{ t("crm.dashboard.pipeline") }}</th>
                  <th class="py-1 text-start font-medium">{{ t("crm.dashboard.stage") }}</th>
                  <th class="py-1 text-end font-medium">{{ t("crm.dashboard.count") }}</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="row in dealsByStage" :key="`table-${row.pipeline}-${row.stage}`" class="border-t border-default">
                  <td class="py-1.5 text-muted">{{ row.pipeline }}</td>
                  <td class="py-1.5 text-highlighted">{{ row.stage }}</td>
                  <td class="py-1.5 text-end font-medium text-highlighted">{{ row.count }}</td>
                </tr>
              </tbody>
            </table>
          </template>
        </UPageCard>

        <div v-if="canDeals" class="grid grid-cols-1 gap-6 lg:grid-cols-2">
          <UPageCard class="kords-card" :title="t('crm.dashboard.dealsByAgent')">
            <div v-if="!dealsByAgent.length" class="text-sm text-muted">{{ t("crm.dashboard.noData") }}</div>
            <table v-else class="w-full text-sm">
              <thead>
                <tr class="text-start text-muted">
                  <th class="py-1 text-start font-medium">{{ t("crm.dashboard.agent") }}</th>
                  <th class="py-1 text-end font-medium">{{ t("crm.dashboard.count") }}</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="row in dealsByAgent" :key="row.agent" class="border-t border-default">
                  <td class="py-1.5 text-highlighted">{{ row.agent }}</td>
                  <td class="py-1.5 text-end font-medium text-highlighted">{{ row.count }}</td>
                </tr>
              </tbody>
            </table>
          </UPageCard>

          <UPageCard class="kords-card" :title="t('crm.dashboard.dealsByTeam')">
            <div v-if="!dealsByTeam.length" class="text-sm text-muted">{{ t("crm.dashboard.noData") }}</div>
            <table v-else class="w-full text-sm">
              <thead>
                <tr class="text-start text-muted">
                  <th class="py-1 text-start font-medium">{{ t("crm.dashboard.team") }}</th>
                  <th class="py-1 text-end font-medium">{{ t("crm.dashboard.count") }}</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="row in dealsByTeam" :key="row.team" class="border-t border-default">
                  <td class="py-1.5 text-highlighted">{{ row.team }}</td>
                  <td class="py-1.5 text-end font-medium text-highlighted">{{ row.count }}</td>
                </tr>
              </tbody>
            </table>
          </UPageCard>
        </div>
      </div>
    </template>
  </UDashboardPanel>
</template>
