<script setup lang="ts">
// Report: maintenance visits that were carried out in a period — date, technician,
// customer, area and cost — with an export to PDF (the print sheet).
definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "reports", action: "maintenance_done" },
});

const { t } = useI18n();
const toast = useToast();
const { loadMaintenanceDone, loadTechnicians, loadAreaOptions } = useReports();

const ALL = "all";
const initial = reportRange("thisMonth");
const from = ref(initial.from);
const to = ref(initial.to);
const technician = ref(ALL);
const area = ref(ALL);

const technicianItems = ref<ReportOption[]>([]);
const areaItems = ref<ReportOption[]>([]);
const technicianOptions = computed(() => [{ label: t("reports.allTechnicians"), value: ALL }, ...technicianItems.value]);
const areaOptions = computed(() => [{ label: t("reports.allAreas"), value: ALL }, ...areaItems.value]);

const rows = ref<MaintenanceDoneRow[]>([]);
const loading = ref(true);

const filters = computed<MaintenanceDoneFilters>(() => ({
  from: from.value,
  to: to.value,
  technician: technician.value === ALL ? null : technician.value,
  area: area.value === ALL ? null : area.value,
}));

async function reload() {
  if (!from.value || !to.value || from.value > to.value) {
    rows.value = [];
    loading.value = false;
    return;
  }
  loading.value = true;
  try {
    rows.value = await loadMaintenanceDone(filters.value);
  } catch (e) {
    rows.value = [];
    toast.add({ title: (e as Error).message, color: "error" });
  }
  loading.value = false;
}

onMounted(async () => {
  [technicianItems.value, areaItems.value] = await Promise.all([loadTechnicians(), loadAreaOptions()]);
});
watch([from, to, technician, area], reload, { immediate: true });

const quickRanges = ["thisWeek", "thisMonth", "lastMonth", "last30", "thisYear"] as const;
const activeRange = computed(() => quickRanges.find((k) => reportRange(k).from === from.value && reportRange(k).to === to.value) ?? null);
function setRange(kind: (typeof quickRanges)[number]) {
  const r = reportRange(kind);
  from.value = r.from;
  to.value = r.to;
}
function setTechnician(v: unknown) {
  technician.value = typeof v === "string" && v ? v : ALL;
}
function setArea(v: unknown) {
  area.value = typeof v === "string" && v ? v : ALL;
}

// Selecting visits to print their work orders together (none selected: every visit shown)
const selected = ref<Record<string, boolean>>({});
const selectedKeys = computed(() => rows.value.filter((r) => selected.value[r.visit_key]).map((r) => r.visit_key));
const allSelected = computed(() => rows.value.length > 0 && selectedKeys.value.length === rows.value.length);
function toggleAll(on: boolean) {
  selected.value = on ? Object.fromEntries(rows.value.map((r) => [r.visit_key, true])) : {};
}
watch(rows, () => (selected.value = {}));
// The work orders open in one document (one per page), to print or save as PDF. The visits are
// handed over through the browser's storage, so a long list does not make a long address.
function printWorkOrders() {
  const keys = selectedKeys.value.length ? selectedKeys.value : rows.value.map((r) => r.visit_key);
  if (!keys.length) return;
  const token = `wo-${Date.now()}`;
  try {
    localStorage.setItem(token, JSON.stringify(keys));
  } catch {
    toast.add({ title: t("reports.workOrder.bulkFailed"), color: "error" });
    return;
  }
  window.open(`/cs/reports/work-order-print?batch=${token}`, "_blank");
}

const totalCost = computed(() => rows.value.reduce((n, r) => n + r.cost, 0));
const money = (v: number) => formatReportMoney(v, t("common.currency"));

function exportPdf() {
  const q = new URLSearchParams({ from: from.value, to: to.value });
  if (technician.value !== ALL) q.set("technician", technician.value);
  if (area.value !== ALL) q.set("area", area.value);
  window.open(`/cs/reports/maintenance-done-print?${q.toString()}`, "_blank");
}
</script>

