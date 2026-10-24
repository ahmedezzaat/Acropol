<script setup lang="ts">
import type { TableColumn } from "@nuxt/ui";
import { getPaginationRowModel } from "@tanstack/vue-table";

// Confirmed visits: the maintenance appointments the customer has confirmed by
// phone, one row per customer visit (the products of one customer on one day
// are serviced together). From here a visit is assigned to a technician (or
// reassigned), filtered by technician, and marked done.
useHead({ htmlAttrs: { class: "carbon" } });

const supabase = useSupabaseClient();
const { t } = useI18n();
const { hasPermission, hasAnyModulePermission } = usePermissions();
const can = {
  get assign() {
    return hasPermission("cs_maintenance", "schedule");
  },
  get complete() {
    return hasPermission("cs_maintenance", "complete");
  },
};
const { areas, formatDateTime, loadAreas, loadPipelines, areaName } = useCs();

// Someone with only "see my confirmed visits" gets just the visits assigned to
// them (the database enforces it too); "see all" gets everyone's.
const me = useSupabaseUser();
const seesAll = computed(() => hasPermission("cs_maintenance", "view_confirmed_all"));

// ---- Data
const __ad1 = useAsyncData<CsProduct[]>("cs-confirmed-visits", async () =>
  fetchAll<CsProduct>((from, to) =>
    supabase
      .from("customer_products")
      .select("*")
      .not("maintenance_confirmed_at", "is", null)
      .not("next_maintenance_at", "is", null)
      .match(seesAll.value ? {} : { maintenance_technician_id: me.value?.sub as string })
      .order("next_maintenance_at")
      .order("id")
      .range(from, to) as never,
  ),
);
const { data: products, refresh, status } = __ad1;
const __ad2 = useAsyncData<CsCustomer[]>("cs-confirmed-visits-customers", async () =>
  fetchAll<CsCustomer>((from, to) =>
    supabase.from("customers").select("id, name, company, phone, address, area_id").order("id").range(from, to) as never,
  ),
);
const { data: customers } = __ad2;
interface Technician {
  id: string;
  full_name: string | null;
  email: string;
  is_active: boolean;
}
const __ad3 = useAsyncData<Technician[]>("cs-confirmed-visits-technicians", async () => {
  const { data } = await supabase.from("profiles").select("id, full_name, email, is_active").eq("is_technician", true).order("full_name");
  return (data ?? []) as Technician[];
});
const { data: technicians } = __ad3;
const __ad4 = useAsyncData("cs-confirmed-visits-meta", async () => {
  await Promise.all([loadAreas(true), loadPipelines(true)]);
  return true;
});

// Load everything at once instead of one request after another.
await Promise.all([__ad1, __ad2, __ad3, __ad4]);

const customerById = computed(() => new Map((customers.value ?? []).map((c) => [c.id, c])));
const techName = (id: string | null | undefined) => {
  const u = id ? technicians.value?.find((x) => x.id === id) : null;
  return u ? u.full_name || u.email : null;
};

// ---- One row per customer visit: same customer, same day
interface Visit {
  key: string;
  customerId: string;
  at: number;
  products: CsProduct[];
  technicianIds: (string | null)[];
}
const dayKey = (iso: string) => {
  const d = new Date(iso);
  return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
};
const visits = computed<Visit[]>(() => {
  const map = new Map<string, Visit>();
  for (const p of products.value ?? []) {
    const key = `${p.customer_id}|${dayKey(p.next_maintenance_at!)}`;
    const at = new Date(p.next_maintenance_at!).getTime();
    const v = map.get(key) ?? { key, customerId: p.customer_id, at, products: [], technicianIds: [] };
    v.at = Math.min(v.at, at);
    v.products.push(p);
    v.technicianIds.push(p.maintenance_technician_id ?? null);
    map.set(key, v);
  }
  return [...map.values()].sort((a, b) => a.at - b.at);
});
// The technician of a visit when all its products share one; null when none, "mixed" when they differ.
const technicianOf = (v: Visit): string | null | "mixed" => {
  const ids = [...new Set(v.technicianIds)];
  return ids.length === 1 ? ids[0]! : "mixed";
};

