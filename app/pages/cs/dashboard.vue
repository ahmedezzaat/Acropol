<script setup lang="ts">
definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "cs_customers" },
});

useHead({ htmlAttrs: { class: "carbon" } });

const supabase = useSupabaseClient();
const { t, locale } = useI18n();
const { hasAnyModulePermission } = usePermissions();
const { areas, pipelines, stagesOf, stageById, stageName, stageLimitDays, dateIndex, dateOf, daysSince, formatDate, formatDateTime, maintenanceDue, loadAreas, loadPipelines, areaName } = useCs();
// Maintenance numbers only for people who can see maintenance.
const canMaintenance = computed(() => hasAnyModulePermission("cs_maintenance"));

// A product is overdue once it has sat in its stage longer than the stage's
// own limit (Settings); stages with no limit fall back to this many days.
const STUCK_DAYS = 30;

const { data: customers, status } = await useAsyncData<CsCustomer[]>("cs-dash-customers", async () =>
  fetchAll<CsCustomer>((from, to) =>
    supabase.from("customers").select("id, name, company, phone, email, address, area_id, created_at").order("id").range(from, to) as never,
  ),
);
const { data: products } = await useAsyncData<CsProduct[]>("cs-dash-products", async () =>
  fetchAll<CsProduct>((from, to) => supabase.from("customer_products").select("*").order("id").range(from, to) as never),
);
const { data: stageDates } = await useAsyncData<CsStageDate[]>("cs-dash-dates", async () =>
  fetchAll<CsStageDate>((from, to) =>
    supabase.from("customer_product_stage_dates").select("product_id, stage_id, reached_on").order("product_id").order("stage_id").range(from, to) as never,
  ),
);
const dates = computed(() => dateIndex(stageDates.value ?? []));
const { data: categories } = await useAsyncData<{ id: string; name: string; maintenance_interval_months: number | null }[]>("cs-dash-categories", async () => {
  const { data } = await supabase.from("product_categories").select("id, name, maintenance_interval_months").order("sort_order");
  return data ?? [];
});
const { data: people } = await useAsyncData<{ id: string; full_name: string | null; email: string }[]>("cs-dash-people", async () => {
  const { data } = await supabase.from("profiles").select("id, full_name, email");
  return data ?? [];
});
// Visits done in the last 28 days (the maintenance log).
const { data: doneRecently } = await useAsyncData<number>("cs-dash-maintenance-done", async () => {
  if (!canMaintenance.value) return 0;
  const from = new Date();
  from.setDate(from.getDate() - 27);
  const day = `${from.getFullYear()}-${String(from.getMonth() + 1).padStart(2, "0")}-${String(from.getDate()).padStart(2, "0")}`;
  const { count } = await supabase
    .from("product_maintenance_log")
    .select("id", { count: "exact", head: true })
    .eq("kind", "done")
    .gte("done_on", day);
  return count ?? 0;
});
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
const stageRamp = ["bg-[#d9dbfa]", "bg-[#a3a7f0]", "bg-[#5258e4]", "bg-[#3b348f]", "bg-[#211951]"];
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

// ---- Money and warranty (this view's products)
const unpaid = computed(() => filteredProducts.value.filter((p) => p.payment_status === "unpaid").length);
const inWarranty = computed(() => filteredProducts.value.filter((p) => p.warranty_status === "in_warranty").length);
const outWarranty = computed(() => filteredProducts.value.filter((p) => p.warranty_status === "out_of_warranty").length);

