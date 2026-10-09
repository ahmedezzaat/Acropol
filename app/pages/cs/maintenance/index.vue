<script setup lang="ts">
import type { TableColumn } from "@nuxt/ui";
import { getPaginationRowModel } from "@tanstack/vue-table";

definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "cs_customers" },
});

useHead({ htmlAttrs: { class: "carbon" } });

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();
const { hasPermission } = usePermissions();
const { areas, stageById, formatDate, formatDateTime, maintenanceDue, loadAreas, loadPipelines, areaName } = useCs();

// Only products that reached the completed stage (تم التشغيل) — those are the
// ones maintenance starts for. Loaded whole, then narrowed by stage below.
const { data: allProducts, refresh, status } = await useAsyncData<CsProduct[]>("cs-maintenance", async () => {
  const { data, error } = await supabase.from("customer_products").select("*");
  if (error) throw error;
  return (data ?? []) as CsProduct[];
});
const { data: customers } = await useAsyncData<CsCustomer[]>("cs-maintenance-customers", async () => {
  const { data, error } = await supabase.from("customers").select("id, name, company, phone, email, address, area_id");
  if (error) throw error;
  return (data ?? []) as CsCustomer[];
});
const { data: categories } = await useAsyncData<{ id: string; name: string; maintenance_interval_months: number | null }[]>(
  "cs-maintenance-categories",
  async () => {
    const { data } = await supabase.from("product_categories").select("id, name, maintenance_interval_months");
    return data ?? [];
  },
);
await useAsyncData("cs-maintenance-meta", async () => {
  await Promise.all([loadAreas(true), loadPipelines(true)]);
  return true;
});

function customerOf(id: string) {
  return customers.value?.find((c) => c.id === id);
}
function categoryOf(id: string | null) {
  return id ? categories.value?.find((c) => c.id === id) : undefined;
}

interface Row {
  p: CsProduct;
  months: number | null;
  due: string | null; // periodic due date (yyyy-mm-dd)
  at: number | null; // the date that counts: the appointment, else the periodic due date
  appointment: boolean;
  declined: boolean;
}
function rowOf(p: CsProduct): Row {
  const months = categoryOf(p.category_id)?.maintenance_interval_months ?? null;
  const declined = !!p.maintenance_declined_at;
  // A customer who declined maintenance has no due date and no appointment.
  const due = declined ? null : maintenanceDue(p, months);
  const appointment = !declined && !!p.next_maintenance_at;
  const at = appointment ? new Date(p.next_maintenance_at!).getTime() : due ? new Date(`${due}T09:00:00`).getTime() : null;
  return { p, months, due, at, appointment, declined };
}

const rows = computed<Row[]>(() =>
  (allProducts.value ?? [])
    .filter((p) => !!stageById(p.stage_id)?.is_final)
    .map(rowOf)
    .sort((a, b) => (a.at ?? Infinity) - (b.at ?? Infinity)),
);

// ---- Time buckets (local time)
const startOfToday = () => {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d.getTime();
};
type Bucket = "overdue" | "today" | "week" | "later" | "unscheduled" | "declined";
function bucket(r: Row): Bucket {
  if (r.declined) return "declined";
  if (r.at === null) return "unscheduled";
  const today = startOfToday();
  if (r.at < today) return "overdue";
  if (r.at < today + 86_400_000) return "today";
  if (r.at < today + 7 * 86_400_000) return "week";
  return "later";
}
function daysLate(r: Row) {
  return Math.max(1, Math.floor((startOfToday() - r.at!) / 86_400_000) + 1);
}

const tab = ref<"all" | Bucket>("all");
const counts = computed(() => {
  const c = { all: 0, overdue: 0, today: 0, week: 0, later: 0, unscheduled: 0, declined: 0 };
  for (const r of rows.value) {
    c.all++;
    c[bucket(r)]++;
  }
  return c;
});
const tabs = computed(() =>
  (["all", "overdue", "today", "week", "later", "unscheduled", "declined"] as const).map((k) => ({
    label: `${t(`cs.maintenance.${k}`)} · ${counts.value[k]}`,
    value: k,
  })),
);

// ---- Tracking: overdue / scheduled / done over a period
const mode = ref<"list" | "track">("list");
const modeTabs = computed(() => [
  { label: t("cs.maintenance.viewList"), value: "list" },
  { label: t("cs.maintenance.viewTrack"), value: "track" },
]);

