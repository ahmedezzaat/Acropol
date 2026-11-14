<script setup lang="ts">
// Customer Service quotations (عروض الأسعار): spare parts and services offered to a customer, mostly companies.
definePageMeta({ layout: "dashboard", crmPermission: { module: "cs_customers" } });
useHead({ htmlAttrs: { class: "carbon kords" } });

const supabase = useSupabaseClient();
const { t } = useI18n();

interface Row {
  id: string;
  number: string;
  status: QuotationStatus;
  issue_date: string;
  valid_until: string | null;
  total: number;
  created_by: string | null;
  customer: { id: string; name: string; company: string | null; phone: string | null } | null;
}
const { data: quotations, status } = await useAsyncData<Row[]>("cs-quotations", async () => {
  const { data } = await supabase
    .from("cs_quotations")
    .select("id, number, status, issue_date, valid_until, total, created_by, customer:customers(id, name, company, phone)")
    .order("created_at", { ascending: false });
  return ((data ?? []) as unknown as Row[]).map((r) => ({ ...r, total: Number(r.total) }));
});
const { data: people } = await useAsyncData<Record<string, string>>("cs-quotations-people", async () => {
  const { data } = await supabase.from("profiles").select("id, full_name, email");
  return Object.fromEntries((data ?? []).map((p) => [p.id as string, ((p.full_name as string) || (p.email as string))]));
});

const tab = ref<"all" | QuotationStatus>("all");
const search = ref("");
const counts = computed(() => {
  const all = quotations.value ?? [];
  return Object.fromEntries((["all", ...QUOTATION_STATUSES] as const).map((k) => [k, k === "all" ? all.length : all.filter((q) => q.status === k).length]));
});
const tabs = computed(() => (["all", ...QUOTATION_STATUSES] as const).map((k) => ({ value: k, label: `${k === "all" ? t("common.all") : t(`cs.quotations.status.${k}`)} (${counts.value[k]})` })));
const customerLabel = (q: Row) => q.customer?.company || q.customer?.name || "—";
const rows = computed(() => {
  const s = search.value.trim().toLowerCase();
  return (quotations.value ?? []).filter((q) => {
    if (tab.value !== "all" && q.status !== tab.value) return false;
    if (!s) return true;
    return `${q.number} ${q.customer?.name ?? ""} ${q.customer?.company ?? ""}`.toLowerCase().includes(s) || phoneMatches(q.customer?.phone ?? null, search.value);
  });
});
const money = (v: number) => formatReportMoney(v, t("common.currency"));
const approvedTotal = computed(() => rows.value.filter((q) => q.status === "approved").reduce((n, q) => n + q.total, 0));
</script>

<template>
  <UDashboardPanel :ui="{ body: 'kords-canvas' }">
    <template #header>
      <KPageHeader :title="t('cs.quotations.title')" :count="quotations?.length ?? 0">
        <template #right>
          <UButton icon="i-lucide-plus" :label="t('cs.quotations.new')" to="/cs/quotations/new" />
        </template>
      </KPageHeader>
      <div class="kords-filterbar flex flex-wrap items-center gap-2 border-b border-default px-4 py-3 sm:px-6">
        <UInput v-model="search" icon="i-lucide-search" :placeholder="t('cs.quotations.search')" class="min-w-0 flex-1 basis-60 lg:max-w-96 lg:flex-none" />
        <div class="-mx-1 overflow-x-auto px-1">
          <UTabs v-model="tab" :items="tabs" value-key="value" variant="pill" size="sm" :content="false" class="kords-segment-tabs w-max" />
        </div>
        <KBadge v-if="approvedTotal > 0" :label="`${t('cs.quotations.approvedTotal')}: ${money(approvedTotal)}`" tone="success" class="ms-auto" />
      </div>
    </template>

    <template #body>
      <div v-if="status === 'pending'" class="flex justify-center py-16"><UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" /></div>
      <p v-else-if="!rows.length" class="kords-card p-10 text-center text-sm text-muted">{{ t("cs.quotations.empty") }}</p>
      <div v-else class="kords-card overflow-x-auto">
        <table class="w-full min-w-[44rem] text-sm">
          <thead>
            <tr class="border-b border-default text-xs text-muted">
              <th class="px-4 py-3 text-start font-medium">{{ t("cs.quotations.number") }}</th>
              <th class="px-4 py-3 text-start font-medium">{{ t("cs.quotations.customer") }}</th>
              <th class="px-4 py-3 text-start font-medium">{{ t("cs.quotations.issueDate") }}</th>
              <th class="px-4 py-3 text-start font-medium">{{ t("cs.quotations.validUntil") }}</th>
              <th class="px-4 py-3 text-end font-medium">{{ t("cs.quotations.total") }}</th>
              <th class="px-4 py-3 text-start font-medium">{{ t("cs.quotations.statusLabel") }}</th>
              <th class="px-4 py-3 text-start font-medium">{{ t("cs.quotations.createdBy") }}</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-default">
            <tr v-for="q in rows" :key="q.id" class="cursor-pointer hover:bg-elevated" @click="navigateTo(`/cs/quotations/${q.id}`)">
              <td class="px-4 py-3 font-medium text-highlighted"><bdi dir="ltr">{{ q.number }}</bdi></td>
              <td class="px-4 py-3">{{ customerLabel(q) }}<div v-if="q.customer?.phone" class="text-xs text-muted" dir="ltr">{{ q.customer.phone }}</div></td>
              <td class="whitespace-nowrap px-4 py-3">{{ formatDMY(q.issue_date) }}</td>
              <td class="whitespace-nowrap px-4 py-3">{{ q.valid_until ? formatDMY(q.valid_until) : "—" }}</td>
              <td class="whitespace-nowrap px-4 py-3 text-end font-medium">{{ money(q.total) }}</td>
              <td class="px-4 py-3"><KBadge :label="t(`cs.quotations.status.${q.status}`)" :tone="QUOTATION_TONES[q.status]" /></td>
              <td class="px-4 py-3 text-muted">{{ (q.created_by && people?.[q.created_by]) || "—" }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>
  </UDashboardPanel>
</template>