// ---- By product category and by sales person
const byCategory = computed(() => {
  const counts = new Map<string, number>();
  for (const p of filteredProducts.value) {
    const key = p.category_id ?? "none";
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  return [...counts.entries()]
    .map(([id, count]) => ({ name: id === "none" ? t("cs.profile.noCategory") : (categories.value?.find((c) => c.id === id)?.name ?? "—"), count }))
    .sort((a, b) => b.count - a.count)
    .slice(0, 8);
});
const categoryMax = computed(() => Math.max(1, ...byCategory.value.map((r) => r.count)));

const bySalesPerson = computed(() => {
  const counts = new Map<string, number>();
  for (const p of filteredProducts.value) {
    const key = p.sales_person_id ?? "none";
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  return [...counts.entries()]
    .map(([id, count]) => {
      const u = people.value?.find((x) => x.id === id);
      return { name: id === "none" ? t("cs.dashboard.noSalesPerson") : u ? u.full_name || u.email : "—", count };
    })
    .sort((a, b) => b.count - a.count)
    .slice(0, 8);
});
const salesMax = computed(() => Math.max(1, ...bySalesPerson.value.map((r) => r.count)));

// ---- Maintenance: products at the completed stage (any funnel), in the chosen
// area. The period filter above does not apply: maintenance is about now.
const maintenanceRows = computed(() => {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const startOfToday = today.getTime();
  return (products.value ?? [])
    .filter((p) => !!stageById(p.stage_id)?.is_final)
    .filter((p) => !areaFilter.value || customerById.value.get(p.customer_id)?.area_id === areaFilter.value)
    .map((p) => {
      const declined = !!p.maintenance_declined_at;
      const months = categories.value?.find((c) => c.id === p.category_id)?.maintenance_interval_months ?? null;
      const due = declined ? null : maintenanceDue(p, months);
      const at = declined ? null : p.next_maintenance_at ? new Date(p.next_maintenance_at).getTime() : due ? new Date(`${due}T09:00:00`).getTime() : null;
      return { p, declined, at, appointment: !declined && !!p.next_maintenance_at, startOfToday };
    });
});
const maintenanceStats = computed(() => {
  const rows = maintenanceRows.value;
  const today = rows[0]?.startOfToday ?? new Date().setHours(0, 0, 0, 0);
  const week = today + 7 * 86_400_000;
  return {
    overdue: rows.filter((r) => r.at !== null && r.at < today).length,
    week: rows.filter((r) => r.at !== null && r.at >= today && r.at < week).length,
    scheduled: rows.filter((r) => r.appointment && r.at !== null && r.at >= today).length,
    cancelled: rows.filter((r) => r.declined).length,
    unscheduled: rows.filter((r) => !r.declined && r.at === null).length,
  };
});
const nextAppointments = computed(() => {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  return maintenanceRows.value
    .filter((r) => r.appointment && r.at !== null && r.at >= today.getTime())
    .sort((a, b) => a.at! - b.at!)
    .slice(0, 5);
});

function openCustomer(id: string) {
  navigateTo(`/cs/customers/${id}`);
}
</script>

<template>
  <UDashboardPanel :ui="{ body: 'kords-canvas' }">
    <template #header>
      <KPageHeader :title="t('cs.dashboard.title')" />

      <div class="kords-filterbar w-full space-y-3 border-b border-default px-4 py-3 sm:px-6">
        <div v-if="pipelines.length > 1" class="-mx-4 overflow-x-auto overflow-y-hidden px-4 [scrollbar-width:none] sm:mx-0 sm:px-0 [&::-webkit-scrollbar]:hidden">
          <UTabs v-model="pipelineId" :items="pipelineTabs" value-key="value" variant="link" :content="false" class="kords-pilltabs w-max min-w-full" />
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <USelect v-model="areaFilter" :items="areaItems" value-key="value" icon="i-lucide-map-pin" class="w-48" />
          <UTabs v-model="period" :items="periodTabs" value-key="value" variant="link" size="sm" :content="false" class="kords-pilltabs" />
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
          <KStatsCard to="/cs/customers" icon="i-lucide-users" :title="t('cs.dashboard.customers')" :value="filteredCustomers.length" />
          <KStatsCard to="/cs/installations" icon="i-lucide-package" :title="t('cs.dashboard.installations')" :value="total" />
          <KStatsCard to="/cs/installations" icon="i-lucide-loader" :title="t('cs.dashboard.inProgress')" :value="inProgress" />
          <KStatsCard to="/cs/installations" icon="i-lucide-circle-check" tone="success" :title="t('cs.dashboard.completed', { rate: completionRate })" :value="completed" />
          <KStatsCard icon="i-lucide-triangle-alert" :tone="stuck.length ? 'error' : 'default'" :title="t('cs.dashboard.stuck')" :value="stuck.length" />
        </div>

        <!-- Warranty and payment -->
        <div class="grid grid-cols-3 gap-4">
          <KStatsCard icon="i-lucide-banknote" :tone="unpaid ? 'error' : 'default'" :title="t('cs.dashboard.unpaid')" :value="unpaid" />
          <KStatsCard icon="i-lucide-shield-check" tone="success" :title="t('cs.dashboard.inWarranty')" :value="inWarranty" />
          <KStatsCard icon="i-lucide-shield" :title="t('cs.dashboard.outWarranty')" :value="outWarranty" />
        </div>

        <!-- Maintenance -->
        <UPageCard class="kords-card" v-if="canMaintenance" :title="t('cs.dashboard.maintenance')" :description="t('cs.dashboard.maintenanceHint')">
          <div class="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-6">
            <div class="rounded-[10px] bg-[#f6f9fc] p-3">
              <div class="text-2xl font-bold" :class="maintenanceStats.overdue ? 'text-error' : 'text-highlighted'">{{ maintenanceStats.overdue }}</div>
              <div class="text-xs text-muted">{{ t("cs.maintenance.stat.overdue") }}</div>
            </div>
            <div class="rounded-[10px] bg-[#f6f9fc] p-3">
              <div class="text-2xl font-bold" :class="maintenanceStats.week ? 'text-warning' : 'text-highlighted'">{{ maintenanceStats.week }}</div>
              <div class="text-xs text-muted">{{ t("cs.dashboard.dueThisWeek") }}</div>
            </div>
            <div class="rounded-[10px] bg-[#f6f9fc] p-3">
              <div class="text-2xl font-bold text-highlighted">{{ maintenanceStats.scheduled }}</div>
              <div class="text-xs text-muted">{{ t("cs.dashboard.upcomingAppointments") }}</div>
            </div>
            <div class="rounded-[10px] bg-[#f6f9fc] p-3">
              <div class="text-2xl font-bold text-success">{{ doneRecently ?? 0 }}</div>
              <div class="text-xs text-muted">{{ t("cs.dashboard.doneLast28") }}</div>
            </div>
            <div class="rounded-[10px] bg-[#f6f9fc] p-3">
              <div class="text-2xl font-bold text-highlighted">{{ maintenanceStats.unscheduled }}</div>
              <div class="text-xs text-muted">{{ t("cs.maintenance.unscheduled") }}</div>
            </div>
            <div class="rounded-[10px] bg-[#f6f9fc] p-3">
              <div class="text-2xl font-bold text-highlighted">{{ maintenanceStats.cancelled }}</div>
              <div class="text-xs text-muted">{{ t("cs.maintenance.stat.declined") }}</div>
            </div>
          </div>

          <div class="mt-3">
            <UButton to="/cs/maintenance" icon="i-lucide-wrench" size="sm" color="neutral" variant="soft" :label="t('cs.dashboard.openMaintenance')" />
          </div>

          <div v-if="nextAppointments.length" class="mt-4 border-t border-default pt-3">
            <div class="mb-1 text-xs font-semibold uppercase tracking-wide text-muted">{{ t("cs.dashboard.nextUp") }}</div>
            <ul class="divide-y divide-default">
              <li v-for="r in nextAppointments" :key="r.p.id">
                <NuxtLink :to="`/cs/maintenance/${r.p.id}`" class="flex flex-wrap items-center justify-between gap-2 py-2 text-sm transition-colors hover:bg-elevated">
                  <span class="min-w-0">
                    <span class="block truncate font-medium text-highlighted">{{ customerById.get(r.p.customer_id) ? customerTitle(customerById.get(r.p.customer_id)!) : "—" }}</span>
                    <span class="block truncate text-xs text-muted">{{ r.p.name }}</span>
                  </span>
                  <span class="shrink-0 text-xs text-muted">{{ formatDateTime(r.p.next_maintenance_at) }}</span>
                </NuxtLink>
              </li>
            </ul>
          </div>
        </UPageCard>

        <!-- Funnel -->
        <UPageCard class="kords-card" :title="t('cs.dashboard.funnel')">
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
              <div class="h-3 w-full overflow-hidden rounded-full bg-[#eef1f6]">
                <div class="h-full rounded-full" :class="rampClass(row.rank, byStage.length)" :style="{ width: `${(row.count / stageMax) * 100}%` }" />
              </div>
            </div>
          </div>
        </UPageCard>

        <!-- Contracts per month -->
        <UPageCard class="kords-card" :title="t('cs.dashboard.contractsByMonth')">
          <div v-if="!total" class="text-sm text-muted">{{ t("cs.dashboard.noData") }}</div>
          <div v-else class="flex h-44 items-stretch gap-1 sm:gap-2" dir="ltr">
            <div v-for="m in byMonth" :key="m.key" class="flex min-w-0 flex-1 flex-col items-center">
              <!-- the bars live in their own area so the labels never overlap them -->
              <div class="flex min-h-0 w-full flex-1 flex-col items-center justify-end gap-1">
                <span class="text-[10px] font-medium text-highlighted sm:text-xs">{{ m.count || "" }}</span>
                <div
                  class="w-full max-w-8 rounded-t"
                  :class="m.count ? 'bg-[#5258e4]' : 'bg-elevated'"
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

        <div class="grid grid-cols-1 gap-6 lg:grid-cols-3">
          <!-- By area -->
          <UPageCard class="kords-card" :title="t('cs.dashboard.byArea')">
            <div v-if="!byArea.length" class="text-sm text-muted">{{ t("cs.dashboard.noData") }}</div>
            <div v-else class="space-y-2.5">
              <div v-for="r in byArea" :key="r.name" class="space-y-1">
                <div class="flex items-baseline justify-between gap-2 text-xs">
                  <span class="truncate text-highlighted">{{ r.name }}</span>
                  <span class="font-medium text-highlighted">{{ r.count }}</span>
                </div>
                <div class="h-2.5 w-full overflow-hidden rounded-full bg-[#eef1f6]">
                  <div class="h-full rounded-full bg-[#5258e4]" :style="{ width: `${(r.count / areaMax) * 100}%` }" />
                </div>
              </div>
            </div>
          </UPageCard>

          <!-- By product category -->
          <UPageCard class="kords-card" :title="t('cs.dashboard.byCategory')">
            <div v-if="!byCategory.length" class="text-sm text-muted">{{ t("cs.dashboard.noData") }}</div>
            <div v-else class="space-y-2.5">
              <div v-for="r in byCategory" :key="r.name" class="space-y-1">
                <div class="flex items-baseline justify-between gap-2 text-xs">
                  <span class="truncate text-highlighted">{{ r.name }}</span>
                  <span class="font-medium text-highlighted">{{ r.count }}</span>
                </div>
                <div class="h-2.5 w-full overflow-hidden rounded-full bg-[#eef1f6]">
                  <div class="h-full rounded-full bg-[#5258e4]" :style="{ width: `${(r.count / categoryMax) * 100}%` }" />
                </div>
              </div>
            </div>
          </UPageCard>

          <!-- By sales person -->
          <UPageCard class="kords-card" :title="t('cs.dashboard.bySalesPerson')">
            <div v-if="!bySalesPerson.length" class="text-sm text-muted">{{ t("cs.dashboard.noData") }}</div>
            <div v-else class="space-y-2.5">
              <div v-for="r in bySalesPerson" :key="r.name" class="space-y-1">
                <div class="flex items-baseline justify-between gap-2 text-xs">
                  <span class="truncate text-highlighted" dir="auto">{{ r.name }}</span>
                  <span class="font-medium text-highlighted">{{ r.count }}</span>
                </div>
                <div class="h-2.5 w-full overflow-hidden rounded-full bg-[#eef1f6]">
                  <div class="h-full rounded-full bg-[#5258e4]" :style="{ width: `${(r.count / salesMax) * 100}%` }" />
                </div>
              </div>
            </div>
          </UPageCard>
        </div>

        <!-- Needs attention -->
        <UPageCard class="kords-card" :title="t('cs.dashboard.needsAttention')" :description="t('cs.dashboard.limitHint', { days: STUCK_DAYS })">
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
                  <KBadge :label="stageName(x.p.stage_id)" tone="neutral" />
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