type Period = "7d" | "28d" | "month" | "year";
const period = ref<Period>("28d");
const periodTabs = computed(() => [
  { label: t("cs.maintenance.p7d"), value: "7d" },
  { label: t("cs.maintenance.p28d"), value: "28d" },
  { label: t("cs.maintenance.pMonth"), value: "month" },
  { label: t("cs.maintenance.pYear"), value: "year" },
]);
// [from, to) in local time
const range = computed(() => {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const day = 86_400_000;
  if (period.value === "7d") return { from: today.getTime() - 6 * day, to: today.getTime() + day };
  if (period.value === "28d") return { from: today.getTime() - 27 * day, to: today.getTime() + day };
  if (period.value === "month") {
    return { from: new Date(today.getFullYear(), today.getMonth(), 1).getTime(), to: new Date(today.getFullYear(), today.getMonth() + 1, 1).getTime() };
  }
  return { from: new Date(today.getFullYear(), 0, 1).getTime(), to: new Date(today.getFullYear() + 1, 0, 1).getTime() };
});
const dayStr = (ms: number) => {
  const d = new Date(ms);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
};

interface LogRow {
  id: string;
  product_id: string;
  kind: "scheduled" | "rescheduled" | "done" | "declined";
  happened_at: string;
  scheduled_for: string | null;
  done_on: string | null;
  note: string | null;
}
const { data: logs, refresh: refreshLogs } = await useAsyncData<LogRow[]>(
  "cs-maintenance-log",
  async () => {
    const { from, to } = range.value;
    const [booked, done] = await Promise.all([
      supabase
        .from("product_maintenance_log")
        .select("*")
        .in("kind", ["scheduled", "rescheduled", "declined"])
        .gte("happened_at", new Date(from).toISOString())
        .lt("happened_at", new Date(to).toISOString()),
      supabase.from("product_maintenance_log").select("*").eq("kind", "done").gte("done_on", dayStr(from)).lt("done_on", dayStr(to)),
    ]);
    return [...(booked.data ?? []), ...(done.data ?? [])] as LogRow[];
  },
  { watch: [period] },
);

const statKey = ref<"overdue" | "scheduled" | "done" | "declined">("overdue");
// Overdue is a standing state, so it counts everything overdue right now, whatever the period.
const overdueRows = computed(() => rows.value.filter((r) => r.at !== null && r.at < startOfToday()));
const scheduledLogs = computed(() => (logs.value ?? []).filter((l) => l.kind === "scheduled" || l.kind === "rescheduled"));
const declinedLogs = computed(() => (logs.value ?? []).filter((l) => l.kind === "declined"));
const doneLogs = computed(() => (logs.value ?? []).filter((l) => l.kind === "done"));
const stats = computed(() => [
  { key: "overdue" as const, icon: "i-lucide-triangle-alert", value: overdueRows.value.length, tone: overdueRows.value.length ? "text-error" : "text-highlighted" },
  { key: "scheduled" as const, icon: "i-lucide-calendar-clock", value: scheduledLogs.value.length, tone: "text-highlighted" },
  { key: "done" as const, icon: "i-lucide-circle-check", value: doneLogs.value.length, tone: doneLogs.value.length ? "text-success" : "text-highlighted" },
  { key: "declined" as const, icon: "i-lucide-ban", value: declinedLogs.value.length, tone: declinedLogs.value.length ? "text-error" : "text-highlighted" },
]);

