<script setup lang="ts">
definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "cs_customers" },
});

useHead({ htmlAttrs: { class: "carbon" } });

const supabase = useSupabaseClient();
const { t, locale } = useI18n();
const { areas, pipelines, stagesOf, stageById, stageName, stageLimitDays, dateIndex, dateOf, daysSince, formatDate, loadAreas, loadPipelines, areaName } = useCs();

// A product is overdue once it has sat in its stage longer than the stage's
// own limit (Settings); stages with no limit fall back to this many days.
const STUCK_DAYS = 30;

const { data: customers, status } = await useAsyncData<CsCustomer[]>("cs-dash-customers", async () => {
  const { data, error } = await supabase.from("customers").select("id, name, company, phone, email, address, area_id, created_at");
  if (error) throw error;
  return (data ?? []) as CsCustomer[];
});
const { data: products } = await useAsyncData<CsProduct[]>("cs-dash-products", async () => {
  const { data, error } = await supabase.from("customer_products").select("*");
  if (error) throw error;
  return (data ?? []) as CsProduct[];
});
const { data: stageDates } = await useAsyncData<CsStageDate[]>("cs-dash-dates", async () => {
  const { data, error } = await supabase.from("customer_product_stage_dates").select("product_id, stage_id, reached_on");
  if (error) throw error;
  return (data ?? []) as CsStageDate[];
});
const dates = computed(() => dateIndex(stageDates.value ?? []));
await useAsyncData("cs-dash-areas", async () => {
  await Promise.all([loadAreas(true), loadPipelines(true)]);
  return true;
});

// ---- Filters: area, and a period applied to the contract date
type Period = "all" | "year" | "90d";
const period = ref<Period>("all");
const pipelineId = ref<string | undefined>(pipelines.value[0]?.id);
const pipelineTabs = computed(() => pipelines.value.map((p) => ({ label: p.name, value: p.id })));
const areaFilter = ref<string | null>(null);

const areaItems = computed(() => [
  { label: t("cs.customers.allAreas"), value: null },
  ...areas.value.map((a) => ({ label: a.name, value: a.id })),
]);
const periodTabs = computed(() =>
  (["all", "year", "90d"] as const).map((p) => ({ value: p, label: t(`cs.dashboard.period.${p}`) })),
);


const customerById = computed(() => new Map((customers.value ?? []).map((c) => [c.id, c])));

const filteredProducts = computed(() =>
  (products.value ?? []).filter((p) => {
    if (p.pipeline_id !== pipelineId.value) return false;
    const c = customerById.value.get(p.customer_id);
    if (areaFilter.value && c?.area_id !== areaFilter.value) return false;
    if (period.value !== "all") {
      const age = daysSince(p.contract_date);
      if (age === null) return false;
      if (period.value === "90d" && age > 90) return false;
      if (period.value === "year" && new Date(`${p.contract_date}T12:00:00`).getFullYear() !== new Date().getFullYear()) return false;
    }
    return true;
  }),
);
const filteredCustomers = computed(() =>
  (customers.value ?? []).filter((c) => {
    if (areaFilter.value && c.area_id !== areaFilter.value) return false;
    // With a period selected, only customers who have a product in it.
    if (period.value !== "all") return filteredProducts.value.some((p) => p.customer_id === c.id);
    return true;
  }),
);

// ---- KPIs
const isFinal = (p: CsProduct) => !!stageById(p.stage_id)?.is_final;
const total = computed(() => filteredProducts.value.length);
const completed = computed(() => filteredProducts.value.filter(isFinal).length);
const inProgress = computed(() => total.value - completed.value);
const completionRate = computed(() => (total.value ? Math.round((completed.value / total.value) * 100) : 0));

// Days a product has been in its current stage (falls back to the contract date).
function daysInStage(p: CsProduct) {
  return daysSince(dateOf(dates.value, p.id, p.stage_id) ?? p.contract_date);
}
function limitFor(p: CsProduct) {
  return stageLimitDays(stageById(p.stage_id)) ?? STUCK_DAYS;
}
const stuck = computed(() =>
  filteredProducts.value
    .filter((p) => !isFinal(p))
    .map((p) => ({ p, days: daysInStage(p), limit: limitFor(p) }))
    .filter((x): x is { p: CsProduct; days: number; limit: number } => x.days !== null && x.days > x.limit)
    .sort((a, b) => b.days - b.limit - (a.days - a.limit)),
);

// ---- Funnel by stage (the chosen pipeline's stages, in order)
const byStage = computed(() => {
  const list = stagesOf(pipelineId.value);
  return list.map((s, rank) => ({
    stage: s,
    rank,
    count: filteredProducts.value.filter((p) => p.stage_id === s.id).length,
  }));
});
const stageMax = computed(() => Math.max(1, ...byStage.value.map((r) => r.count)));

