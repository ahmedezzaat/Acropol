<script setup lang="ts">
// Report: the spare parts used in maintenance visits in a period — one row per part
// used, with totals per part — and an export to PDF (the print sheet).
definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "reports", action: "spare_parts_used" },
});

const { t } = useI18n();
const toast = useToast();
const { loadSparePartsUsed, summarizeParts, loadTechnicians, loadAreaOptions } = useReports();

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

const rows = ref<SparePartUsedRow[]>([]);
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
    rows.value = await loadSparePartsUsed(filters.value);
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

const totalValue = computed(() => rows.value.reduce((n, r) => n + r.line_total, 0));
const totalQty = computed(() => rows.value.reduce((n, r) => n + r.quantity, 0));
const summary = computed(() => summarizeParts(rows.value));
const money = (v: number) => formatReportMoney(v, t("common.currency"));

function exportPdf() {
  const q = new URLSearchParams({ from: from.value, to: to.value });
  if (technician.value !== ALL) q.set("technician", technician.value);
  if (area.value !== ALL) q.set("area", area.value);
  window.open(`/cs/reports/spare-parts-used-print?${q.toString()}`, "_blank");
}
</script>

<template>
  <UDashboardPanel :ui="{ body: 'kords-canvas' }">
    <template #header>
      <UDashboardNavbar :title="t('reports.sparePartsUsed.title')">
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
          <KBadge :label="t('reports.sparePartsUsed.parts', { count: totalQty })" tone="primary" />
          <KBadge :label="`${t('reports.sparePartsUsed.grandTotal')}: ${money(totalValue)}`" tone="success" />
        </div>

        <div v-if="loading" class="flex justify-center py-16">
          <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
        </div>
        <p v-else-if="!rows.length" class="kords-card p-10 text-center text-sm text-muted">{{ t("reports.sparePartsUsed.noData") }}</p>
        <template v-else>
          <div class="kords-card overflow-x-auto">
            <table class="w-full min-w-[56rem] text-sm">
              <thead>
                <tr class="border-b border-default text-xs text-muted">
                  <th class="px-4 py-3 text-start font-medium">{{ t("reports.maintenanceDone.date") }}</th>
                  <th class="px-4 py-3 text-start font-medium">{{ t("reports.maintenanceDone.customer") }}</th>
                  <th class="px-4 py-3 text-start font-medium">{{ t("reports.maintenanceDone.area") }}</th>
                  <th class="px-4 py-3 text-start font-medium">{{ t("reports.maintenanceDone.technician") }}</th>
                  <th class="px-4 py-3 text-start font-medium">{{ t("reports.sparePartsUsed.part") }}</th>
                  <th class="px-4 py-3 text-end font-medium">{{ t("reports.sparePartsUsed.qty") }}</th>
                  <th class="px-4 py-3 text-end font-medium">{{ t("reports.sparePartsUsed.unitPrice") }}</th>
                  <th class="px-4 py-3 text-end font-medium">{{ t("reports.sparePartsUsed.lineTotal") }}</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-default">
                <tr v-for="r in rows" :key="r.used_id" class="hover:bg-elevated">
                  <td class="whitespace-nowrap px-4 py-3">{{ formatDMY(r.done_on) }}</td>
                  <td class="px-4 py-3">
                    <NuxtLink :to="`/cs/customers/${r.customer_id}`" class="font-medium text-highlighted hover:text-primary">{{ r.customer_name }}</NuxtLink>
                  </td>
                  <td class="px-4 py-3">{{ r.area_name || "—" }}</td>
                  <td class="px-4 py-3">{{ r.technician_name || "—" }}</td>
                  <td class="px-4 py-3 font-medium text-highlighted">{{ r.part_name }}</td>
                  <td class="px-4 py-3 text-end">{{ r.quantity }}</td>
                  <td class="whitespace-nowrap px-4 py-3 text-end">{{ money(r.unit_price) }}</td>
                  <td class="whitespace-nowrap px-4 py-3 text-end font-medium">{{ money(r.line_total) }}</td>
                </tr>
              </tbody>
              <tfoot>
                <tr class="border-t border-default bg-muted font-semibold">
                  <td class="px-4 py-3" colspan="5">{{ t("reports.sparePartsUsed.grandTotal") }}</td>
                  <td class="px-4 py-3 text-end">{{ totalQty }}</td>
                  <td />
                  <td class="whitespace-nowrap px-4 py-3 text-end">{{ money(totalValue) }}</td>
                </tr>
              </tfoot>
            </table>
          </div>

          <div class="kords-card overflow-x-auto">
            <h3 class="border-b border-default px-4 py-3 text-sm font-semibold text-highlighted">{{ t("reports.sparePartsUsed.summary") }}</h3>
            <table class="w-full min-w-[24rem] text-sm">
              <tbody class="divide-y divide-default">
                <tr v-for="g in summary" :key="g.name">
                  <td class="px-4 py-2 font-medium text-highlighted">{{ g.name }}</td>
                  <td class="px-4 py-2 text-end">{{ g.quantity }}</td>
                  <td class="whitespace-nowrap px-4 py-2 text-end font-medium">{{ money(g.total) }}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </template>
      </div>
    </template>
  </UDashboardPanel>
</template>