interface TrackRow {
  key: string;
  p: CsProduct;
  when: string;
  badge: string | null;
  badgeColor: "error" | "info" | "success";
  sub: string;
  note: string | null;
}
function productOf(id: string) {
  return (allProducts.value ?? []).find((p) => p.id === id);
}
const trackRows = computed<TrackRow[]>(() => {
  if (statKey.value === "overdue") {
    return [...overdueRows.value]
      .sort((a, b) => a.at! - b.at!)
      .map((r) => ({
        key: r.p.id,
        p: r.p,
        when: whenText(r),
        badge: t("cs.maintenance.late", { days: daysLate(r) }),
        badgeColor: "error" as const,
        sub: r.appointment ? t("cs.maintenance.appointment") : t("cs.maintenance.periodicShort"),
        note: r.p.next_maintenance_note,
      }));
  }
  const list = statKey.value === "scheduled" ? scheduledLogs.value : statKey.value === "declined" ? declinedLogs.value : doneLogs.value;
  return list
    .map((l) => ({ l, p: productOf(l.product_id) }))
    .filter((x): x is { l: LogRow; p: CsProduct } => !!x.p)
    .sort((a, b) => (b.l.done_on ?? b.l.happened_at).localeCompare(a.l.done_on ?? a.l.happened_at))
    .map(({ l, p }) =>
      statKey.value === "declined"
        ? {
            key: l.id,
            p,
            when: formatDateTime(l.happened_at),
            badge: t("cs.maintenance.declined"),
            badgeColor: "error" as const,
            sub: "",
            note: l.note,
          }
        : statKey.value === "scheduled"
        ? {
            key: l.id,
            p,
            when: formatDateTime(l.scheduled_for),
            badge: null,
            badgeColor: "info" as const,
            sub: t("cs.maintenance.bookedOn", { date: formatDateTime(l.happened_at) }),
            note: l.note,
          }
        : {
            key: l.id,
            p,
            when: formatDate(l.done_on),
            badge: t("cs.maintenance.doneStat"),
            badgeColor: "success" as const,
            sub: "",
            note: l.note,
          },
    );
});
const trackPagination = ref({ pageIndex: 0, pageSize: 50 });
watch([statKey, period], () => (trackPagination.value.pageIndex = 0));
const trackPaged = computed(() =>
  trackRows.value.slice(trackPagination.value.pageIndex * trackPagination.value.pageSize, (trackPagination.value.pageIndex + 1) * trackPagination.value.pageSize),
);

const search = ref("");
const areaFilter = ref<string | null>(null);
const areaItems = computed(() => [
  { label: t("cs.customers.allAreas"), value: null },
  ...areas.value.map((a) => ({ label: a.name, value: a.id })),
]);

const filtered = computed(() =>
  rows.value.filter((r) => {
    if (tab.value !== "all" && bucket(r) !== tab.value) return false;
    const c = customerOf(r.p.customer_id);
    if (areaFilter.value && c?.area_id !== areaFilter.value) return false;
    if (search.value) {
      const q = search.value.toLowerCase();
      const hay = `${c?.name ?? ""} ${c?.company ?? ""} ${c?.phone ?? ""} ${r.p.name} ${r.p.contract_code ?? ""} ${r.p.next_maintenance_note ?? ""}`.toLowerCase();
      if (!hay.includes(q)) return false;
    }
    return true;
  }),
);

const bucketColor = { overdue: "error", today: "warning", week: "info", later: "neutral", unscheduled: "neutral", declined: "error" } as const;
function badgeLabel(r: Row) {
  return bucket(r) === "overdue" ? t("cs.maintenance.late", { days: daysLate(r) }) : t(`cs.maintenance.${bucket(r)}`);
}
function whenText(r: Row) {
  if (r.appointment) return formatDateTime(r.p.next_maintenance_at);
  return r.due ? formatDate(r.due) : "—";
}

const columns = computed<TableColumn<Row>[]>(() => [
  { id: "when", header: t("cs.maintenance.when") },
  { id: "customer", header: t("cs.maintenance.customer") },
  { id: "product", header: t("cs.maintenance.product") },
  { id: "operation", header: t("cs.maintenance.operationDate") },
  { id: "last", header: t("cs.maintenance.lastDone") },
  { id: "note", header: t("cs.maintenance.note") },
  { id: "actions", header: "" },
]);
const pagination = ref({ pageIndex: 0, pageSize: 50 });
watch([search, areaFilter, tab], () => {
  pagination.value.pageIndex = 0;
});
const pagedCards = computed(() =>
  filtered.value.slice(pagination.value.pageIndex * pagination.value.pageSize, (pagination.value.pageIndex + 1) * pagination.value.pageSize),
);

const doneOpen = ref(false);
const doneProduct = ref<CsProduct | null>(null);
function openDone(p: CsProduct) {
  doneProduct.value = p;
  doneOpen.value = true;
}