// One hue, lightness stepped by funnel position: darker means further along.
const stageRamp = ["bg-kords-primary-200", "bg-kords-primary-400", "bg-kords-primary-500", "bg-kords-primary-700", "bg-kords-primary-900"];
function rampClass(rank: number, count: number) {
  return stageRamp[count <= 1 ? 4 : Math.round((rank / (count - 1)) * (stageRamp.length - 1))];
}

// ---- Contracts per month: the 12 months ending at the latest contract (so
// history imported from older files still shows up, and it follows today once
// new contracts keep arriving).
const byMonth = computed(() => {
  const latest = filteredProducts.value.map((p) => p.contract_date).filter((d): d is string => !!d).sort().at(-1);
  const end = latest ? new Date(`${latest}T12:00:00`) : new Date();
  const months = Array.from({ length: 12 }, (_, i) => {
    const d = new Date(end.getFullYear(), end.getMonth() - (11 - i), 1);
    return { key: `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`, date: d, count: 0 };
  });
  for (const p of filteredProducts.value) {
    const m = months.find((x) => p.contract_date?.startsWith(x.key));
    if (m) m.count++;
  }
  return months.map((m) => ({
    ...m,
    label: m.date.toLocaleDateString(locale.value === "ar" ? "ar" : "en", { month: "short" }),
    year: String(m.date.getFullYear()).slice(2),
  }));
});
const monthMax = computed(() => Math.max(1, ...byMonth.value.map((m) => m.count)));