<template>
  <UDashboardPanel :ui="{ body: 'kords-canvas' }">
    <template #header>
      <UDashboardNavbar :title="t('reports.maintenanceDone.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton icon="i-lucide-file-down" :label="t('reports.exportPdf')" :disabled="!rows.length" @click="exportPdf" />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <div class="space-y-4">
        <div class="kords-filterbar space-y-3 p-3">
          <div class="flex flex-wrap items-center gap-2">
            <button
              v-for="k in quickRanges"
              :key="k"
              type="button"
              class="kords-chip"
              :class="activeRange === k && 'kords-chip-on'"
              @click="setRange(k)"
            >
              {{ t(`reports.${k}`) }}
            </button>
          </div>
          <div class="flex flex-wrap items-end gap-3">
            <UFormField :label="t('reports.from')">
              <UInput v-model="from" type="date" class="w-40" />
            </UFormField>
            <UFormField :label="t('reports.to')">
              <UInput v-model="to" type="date" class="w-40" />
            </UFormField>
            <UFormField :label="t('reports.technician')">
              <USelect :model-value="technician" :items="technicianOptions" value-key="value" class="w-48" @update:model-value="setTechnician" />
            </UFormField>
            <UFormField :label="t('reports.area')">
              <USelect :model-value="area" :items="areaOptions" value-key="value" class="w-48" @update:model-value="setArea" />
            </UFormField>
          </div>
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <KBadge :label="t('reports.rows', { count: rows.length })" tone="primary" />
          <KBadge :label="`${t('reports.maintenanceDone.totalCost')}: ${money(totalCost)}`" tone="success" />
          <UButton
            v-if="rows.length"
            icon="i-lucide-printer"
            color="neutral"
            variant="outline"
            size="sm"
            class="ms-auto"
            :label="selectedKeys.length ? t('reports.workOrder.printSelected', { count: selectedKeys.length }) : t('reports.workOrder.printAll', { count: rows.length })"
            @click="printWorkOrders"
          />
        </div>

        <div v-if="loading" class="flex justify-center py-16">
          <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
        </div>
        <p v-else-if="!rows.length" class="kords-card p-10 text-center text-sm text-muted">{{ t("reports.noData") }}</p>
        <div v-else class="kords-card overflow-x-auto">
          <table class="w-full min-w-[40rem] text-sm">
            <thead>
              <tr class="border-b border-default text-start text-xs text-muted">
                <th class="w-10 px-3 py-3"><UCheckbox :model-value="allSelected" :aria-label="t('common.selectAll')" @update:model-value="(v: boolean | 'indeterminate') => toggleAll(v === true)" /></th>
                <th class="px-4 py-3 text-start font-medium">{{ t("reports.maintenanceDone.date") }}</th>
                <th class="px-4 py-3 text-start font-medium">{{ t("reports.maintenanceDone.technician") }}</th>
                <th class="px-4 py-3 text-start font-medium">{{ t("reports.maintenanceDone.customer") }}</th>
                <th class="px-4 py-3 text-start font-medium">{{ t("reports.maintenanceDone.area") }}</th>
                <th class="px-4 py-3 text-start font-medium">{{ t("reports.maintenanceDone.contract") }}</th>
                <th class="px-4 py-3 text-end font-medium">{{ t("reports.maintenanceDone.cost") }}</th>
                <th class="w-12 px-2 py-3"><span class="sr-only">{{ t("reports.workOrder.print") }}</span></th>
              </tr>
            </thead>
            <tbody class="divide-y divide-default">
              <tr v-for="r in rows" :key="r.visit_key" class="hover:bg-elevated">
                <td class="px-3 py-3"><UCheckbox v-model="selected[r.visit_key]" :aria-label="t('common.selectRow')" /></td>
                <td class="whitespace-nowrap px-4 py-3">{{ formatDMY(r.done_on) }}</td>
                <td class="px-4 py-3">{{ r.technician_name || "—" }}</td>
                <td class="px-4 py-3">
                  <NuxtLink :to="`/cs/customers/${r.customer_id}`" class="font-medium text-highlighted hover:text-primary">{{ r.customer_name }}</NuxtLink>
                </td>
                <td class="px-4 py-3">{{ r.area_name || "—" }}</td>
                <td class="px-4 py-3"><bdi dir="ltr">{{ r.contract_codes || "—" }}</bdi></td>
                <td class="whitespace-nowrap px-4 py-3 text-end font-medium">{{ r.cost ? money(r.cost) : "—" }}</td>
                <td class="px-2 py-2 text-end">
                  <UButton icon="i-lucide-printer" color="neutral" variant="ghost" size="sm" :title="t('reports.workOrder.print')" :aria-label="t('reports.workOrder.print')" :to="`/cs/reports/work-order-print?visit=${r.visit_key}`" target="_blank" />
                </td>
              </tr>
            </tbody>
            <tfoot>
              <tr class="border-t border-default bg-muted font-semibold">
                <td class="px-4 py-3" colspan="6">{{ t("reports.total") }} · {{ t("reports.rows", { count: rows.length }) }}</td>
                <td class="whitespace-nowrap px-4 py-3 text-end">{{ money(totalCost) }}</td>
                <td />
              </tr>
            </tfoot>
          </table>
        </div>
      </div>
    </template>
  </UDashboardPanel>
</template>