const cancelOpen = ref(false);
const cancelProduct = ref<CsProduct | null>(null);
function openCancel(p: CsProduct) {
  cancelProduct.value = p;
  cancelOpen.value = true;
}
async function resume(p: CsProduct) {
  const { error } = await supabase.from("customer_products").update({ maintenance_declined_at: null }).eq("id", p.id);
  if (!error) await supabase.from("product_maintenance_log").insert({ product_id: p.id, kind: "resumed" });
  if (error) {
    toast.add({ title: t("cs.maintenance.saveFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("cs.maintenance.resumed"), color: "success" });
  await onSaved();
}

const modalOpen = ref(false);
const modalProduct = ref<CsProduct | null>(null);
function openModal(p: CsProduct) {
  modalProduct.value = p;
  modalOpen.value = true;
}
async function onSaved() {
  await Promise.all([refresh(), refreshLogs()]);
}
function openRecord(productId: string) {
  navigateTo(`/cs/maintenance/${productId}`);
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar>
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #title>
          <span class="flex items-center gap-2">
            {{ t("cs.maintenance.title") }}
            <UBadge :label="String(counts.all)" color="neutral" variant="subtle" class="cds-tag" />
          </span>
        </template>
      </UDashboardNavbar>

      <div class="w-full space-y-3 border-b border-default px-4 py-3 sm:px-6">
        <UTabs v-model="mode" :items="modeTabs" value-key="value" variant="link" size="sm" :content="false" />
        <div v-if="mode === 'track'" class="-mx-4 overflow-x-auto overflow-y-hidden px-4 [scrollbar-width:none] sm:mx-0 sm:px-0 [&::-webkit-scrollbar]:hidden">
          <UTabs v-model="period" :items="periodTabs" value-key="value" variant="pill" size="sm" :content="false" class="w-max min-w-full sm:w-auto sm:min-w-0" />
        </div>
        <div v-if="mode === 'list'" class="-mx-4 overflow-x-auto overflow-y-hidden px-4 [scrollbar-width:none] sm:mx-0 sm:px-0 [&::-webkit-scrollbar]:hidden">
          <UTabs v-model="tab" :items="tabs" value-key="value" variant="pill" size="sm" :content="false" class="w-max min-w-full sm:w-auto sm:min-w-0" />
        </div>
        <div v-if="mode === 'list'" class="flex flex-wrap items-center gap-2">
          <UInput v-model="search" icon="i-lucide-search" :placeholder="t('cs.maintenance.search')" class="min-w-0 flex-1 basis-56" />
          <USelect v-model="areaFilter" :items="areaItems" value-key="value" icon="i-lucide-map-pin" class="w-44" />
        </div>
      </div>
    </template>

    <template #body>
      <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>

      <!-- Tracking -->
      <div v-else-if="mode === 'track'" class="space-y-4">
        <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <button
            v-for="s in stats"
            :key="s.key"
            type="button"
            class="border bg-default p-3 text-start transition-colors hover:bg-elevated"
            :class="statKey === s.key ? 'border-primary ring-1 ring-primary' : 'border-default'"
            @click="statKey = s.key"
          >
            <div class="flex items-center gap-1.5 text-xs text-muted">
              <UIcon :name="s.icon" class="size-3.5" />{{ t(`cs.maintenance.stat.${s.key}`) }}
            </div>
            <div class="mt-1 text-2xl font-bold" :class="s.tone">{{ s.value }}</div>
          </button>
        </div>

        <p v-if="!trackRows.length" class="py-12 text-center text-sm text-muted">{{ t("cs.maintenance.emptyTrack") }}</p>
        <template v-else>
          <ul class="divide-y divide-default border border-default bg-default">
            <li v-for="r in trackPaged" :key="r.key">
              <button
                type="button"
                class="flex w-full flex-wrap items-center justify-between gap-x-4 gap-y-1 px-4 py-3 text-start transition-colors hover:bg-elevated"
                @click="openRecord(r.p.id)"
              >
                <div class="min-w-0 flex-1 basis-56">
                  <div class="truncate text-sm font-medium text-highlighted">
                    {{ customerOf(r.p.customer_id) ? customerTitle(customerOf(r.p.customer_id)!) : "—" }}
                  </div>
                  <div class="truncate text-xs text-toned">{{ r.p.name }}</div>
                  <p v-if="r.note" class="mt-0.5 line-clamp-1 text-xs text-muted">{{ r.note }}</p>
                </div>
                <div class="flex shrink-0 flex-col items-end gap-1 text-end">
                  <span class="text-sm font-medium text-highlighted">{{ r.when }}</span>
                  <div class="flex items-center gap-1.5">
                    <UBadge v-if="r.badge" :label="r.badge" :color="r.badgeColor" variant="subtle" size="sm" class="cds-tag" />
                    <span v-if="r.sub" class="text-xs text-muted">{{ r.sub }}</span>
                  </div>
                </div>
              </button>
            </li>
          </ul>
          <div class="flex flex-wrap items-center justify-between gap-2 border-t border-default pt-3">
            <span class="text-sm text-muted">{{ t("cs.maintenance.count", { count: trackRows.length }) }}</span>
            <UPagination
              :page="trackPagination.pageIndex + 1"
              :items-per-page="trackPagination.pageSize"
              :total="trackRows.length"
              :sibling-count="1"
              @update:page="(p: number) => (trackPagination.pageIndex = p - 1)"
            />
          </div>
        </template>
      </div>

      <div v-else-if="!filtered.length" class="flex flex-col items-center gap-2 py-16 text-center">
        <UIcon name="i-lucide-wrench" class="size-8 text-muted" />
        <p class="text-sm text-muted">{{ t("cs.maintenance.empty") }}</p>
        <p class="max-w-md text-xs text-muted">{{ t("cs.maintenance.hint") }}</p>
      </div>

      <template v-else>
        <UTable
          v-model:pagination="pagination"
          :data="filtered"
          :columns="columns"
          :pagination-options="{ getPaginationRowModel: getPaginationRowModel() }"
          :ui="{ root: 'hidden md:block [&_tbody_tr]:cursor-pointer' }"
          @select="(_e, row) => openRecord(row.original.p.id)"
        >
          <template #when-cell="{ row }">
            <div v-if="row.original.at !== null">
              <div class="text-sm font-medium" :class="bucket(row.original) === 'overdue' ? 'text-error' : 'text-highlighted'">
                {{ whenText(row.original) }}
              </div>
              <div class="mt-1 flex flex-wrap items-center gap-1">
                <UBadge
                  v-if="bucket(row.original) !== 'later'"
                  :label="badgeLabel(row.original)"
                  :color="bucketColor[bucket(row.original)]"
                  variant="subtle"
                  size="sm"
                  class="cds-tag"
                />
                <span class="text-xs text-muted">
                  {{ row.original.appointment ? t("cs.maintenance.appointment") : t("cs.maintenance.periodicShort") }}
                </span>
              </div>
            </div>
            <UBadge v-else-if="row.original.declined" :label="t('cs.maintenance.declined')" icon="i-lucide-ban" color="error" variant="subtle" size="sm" class="cds-tag" />
            <UBadge v-else :label="t('cs.maintenance.unscheduled')" color="neutral" variant="outline" size="sm" class="cds-tag" />
          </template>
          <template #customer-cell="{ row }">
            <div class="min-w-0">
              <div class="truncate font-medium text-highlighted">
                {{ customerOf(row.original.p.customer_id) ? customerTitle(customerOf(row.original.p.customer_id)!) : "—" }}
              </div>
              <bdi v-if="customerOf(row.original.p.customer_id)?.phone" dir="ltr" class="text-xs text-toned">{{ customerOf(row.original.p.customer_id)?.phone }}</bdi>
            </div>
          </template>
          <template #product-cell="{ row }">
            <div class="min-w-0">
              <div class="truncate text-sm">{{ row.original.p.name }}</div>
              <div class="flex flex-wrap items-center gap-x-2 text-xs text-muted">
                <span v-if="categoryOf(row.original.p.category_id)">{{ categoryOf(row.original.p.category_id)?.name }}</span>
                <span v-if="row.original.months">· {{ t("cs.maintenance.periodic", { months: row.original.months }) }}</span>
              </div>
            </div>
          </template>
          <template #operation-cell="{ row }">
            <span class="text-sm text-muted">{{ formatDate(row.original.p.operation_date) }}</span>
          </template>
          <template #last-cell="{ row }">
            <span class="text-sm text-muted">{{ row.original.p.last_maintenance_on ? formatDate(row.original.p.last_maintenance_on) : "—" }}</span>
          </template>
          <template #note-cell="{ row }">
            <span class="line-clamp-2 max-w-64 text-sm text-muted">{{ row.original.p.next_maintenance_note || "—" }}</span>
          </template>
          <template #actions-cell="{ row }">
            <div v-if="hasPermission('cs_customers', 'edit')" class="flex items-center justify-end gap-1">
              <UButton
                v-if="row.original.appointment"
                icon="i-lucide-check"
                size="xs"
                color="success"
                variant="soft"
                :label="t('cs.maintenance.markDone')"
                @click.stop="openDone(row.original.p)"
              />
              <UButton
                v-if="row.original.declined"
                icon="i-lucide-rotate-ccw"
                size="xs"
                color="neutral"
                variant="soft"
                :label="t('cs.maintenance.resume')"
                @click.stop="resume(row.original.p)"
              />
              <template v-else>
                <UButton
                  :icon="row.original.appointment ? 'i-lucide-calendar-sync' : 'i-lucide-calendar-plus'"
                  size="xs"
                  color="neutral"
                  variant="soft"
                  :aria-label="t(row.original.appointment ? 'cs.maintenance.reschedule' : 'cs.maintenance.schedule')"
                  @click.stop="openModal(row.original.p)"
                />
                <UButton
                  icon="i-lucide-ban"
                  size="xs"
                  color="error"
                  variant="soft"
                  :aria-label="t('cs.maintenance.cancelAction')"
                  @click.stop="openCancel(row.original.p)"
                />
              </template>
            </div>
          </template>
        </UTable>

        <!-- Phones -->
        <div class="space-y-2 md:hidden">
          <div
            v-for="r in pagedCards"
            :key="r.p.id"
            class="cursor-pointer border border-default bg-default p-3 text-sm transition-colors hover:border-primary hover:bg-elevated"
            :class="bucket(r) === 'overdue' && 'border-s-4 border-s-error'"
            @click="openRecord(r.p.id)"
          >
            <div class="flex items-start justify-between gap-2">
              <div class="min-w-0">
                <div class="truncate font-semibold text-highlighted">{{ customerOf(r.p.customer_id) ? customerTitle(customerOf(r.p.customer_id)!) : "—" }}</div>
                <div class="mt-0.5 truncate text-xs text-toned">{{ r.p.name }}</div>
              </div>
              <UBadge
                v-if="bucket(r) !== 'later'"
                :label="bucket(r) === 'unscheduled' ? t('cs.maintenance.unscheduled') : badgeLabel(r)"
                :color="bucketColor[bucket(r)]"
                :variant="bucket(r) === 'unscheduled' ? 'outline' : 'subtle'"
                size="sm"
                class="cds-tag shrink-0"
              />
            </div>
            <div class="mt-2 flex items-center justify-between gap-2 text-xs">
              <span class="flex items-center gap-1" :class="bucket(r) === 'overdue' ? 'font-medium text-error' : 'text-muted'">
                <UIcon name="i-lucide-calendar-clock" class="size-3.5" />{{ whenText(r) }}
                <span v-if="r.at !== null">· {{ r.appointment ? t("cs.maintenance.appointment") : t("cs.maintenance.periodicShort") }}</span>
              </span>
              <div v-if="hasPermission('cs_customers', 'edit')" class="flex items-center gap-1">
                <UButton v-if="r.appointment" icon="i-lucide-check" size="xs" color="success" variant="soft" :label="t('cs.maintenance.markDone')" @click.stop="openDone(r.p)" />
                <UButton v-if="r.declined" icon="i-lucide-rotate-ccw" size="xs" color="neutral" variant="soft" @click.stop="resume(r.p)" />
                <template v-else>
                  <UButton
                    :icon="r.appointment ? 'i-lucide-calendar-sync' : 'i-lucide-calendar-plus'"
                    size="xs"
                    color="neutral"
                    variant="soft"
                    @click.stop="openModal(r.p)"
                  />
                  <UButton icon="i-lucide-ban" size="xs" color="error" variant="soft" @click.stop="openCancel(r.p)" />
                </template>
              </div>
            </div>
            <p v-if="r.p.next_maintenance_note" class="mt-2 line-clamp-2 text-xs text-muted">{{ r.p.next_maintenance_note }}</p>
          </div>
        </div>

        <div class="mt-3 flex flex-wrap items-center justify-between gap-2 border-t border-default pt-3">
          <span class="text-sm text-muted">{{ t("cs.maintenance.count", { count: filtered.length }) }}</span>
          <UPagination
            :page="pagination.pageIndex + 1"
            :items-per-page="pagination.pageSize"
            :total="filtered.length"
            :sibling-count="1"
            @update:page="(p: number) => (pagination.pageIndex = p - 1)"
          />
        </div>
      </template>
    </template>
  </UDashboardPanel>

  <MaintenanceModal v-model:open="modalOpen" :product="modalProduct" @saved="onSaved" />
  <MaintenanceDoneModal v-model:open="doneOpen" :product="doneProduct" @saved="onSaved" />
  <MaintenanceCancelModal v-model:open="cancelOpen" :product="cancelProduct" @saved="onSaved" />
</template>