// ---- By area
const byArea = computed(() => {
  const counts = new Map<string, number>();
  for (const p of filteredProducts.value) {
    const key = customerById.value.get(p.customer_id)?.area_id ?? "none";
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  return [...counts.entries()]
    .map(([id, count]) => ({ name: id === "none" ? t("cs.customers.noArea") : areaName(id), count }))
    .sort((a, b) => b.count - a.count)
    .slice(0, 10);
});
const areaMax = computed(() => Math.max(1, ...byArea.value.map((r) => r.count)));

function openCustomer(id: string) {
  navigateTo(`/cs/customers/${id}`);
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="t('cs.dashboard.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
      </UDashboardNavbar>

      <div class="w-full space-y-3 border-b border-default px-4 py-3 sm:px-6">
        <div v-if="pipelines.length > 1" class="-mx-4 overflow-x-auto overflow-y-hidden px-4 [scrollbar-width:none] sm:mx-0 sm:px-0 [&::-webkit-scrollbar]:hidden">
          <UTabs v-model="pipelineId" :items="pipelineTabs" value-key="value" variant="link" :content="false" class="w-max min-w-full" />
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <USelect v-model="areaFilter" :items="areaItems" value-key="value" icon="i-lucide-map-pin" class="w-48" />
          <UTabs v-model="period" :items="periodTabs" value-key="value" variant="pill" size="sm" :content="false" />
        </div>
      </div>
    </template>

    <template #body>
      <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>

      <div v-else class="space-y-6">
        <!-- KPIs -->
        <div class="grid grid-cols-2 gap-4 lg:grid-cols-5">
          <UPageCard to="/cs/customers">
            <div class="text-2xl font-bold text-highlighted">{{ filteredCustomers.length }}</div>
            <div class="text-sm text-muted">{{ t("cs.dashboard.customers") }}</div>
          </UPageCard>
          <UPageCard to="/cs/installations">
            <div class="text-2xl font-bold text-highlighted">{{ total }}</div>
            <div class="text-sm text-muted">{{ t("cs.dashboard.installations") }}</div>
          </UPageCard>
          <UPageCard to="/cs/installations">
            <div class="text-2xl font-bold text-highlighted">{{ inProgress }}</div>
            <div class="text-sm text-muted">{{ t("cs.dashboard.inProgress") }}</div>
          </UPageCard>
          <UPageCard to="/cs/installations">
            <div class="text-2xl font-bold text-success">{{ completed }}</div>
            <div class="text-sm text-muted">{{ t("cs.dashboard.completed", { rate: completionRate }) }}</div>
          </UPageCard>
          <UPageCard>
            <div class="text-2xl font-bold" :class="stuck.length ? 'text-error' : 'text-highlighted'">{{ stuck.length }}</div>
            <div class="text-sm text-muted">{{ t("cs.dashboard.stuck") }}</div>
          </UPageCard>
        </div>

        <!-- Funnel -->
        <UPageCard :title="t('cs.dashboard.funnel')">
          <div v-if="!total" class="text-sm text-muted">{{ t("cs.dashboard.noData") }}</div>
          <div v-else class="space-y-3">
            <div v-for="row in byStage" :key="row.stage.id" class="space-y-1">
              <div class="flex items-baseline justify-between gap-2 text-xs">
                <span class="text-highlighted">{{ row.stage.name }}</span>
                <span class="text-muted">
                  <span class="font-medium text-highlighted">{{ row.count }}</span>
                  · {{ Math.round((row.count / total) * 100) }}%
                </span>
              </div>
              <div class="h-3 w-full overflow-hidden rounded-full bg-elevated">
                <div class="h-full rounded-full" :class="rampClass(row.rank, byStage.length)" :style="{ width: `${(row.count / stageMax) * 100}%` }" />
              </div>
            </div>
          </div>
        </UPageCard>

        <!-- Contracts per month -->
        <UPageCard :title="t('cs.dashboard.contractsByMonth')">
          <div v-if="!total" class="text-sm text-muted">{{ t("cs.dashboard.noData") }}</div>
          <div v-else class="flex h-44 items-stretch gap-1 sm:gap-2" dir="ltr">
            <div v-for="m in byMonth" :key="m.key" class="flex min-w-0 flex-1 flex-col items-center">
              <!-- the bars live in their own area so the labels never overlap them -->
              <div class="flex min-h-0 w-full flex-1 flex-col items-center justify-end gap-1">
                <span class="text-[10px] font-medium text-highlighted sm:text-xs">{{ m.count || "" }}</span>
                <div
                  class="w-full max-w-8 rounded-t"
                  :class="m.count ? 'bg-kords-primary-500' : 'bg-elevated'"
                  :style="{ height: `${m.count ? Math.max(6, (m.count / monthMax) * 82) : 3}%` }"
                  :title="`${m.label} ${m.year}: ${m.count}`"
                />
              </div>
              <span class="mt-1 shrink-0 text-center text-[9px] leading-tight text-muted sm:text-[10px]">
                <span class="sm:hidden">{{ m.label.slice(0, 3) }}</span><span class="hidden sm:inline">{{ m.label }}</span><br />{{ m.year }}
              </span>
            </div>
          </div>
        </UPageCard>

        <div>
          <!-- By area -->
          <UPageCard :title="t('cs.dashboard.byArea')">
            <div v-if="!byArea.length" class="text-sm text-muted">{{ t("cs.dashboard.noData") }}</div>
            <div v-else class="space-y-2.5">
              <div v-for="r in byArea" :key="r.name" class="space-y-1">
                <div class="flex items-baseline justify-between gap-2 text-xs">
                  <span class="truncate text-highlighted">{{ r.name }}</span>
                  <span class="font-medium text-highlighted">{{ r.count }}</span>
                </div>
                <div class="h-2.5 w-full overflow-hidden rounded-full bg-elevated">
                  <div class="h-full rounded-full bg-kords-primary-500" :style="{ width: `${(r.count / areaMax) * 100}%` }" />
                </div>
              </div>
            </div>
          </UPageCard>
        </div>

        <!-- Needs attention -->
        <UPageCard :title="t('cs.dashboard.needsAttention')" :description="t('cs.dashboard.limitHint', { days: STUCK_DAYS })">
          <p v-if="!stuck.length" class="text-sm text-muted">{{ t("cs.dashboard.nothingStuck") }}</p>
          <ul v-else class="divide-y divide-default">
            <li v-for="x in stuck.slice(0, 10)" :key="x.p.id">
              <button
                type="button"
                class="flex w-full flex-wrap items-center justify-between gap-2 py-2.5 text-start transition-colors hover:bg-elevated"
                @click="openCustomer(x.p.customer_id)"
              >
                <span class="min-w-0">
                  <span class="block truncate font-medium text-highlighted">{{ customerById.get(x.p.customer_id) ? customerTitle(customerById.get(x.p.customer_id)!) : "—" }}</span>
                  <span class="block truncate text-xs text-muted">{{ x.p.name }}</span>
                </span>
                <span class="flex shrink-0 items-center gap-2 text-xs">
                  <UBadge :label="stageName(x.p.stage_id)" color="neutral" variant="subtle" size="sm" class="cds-tag" />
                  <span class="font-semibold text-error">{{ t("cs.dashboard.daysOfLimit", { days: x.days, limit: Math.round(x.limit) }) }}</span>
                  <span class="hidden text-muted sm:inline">{{ formatDate(dateOf(dates, x.p.id, x.p.stage_id) ?? x.p.contract_date) }}</span>
                </span>
              </button>
            </li>
          </ul>
        </UPageCard>
      </div>
    </template>
  </UDashboardPanel>
</template>
