<script setup lang="ts">
// Report: maintenance appointments that were rescheduled in a period — when it was
// done, the old and new date, customer, reason and who did it — with an export to PDF.
definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "reports", action: "maintenance_rescheduled" },
});

const { t, locale } = useI18n();
const toast = useToast();
const { loadMaintenanceRescheduled, loadAgents } = useReports();

const ALL = "all";
const initial = reportRange("thisMonth");
const from = ref(initial.from);
const to = ref(initial.to);
const agent = ref(ALL);

const agentItems = ref<ReportOption[]>([]);
const agentOptions = computed(() => [{ label: t("reports.maintenanceRescheduled.allAgents"), value: ALL }, ...agentItems.value]);

const rows = ref<MaintenanceRescheduledRow[]>([]);
const loading = ref(true);

const filters = computed<MaintenanceRescheduledFilters>(() => ({
  from: from.value,
  to: to.value,
  agent: agent.value === ALL ? null : agent.value,
}));

async function reload() {
  if (!from.value || !to.value || from.value > to.value) {
    rows.value = [];
    loading.value = false;
    return;
  }
  loading.value = true;
  try {
    rows.value = await loadMaintenanceRescheduled(filters.value);
  } catch (e) {
    rows.value = [];
    toast.add({ title: (e as Error).message, color: "error" });
  }
  loading.value = false;
}

onMounted(async () => {
  agentItems.value = await loadAgents();
});
watch([from, to, agent], reload, { immediate: true });

const quickRanges = ["thisWeek", "thisMonth", "lastMonth", "last30", "thisYear"] as const;
const activeRange = computed(() => quickRanges.find((k) => reportRange(k).from === from.value && reportRange(k).to === to.value) ?? null);
function setRange(kind: (typeof quickRanges)[number]) {
  const r = reportRange(kind);
  from.value = r.from;
  to.value = r.to;
}
function setAgent(v: unknown) {
  agent.value = typeof v === "string" && v ? v : ALL;
}

function exportPdf() {
  const q = new URLSearchParams({ from: from.value, to: to.value });
  if (agent.value !== ALL) q.set("agent", agent.value);
  window.open(`/cs/reports/maintenance-rescheduled-print?${q.toString()}`, "_blank");
}
</script>

<template>
  <UDashboardPanel :ui="{ body: 'kords-canvas' }">
    <template #header>
      <UDashboardNavbar :title="t('reports.maintenanceRescheduled.title')">
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
            <UFormField :label="t('reports.maintenanceRescheduled.agent')">
              <USelect :model-value="agent" :items="agentOptions" value-key="value" class="w-48" @update:model-value="setAgent" />
            </UFormField>
          </div>
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <KBadge :label="t('reports.rows', { count: rows.length })" tone="primary" />
        </div>

        <div v-if="loading" class="flex justify-center py-16">
          <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
        </div>
        <p v-else-if="!rows.length" class="kords-card p-10 text-center text-sm text-muted">{{ t("reports.noDataRescheduled") }}</p>
        <div v-else class="kords-card overflow-x-auto">
          <table class="w-full min-w-[56rem] text-sm">
            <thead>
              <tr class="border-b border-default text-xs text-muted">
                <th class="px-4 py-3 text-start font-medium">{{ t("reports.maintenanceRescheduled.doneAt") }}</th>
                <th class="px-4 py-3 text-start font-medium">{{ t("reports.maintenanceRescheduled.oldDate") }}</th>
                <th class="px-4 py-3 text-start font-medium">{{ t("reports.maintenanceRescheduled.newDate") }}</th>
                <th class="px-4 py-3 text-start font-medium">{{ t("reports.maintenanceRescheduled.customer") }}</th>
                <th class="px-4 py-3 text-start font-medium">{{ t("reports.maintenanceRescheduled.reason") }}</th>
                <th class="px-4 py-3 text-start font-medium">{{ t("reports.maintenanceRescheduled.agent") }}</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-default">
              <tr v-for="(r, i) in rows" :key="i" class="align-top hover:bg-elevated">
                <td class="whitespace-nowrap px-4 py-3">{{ formatDMYTime(r.done_at, locale) }}</td>
                <td class="whitespace-nowrap px-4 py-3">{{ r.old_at ? formatDMYTime(r.old_at, locale) : "—" }}</td>
                <td class="whitespace-nowrap px-4 py-3 font-medium text-highlighted">{{ formatDMYTime(r.new_at, locale) }}</td>
                <td class="px-4 py-3">
                  <NuxtLink :to="`/cs/customers/${r.customer_id}`" class="font-medium text-highlighted hover:text-primary">{{ r.customer_name }}</NuxtLink>
                </td>
                <td class="px-4 py-3 text-toned">{{ r.reason || "—" }}</td>
                <td class="px-4 py-3">{{ r.agent_name || "—" }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </template>
  </UDashboardPanel>
</template>