// ---- Filters
const startOfToday = () => {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d.getTime();
};
type Period = "all" | "overdue" | "today" | "tomorrow" | "week" | "later";
const period = ref<Period>("all");
const inPeriod = (v: Visit, p: Period) => {
  const today = startOfToday();
  if (p === "all") return true;
  if (p === "overdue") return v.at < today;
  if (p === "today") return v.at >= today && v.at < today + 86_400_000;
  if (p === "tomorrow") return v.at >= today + 86_400_000 && v.at < today + 2 * 86_400_000;
  if (p === "week") return v.at >= today && v.at < today + 7 * 86_400_000;
  return v.at >= today + 7 * 86_400_000;
};
const periodTabs = computed(() =>
  (["all", "overdue", "today", "tomorrow", "week", "later"] as const).map((k) => ({
    value: k,
    label: `${t(k === "all" ? "cs.confirmedVisits.all" : `cs.maintenance.${k}`)} · ${visits.value.filter((v) => inPeriod(v, k)).length}`,
  })),
);

// technician chips: everyone, unassigned, or one technician
const techFilter = ref<"all" | "none" | string>("all");
const techChips = computed(() => {
  const count = (pred: (v: Visit) => boolean) => visits.value.filter((v) => inPeriod(v, period.value) && pred(v)).length;
  return [
    { key: "all", label: t("cs.confirmedVisits.allTechnicians"), count: count(() => true) },
    { key: "none", label: t("cs.maintenance.unassigned"), count: count((v) => v.technicianIds.some((id) => !id)) },
    ...(technicians.value ?? [])
      .filter((u) => u.is_active || visits.value.some((v) => v.technicianIds.includes(u.id)))
      .map((u) => ({ key: u.id, label: u.full_name || u.email, count: count((v) => v.technicianIds.includes(u.id)) })),
  ];
});

const search = ref("");
const areaFilter = ref<string | null>(null);
const areaItems = computed(() => [{ label: t("cs.customers.allAreas"), value: null }, ...areas.value.map((a) => ({ label: a.name, value: a.id }))]);

// Everything except the period tab: used by the calendar, which has its own range.
const passesFilters = (v: Visit) => {
  if (techFilter.value === "none" && !v.technicianIds.some((id) => !id)) return false;
  if (techFilter.value !== "all" && techFilter.value !== "none" && !v.technicianIds.includes(techFilter.value)) return false;
  const c = customerById.value.get(v.customerId);
  if (areaFilter.value && c?.area_id !== areaFilter.value) return false;
  if (search.value) {
    const q = search.value.toLowerCase();
    const hay = `${c?.name ?? ""} ${c?.company ?? ""} ${c?.phone ?? ""} ${c?.address ?? ""} ${v.products.map((p) => `${p.name} ${p.contract_code ?? ""}`).join(" ")}`.toLowerCase();
    if (!hay.includes(q)) return false;
  }
  return true;
};
const filtered = computed(() => visits.value.filter((v) => inPeriod(v, period.value) && passesFilters(v)));

