<script setup lang="ts">
// The printable A4 sheet of the Done maintenance report. It opens the print
// dialog by itself — choose "Save as PDF" there. Filters come from the query:
// ?from=YYYY-MM-DD&to=YYYY-MM-DD[&technician=<id>][&area=<id>].
definePageMeta({
  layout: false,
  crmPermission: { module: "reports", action: "maintenance_done" },
});

const route = useRoute();
const supabase = useSupabaseClient();
const user = useSupabaseUser();
const { t, locale } = useI18n();
const { loadMaintenanceDone, loadTechnicians, loadAreaOptions } = useReports();

const q = (key: string) => (typeof route.query[key] === "string" ? (route.query[key] as string) : null);
const range = reportRange("thisMonth");
const filters: MaintenanceDoneFilters = {
  from: q("from") ?? range.from,
  to: q("to") ?? range.to,
  technician: q("technician"),
  area: q("area"),
};

const { data } = await useAsyncData("report-maintenance-done-print", async () => {
  const [rows, technicians, areas, me] = await Promise.all([
    loadMaintenanceDone(filters),
    filters.technician ? loadTechnicians() : Promise.resolve([] as ReportOption[]),
    filters.area ? loadAreaOptions() : Promise.resolve([] as ReportOption[]),
    supabase.from("profiles").select("full_name, email").eq("id", user.value?.sub as string).maybeSingle(),
  ]);
  return {
    rows,
    technicianName: technicians.find((o) => o.value === filters.technician)?.label ?? null,
    areaName: areas.find((o) => o.value === filters.area)?.label ?? null,
    by: me.data?.full_name || me.data?.email || "",
  };
});

const rows = computed(() => data.value?.rows ?? []);
const totalCost = computed(() => rows.value.reduce((n, r) => n + r.cost, 0));
const money = (v: number) => formatReportMoney(v, t("common.currency"));

function doPrint() {
  window.print();
}
onMounted(() => {
  // let the sheet paint before the print dialog opens
  setTimeout(doPrint, 600);
});
</script>

<template>
  <div class="sheet-wrap">
    <div class="no-print toolbar">
      <button type="button" class="btn" @click="doPrint">{{ t("reports.printButton") }}</button>
      <NuxtLink to="/cs/reports/maintenance-done" class="btn ghost">{{ t("reports.back") }}</NuxtLink>
      <span class="hint">{{ t("reports.printHint") }}</span>
    </div>

    <article class="sheet" :dir="locale === 'ar' ? 'rtl' : 'ltr'">
      <header class="doc-head">
        <div class="brand">{{ t("nav.appName") }}</div>
        <div class="doc-title">{{ t("reports.maintenanceDone.title") }}</div>
      </header>

      <dl class="meta">
        <div><dt>{{ t("reports.period") }}</dt><dd>{{ formatDMY(filters.from) }} – {{ formatDMY(filters.to) }}</dd></div>
        <div><dt>{{ t("reports.technician") }}</dt><dd>{{ data?.technicianName ?? t("reports.allTechnicians") }}</dd></div>
        <div><dt>{{ t("reports.area") }}</dt><dd>{{ data?.areaName ?? t("reports.allAreas") }}</dd></div>
        <div><dt>{{ t("reports.total") }}</dt><dd>{{ t("reports.rows", { count: rows.length }) }}</dd></div>
      </dl>

      <p v-if="!rows.length" class="empty">{{ t("reports.noData") }}</p>
      <table v-else class="rows">
        <thead>
          <tr>
            <th>{{ t("reports.maintenanceDone.date") }}</th>
            <th>{{ t("reports.maintenanceDone.technician") }}</th>
            <th>{{ t("reports.maintenanceDone.customer") }}</th>
            <th>{{ t("reports.maintenanceDone.area") }}</th>
            <th>{{ t("reports.maintenanceDone.contract") }}</th>
            <th class="num">{{ t("reports.maintenanceDone.cost") }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="r in rows" :key="r.visit_key">
            <td class="nowrap">{{ formatDMY(r.done_on) }}</td>
            <td>{{ r.technician_name || "—" }}</td>
            <td>{{ r.customer_name }}</td>
            <td>{{ r.area_name || "—" }}</td>
            <td class="nowrap"><bdi dir="ltr">{{ r.contract_codes || "—" }}</bdi></td>
            <td class="num nowrap">{{ r.cost ? money(r.cost) : "—" }}</td>
          </tr>
        </tbody>
        <tfoot>
          <tr>
            <td colspan="5">{{ t("reports.maintenanceDone.totalCost") }}</td>
            <td class="num nowrap">{{ money(totalCost) }}</td>
          </tr>
        </tfoot>
      </table>

      <footer class="foot">{{ t("reports.generated", { name: data?.by ?? "", date: formatDMYTime(new Date(), locale) }) }}</footer>
    </article>
  </div>
</template>

<style scoped>
.sheet-wrap {
  min-height: 100vh;
  background: #e5e7eb;
  padding: 16px;
  font-family: inherit;
  color: #111827;
}
.toolbar {
  max-width: 210mm;
  margin: 0 auto 12px;
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 10px;
}
.btn {
  background: #1d4ed8;
  color: #fff;
  border: 0;
  padding: 8px 16px;
  font-size: 14px;
  cursor: pointer;
  text-decoration: none;
}
.btn.ghost {
  background: #fff;
  color: #111827;
  border: 1px solid #d1d5db;
}
.hint {
  color: #6b7280;
  font-size: 12px;
}
.sheet {
  width: 210mm;
  min-height: 297mm;
  margin: 0 auto;
  background: #fff;
  padding: 14mm 12mm;
  font-size: 12px;
  line-height: 1.5;
}
.doc-head {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  border-bottom: 2px solid #111827;
  padding-bottom: 8px;
  margin-bottom: 12px;
}
.brand {
  font-size: 18px;
  font-weight: 700;
}
.doc-title {
  font-size: 16px;
  font-weight: 600;
}
.meta {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 8px;
  margin: 0 0 14px;
}
.meta dt {
  color: #6b7280;
  font-size: 11px;
}
.meta dd {
  margin: 0;
  font-weight: 600;
}
.rows {
  width: 100%;
  border-collapse: collapse;
}
.rows th,
.rows td {
  border: 1px solid #d1d5db;
  padding: 5px 8px;
  text-align: start;
}
.rows th {
  background: #f3f4f6;
  font-weight: 600;
}
.rows .num {
  text-align: end;
}
.rows .nowrap {
  white-space: nowrap;
}
.rows tfoot td {
  background: #f3f4f6;
  font-weight: 700;
}
.rows tr {
  break-inside: avoid;
}
.rows thead {
  display: table-header-group;
}
.empty {
  text-align: center;
  padding: 30px;
  color: #6b7280;
}
.foot {
  margin-top: 14px;
  color: #6b7280;
  font-size: 11px;
}
@media print {
  .sheet-wrap {
    background: #fff;
    padding: 0;
  }
  .no-print {
    display: none;
  }
  .sheet {
    width: auto;
    min-height: 0;
    padding: 0;
  }
}
</style>

<style>
@media print {
  @page {
    size: A4;
    margin: 12mm 12mm 16mm;
  }
}
</style>