// ---- Calendar view: this week, next week or a month, as a grid
const viewMode = ref<"list" | "calendar">("list");
type CalRange = "thisWeek" | "nextWeek" | "month";
const calRange = ref<CalRange>("thisWeek");
const calShift = ref(0); // weeks (or months) moved with the arrows
function weekStart(offsetWeeks: number) {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  // weeks start on Saturday
  d.setDate(d.getDate() - ((d.getDay() + 1) % 7) + offsetWeeks * 7);
  return d;
}
const calStart = computed(() => {
  if (calRange.value === "month") {
    const n = new Date();
    return new Date(n.getFullYear(), n.getMonth() + calShift.value, 1);
  }
  return weekStart((calRange.value === "nextWeek" ? 1 : 0) + calShift.value);
});
const calMode = computed(() => (calRange.value === "month" ? "month" : "week"));
const calTabs = computed(() => [
  { value: "thisWeek", label: t("cs.confirmedVisits.thisWeek") },
  { value: "nextWeek", label: t("cs.confirmedVisits.nextWeek") },
  { value: "month", label: t("cs.confirmedVisits.month") },
]);
watch(calRange, () => (calShift.value = 0));
const calendarVisits = computed(() => visits.value.filter(passesFilters));
const customerTitleOf = (id: string) => {
  const c = customerById.value.get(id);
  return c ? customerTitle(c) : "—";
};
// A visit clicked on the calendar opens its assignment (or its customer).
function onCalendarSelect(v: { key: string }) {
  const visit = visits.value.find((x) => x.key === v.key);
  if (!visit) return;
  if (can.assign) openAssign([visit]);
  else openCustomer(visit.customerId);
}
function setView(mode: "list" | "calendar") {
  viewMode.value = mode;
}
function shiftCal(delta: number) {
  calShift.value += delta;
}
function backToToday() {
  calShift.value = 0;
}

// ---- Selection (bulk assign)
const UCheckbox = resolveComponent("UCheckbox");
const rowSelection = ref<Record<string, boolean>>({});
const selectedVisits = computed(() => filtered.value.filter((v) => rowSelection.value[v.key]));
function clearSelection() {
  rowSelection.value = {};
}

const columns = computed<TableColumn<Visit>[]>(() => [
  ...(can.assign
    ? [
        {
          id: "select",
          header: ({ table }: { table: any }) =>
            h(UCheckbox, {
              modelValue: table.getIsSomePageRowsSelected() ? "indeterminate" : table.getIsAllPageRowsSelected(),
              "onUpdate:modelValue": (value: boolean | "indeterminate") => table.toggleAllPageRowsSelected(!!value),
              "aria-label": t("common.selectAll"),
            }),
          cell: ({ row }: { row: any }) =>
            h(UCheckbox, {
              modelValue: row.getIsSelected(),
              "onUpdate:modelValue": (value: boolean | "indeterminate") => row.toggleSelected(!!value),
              "aria-label": t("common.selectRow"),
              onClick: (e: Event) => e.stopPropagation(),
            }),
        },
      ]
    : []),
  { id: "when", header: t("cs.maintenance.when") },
  { id: "customer", header: t("cs.maintenance.customer") },
  { id: "products", header: t("cs.profile.products") },
  { id: "place", header: t("cs.customers.address") },
  { id: "technician", header: t("cs.maintenance.technician") },
  { id: "actions", header: "" },
]);

const pagination = ref({ pageIndex: 0, pageSize: 50 });
watch([period, techFilter, search, areaFilter], () => {
  pagination.value = { ...pagination.value, pageIndex: 0 };
  rowSelection.value = {};
});
const pagedCards = computed(() =>
  filtered.value.slice(pagination.value.pageIndex * pagination.value.pageSize, (pagination.value.pageIndex + 1) * pagination.value.pageSize),
);

// ---- Actions
const assignOpen = ref(false);
const assignProducts = ref<CsProduct[]>([]);
function openAssign(list: Visit[]) {
  assignProducts.value = list.flatMap((v) => v.products);
  assignOpen.value = true;
}

// Mark done: the dialog with the spare parts, visit fee, notes, next visit and signature,
// for the products of this visit.
const doneOpen = ref(false);
const doneProducts = ref<CsProduct[]>([]);
function openDone(v: Visit) {
  doneProducts.value = v.products;
  doneOpen.value = true;
}
async function onSaved() {
  clearSelection();
  await refresh();
}

const dayLabel = (v: Visit) => {
  const today = startOfToday();
  if (v.at < today) return { text: t("cs.maintenance.overdue"), tone: "error" as const };
  if (v.at < today + 86_400_000) return { text: t("cs.maintenance.today"), tone: "warning" as const };
  return null;
};
// A visit opens its customer for people who can use the Customer Service pages.
function openCustomer(id: string) {
  if (hasPermission("cs_customers", "view") || hasAnyModulePermission("cs_customers")) navigateTo(`/cs/customers/${id}`);
}
const productsText = (v: Visit) => v.products.map((p) => `${p.name}${(p.quantity ?? 1) > 1 ? ` × ${p.quantity}` : ""}`);
</script>

<template>
  <UDashboardPanel :ui="{ body: 'kords-canvas' }">
    <template #header>
      <KPageHeader :title="t('cs.confirmedVisits.title')" :count="visits.length" />

      <div class="kords-filterbar w-full space-y-3 border-b border-default px-4 py-3 sm:px-6">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <div class="-mx-4 min-w-0 overflow-x-auto overflow-y-hidden px-4 [scrollbar-width:none] sm:mx-0 sm:px-0 [&::-webkit-scrollbar]:hidden">
            <UTabs v-if="viewMode === 'list'" v-model="period" :items="periodTabs" value-key="value" variant="link" size="sm" :content="false" class="kords-pilltabs w-max min-w-full sm:w-auto sm:min-w-0" />
            <div v-else class="flex items-center gap-2">
              <UTabs v-model="calRange" :items="calTabs" value-key="value" variant="link" size="sm" :content="false" class="kords-pilltabs w-max" />
              <UButton icon="i-lucide-chevron-right" size="sm" color="neutral" variant="outline" :aria-label="t('cs.confirmedVisits.previous')" class="rtl:rotate-180" @click="shiftCal(-1)" />
              <UButton size="sm" color="neutral" variant="outline" :label="t('cs.maintenance.today')" @click="backToToday" />
              <UButton icon="i-lucide-chevron-left" size="sm" color="neutral" variant="outline" :aria-label="t('cs.confirmedVisits.next')" class="rtl:rotate-180" @click="shiftCal(1)" />
            </div>
          </div>
          <UButtonGroup class="kords-segment">
            <UButton icon="i-lucide-list" color="neutral" variant="ghost" :class="viewMode === 'list' && 'kords-segment-on'" :aria-label="t('cs.confirmedVisits.viewList')" @click="setView('list')" />
            <UButton icon="i-lucide-calendar-days" color="neutral" variant="ghost" :class="viewMode === 'calendar' && 'kords-segment-on'" :aria-label="t('cs.confirmedVisits.viewCalendar')" @click="setView('calendar')" />
          </UButtonGroup>
        </div>
        <!-- Technician: everyone, unassigned, or one technician's visits -->
        <div v-if="seesAll" class="-mx-4 flex items-center gap-2 overflow-x-auto px-4 pb-0.5 [scrollbar-width:none] sm:mx-0 sm:px-0 [&::-webkit-scrollbar]:hidden">
          <button
            v-for="c in techChips"
            :key="c.key"
            type="button"
            class="kords-chip"
            :class="techFilter === c.key && 'kords-chip-on'"
            @click="techFilter = c.key"
          >
            <UIcon v-if="c.key !== 'all' && c.key !== 'none'" name="i-lucide-hard-hat" class="size-3.5" />
            {{ c.label }}
            <span class="kords-chip-count">{{ c.count }}</span>
          </button>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <UInput v-model="search" icon="i-lucide-search" :placeholder="t('cs.maintenance.search')" class="min-w-0 flex-1 basis-56" />
          <USelect v-model="areaFilter" :items="areaItems" value-key="value" icon="i-lucide-map-pin" class="w-44" />
        </div>
      </div>
    </template>

    <template #body>
      <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>
      <ConfirmedVisitsCalendar
        v-else-if="viewMode === 'calendar'"
        :visits="calendarVisits"
        :mode="calMode"
        :start="calStart"
        :customer-title="customerTitleOf"
        :tech-name="techName"
        @select="onCalendarSelect"
      />
      <div v-else-if="!filtered.length" class="kords-card flex flex-col items-center gap-2 py-16 text-center">
        <UIcon name="i-lucide-phone-call" class="size-8 text-muted" />
        <p class="text-sm text-muted">{{ t("cs.confirmedVisits.empty") }}</p>
        <p class="max-w-md text-xs text-muted">{{ t("cs.confirmedVisits.hint") }}</p>
      </div>

      <template v-else>
        <div v-if="can.assign && selectedVisits.length" class="hidden items-center gap-3 md:flex">
          <span class="text-sm text-muted">{{ t("cs.confirmedVisits.selected", { count: selectedVisits.length }) }}</span>
          <UButton icon="i-lucide-user-check" size="sm" :label="t('cs.maintenance.assign')" @click="openAssign(selectedVisits)" />
          <UButton icon="i-lucide-x" size="sm" color="neutral" variant="ghost" :label="t('cs.customers.clearSelection')" @click="clearSelection" />
        </div>

        <!-- Phone: cards -->
        <div class="space-y-2 md:hidden">
          <div v-for="v in pagedCards" :key="v.key" class="kords-kcard border border-default bg-default p-3 text-sm" :class="v.at < startOfToday() && 'kords-kcard-late'">
            <div class="flex items-start justify-between gap-2">
              <button type="button" class="min-w-0 text-start" @click="openCustomer(v.customerId)">
                <div class="truncate font-semibold text-highlighted">
                  {{ customerById.get(v.customerId) ? customerTitle(customerById.get(v.customerId)!) : "—" }}
                </div>
                <div class="text-xs text-muted">{{ formatDateTime(new Date(v.at).toISOString()) }}</div>
              </button>
              <KBadge v-if="dayLabel(v)" :label="dayLabel(v)!.text" :tone="dayLabel(v)!.tone" />
            </div>
            <ul class="mt-2 space-y-0.5 text-xs text-toned">
              <li v-for="n in productsText(v)" :key="n" class="truncate">{{ n }}</li>
            </ul>
            <div class="mt-2 flex items-center justify-between gap-2 text-xs">
              <span class="flex items-center gap-1.5">
                <KAvatar v-if="technicianOf(v) && technicianOf(v) !== 'mixed'" :name="techName(technicianOf(v) as string)" kind="user" size="2xs" />
                <span :class="technicianOf(v) ? 'text-highlighted' : 'text-muted'">
                  {{ technicianOf(v) === "mixed" ? t("cs.confirmedVisits.mixed") : techName(technicianOf(v) as string | null) || t("cs.maintenance.unassigned") }}
                </span>
              </span>
              <div class="flex items-center gap-1">
                <UButton v-if="can.assign" size="xs" color="neutral" variant="soft" icon="i-lucide-user-check" :label="t(technicianOf(v) ? 'cs.maintenance.reassign' : 'cs.maintenance.assign')" @click="openAssign([v])" />
                <UButton v-if="can.complete" size="xs" color="success" variant="soft" icon="i-lucide-check" :label="t('cs.maintenance.markDone')" @click="openDone(v)" />
              </div>
            </div>
          </div>
        </div>

        <!-- Desktop: table -->
        <UTable
          v-model:row-selection="rowSelection"
          :get-row-id="(row: Visit) => row.key"
          v-model:pagination="pagination"
          :data="filtered"
          :columns="columns"
          :pagination-options="{ getPaginationRowModel: getPaginationRowModel() }"
          :ui="{ root: 'kords-card hidden shrink-0 overflow-hidden md:block [&_tbody_tr]:cursor-pointer' }"
          @select="(_e, row) => openCustomer(row.original.customerId)"
        >
          <template #when-cell="{ row }">
            <div class="whitespace-nowrap">
              <div class="text-sm font-medium" :class="row.original.at < startOfToday() ? 'text-error' : 'text-highlighted'">
                {{ formatDateTime(new Date(row.original.at).toISOString()) }}
              </div>
              <KBadge v-if="dayLabel(row.original)" :label="dayLabel(row.original)!.text" :tone="dayLabel(row.original)!.tone" class="mt-1" />
            </div>
          </template>
          <template #customer-cell="{ row }">
            <div class="min-w-0">
              <div class="truncate font-medium text-highlighted">
                {{ customerById.get(row.original.customerId) ? customerTitle(customerById.get(row.original.customerId)!) : "—" }}
              </div>
              <div class="flex items-center gap-1 text-xs text-toned">
                <bdi v-if="customerById.get(row.original.customerId)?.phone" dir="ltr">{{ customerById.get(row.original.customerId)?.phone }}</bdi>
                <a
                  v-if="toWhatsAppLink(customerById.get(row.original.customerId)?.phone)"
                  :href="toWhatsAppLink(customerById.get(row.original.customerId)?.phone)!"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-[#25D366]"
                  @click.stop
                >
                  <UIcon name="i-simple-icons-whatsapp" class="size-3.5" />
                </a>
              </div>
            </div>
          </template>
          <template #products-cell="{ row }">
            <ul class="space-y-0.5 text-sm">
              <li v-for="n in productsText(row.original).slice(0, 3)" :key="n" class="max-w-56 truncate">{{ n }}</li>
              <li v-if="row.original.products.length > 3" class="text-xs text-muted">+{{ row.original.products.length - 3 }}</li>
            </ul>
          </template>
          <template #place-cell="{ row }">
            <div class="max-w-64 text-sm">
              <div v-if="areaName(customerById.get(row.original.customerId)?.area_id)" class="text-highlighted">
                {{ areaName(customerById.get(row.original.customerId)?.area_id) }}
              </div>
              <div class="line-clamp-2 text-xs text-muted">{{ customerById.get(row.original.customerId)?.address || "—" }}</div>
            </div>
          </template>
          <template #technician-cell="{ row }">
            <div v-if="technicianOf(row.original) === 'mixed'" class="text-sm text-muted">{{ t("cs.confirmedVisits.mixed") }}</div>
            <div v-else-if="technicianOf(row.original)" class="flex items-center gap-1.5 text-sm">
              <KAvatar :name="techName(technicianOf(row.original) as string)" kind="user" size="2xs" />
              <span class="truncate">{{ techName(technicianOf(row.original) as string) }}</span>
            </div>
            <KBadge v-else :label="t('cs.maintenance.unassigned')" tone="warning" outlined />
          </template>
          <template #actions-cell="{ row }">
            <div class="flex items-center justify-end gap-1">
              <UButton
                v-if="can.assign"
                size="xs"
                color="neutral"
                variant="soft"
                icon="i-lucide-user-check"
                :label="t(technicianOf(row.original) ? 'cs.maintenance.reassign' : 'cs.maintenance.assign')"
                @click.stop="openAssign([row.original])"
              />
              <UButton
                v-if="can.complete"
                size="xs"
                color="success"
                variant="soft"
                icon="i-lucide-check"
                :label="t('cs.maintenance.markDone')"
                @click.stop="openDone(row.original)"
              />
            </div>
          </template>
        </UTable>

        <div class="mt-3 flex flex-wrap items-center justify-between gap-2">
          <span class="text-sm text-muted">{{ t("cs.confirmedVisits.count", { count: filtered.length }) }}</span>
          <UPagination
            :page="pagination.pageIndex + 1"
            :items-per-page="pagination.pageSize"
            :total="filtered.length"
            :sibling-count="1"
            @update:page="(p: number) => (pagination = { ...pagination, pageIndex: p - 1 })"
          />
        </div>
      </template>
    </template>
  </UDashboardPanel>

  <MaintenanceAssignModal v-model:open="assignOpen" :products="assignProducts" @saved="onSaved" />
  <MaintenanceDoneModal v-model:open="doneOpen" :products="doneProducts" @saved="onSaved" />
</template>
