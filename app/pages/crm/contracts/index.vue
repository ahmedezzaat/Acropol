<script setup lang="ts">
// Contracts (العقود): the contracts generated when deals are won, newest first. Each opens its own contract page. (Customers themselves are managed in Customer Service.)
definePageMeta({ layout: "dashboard", crmPermission: { module: "crm_customers" } });
useHead({ htmlAttrs: { class: "carbon kords" } });

const supabase = useSupabaseClient();
const { t } = useI18n();

interface ContractRow {
  id: string;
  code: string | null;
  signed_on: string | null;
  notes: string | null;
  value: number | null;
  file_name: string | null;
  file_path: string | null;
  created_at: string;
  customer_id: string;
  deal_id: string | null;
  sales_person_id: string | null;
  customer: { id: string; name: string; company: string | null; phone: string | null; extra_phones: string[] | null; extra_phone_names: string[] | null; cs_pending: boolean } | null;
  deal: { id: string; title: string; assigned_to: string | null; value: number | null } | null;
  products: { name: string; quantity: number | null; sales_person_id: string | null }[] | null;
}

const { hasPermission } = usePermissions();
const canCreate = computed(() => hasPermission("crm_customers", "create"));
const canDelete = computed(() => hasPermission("crm_customers", "delete"));
const createOpen = ref(false);

const { data: contracts, status, refresh } = await useAsyncData<ContractRow[]>("crm-contracts", async () =>
  fetchAll<ContractRow>((from, to) =>
    supabase
      .from("contracts")
      .select("id, code, signed_on, notes, value, file_name, file_path, created_at, customer_id, deal_id, sales_person_id, customer:customers(id, name, company, phone, extra_phones, extra_phone_names, cs_pending), deal:deals(id, title, assigned_to, value), products:customer_products(name, quantity, sales_person_id)")
      .order("created_at", { ascending: false })
      .order("id")
      .range(from, to) as never,
  ),
);

// ---- The agent on a contract: the salesperson recorded on its products, else the agent of its deal
const { data: people } = await useAsyncData<Record<string, string>>("crm-contracts-people", async () => {
  const { data } = await supabase.from("profiles").select("id, full_name, email");
  return Object.fromEntries((data ?? []).map((p) => [p.id as string, (p.full_name || p.email) as string]));
});
// A contract is named after what the customer bought: its products (the deal's title, then the code, when it has none)
function titleOf(c: ContractRow): string {
  const names = (c.products ?? []).filter((p) => p.name?.trim()).map((p) => ((p.quantity ?? 1) > 1 ? `${p.name.trim()} × ${p.quantity}` : p.name.trim()));
  return names.join("، ") || c.deal?.title || c.code || "—";
}
function agentsOf(c: ContractRow): string[] {
  if (c.sales_person_id) return [people.value?.[c.sales_person_id] ?? ""].filter(Boolean);
  const ids = new Set((c.products ?? []).map((p) => p.sales_person_id).filter((x): x is string => !!x));
  if (!ids.size && c.deal?.assigned_to) ids.add(c.deal.assigned_to);
  return [...ids].map((id) => people.value?.[id] ?? "").filter(Boolean);
}

// ---- Search and order
const search = ref("");
// a period of contract dates, to know how many contracts were made in it (none: every contract)
const from = ref("");
const to = ref("");
const quickRanges = ["thisMonth", "lastMonth", "last30", "thisYear"] as const;
const activeRange = computed(() => quickRanges.find((k) => reportRange(k).from === from.value && reportRange(k).to === to.value) ?? null);
function setRange(kind: (typeof quickRanges)[number]) {
  const r = reportRange(kind);
  from.value = r.from;
  to.value = r.to;
}
const hasPeriod = computed(() => !!from.value || !!to.value);
function clearPeriod() {
  from.value = "";
  to.value = "";
}
type SortMode = "created" | "signed";
const sortMode = ref<SortMode>("signed");
const sortItems = computed(() => [
  { label: t("crm.contracts.sortSigned"), value: "signed" },
  { label: t("crm.contracts.sortCreated"), value: "created" },
]);
const time = (v: string | null) => (v ? new Date(v).getTime() : 0);
const rows = computed(() => {
  const q = search.value.trim().toLowerCase();
  const list = (contracts.value ?? []).filter((c) => {
    // inside the chosen period of contract dates (a contract with no date is outside any period)
    if (hasPeriod.value) {
      if (!c.signed_on) return false;
      if (from.value && c.signed_on < from.value) return false;
      if (to.value && c.signed_on > to.value) return false;
    }
    if (!q) return true;
    const cu = c.customer;
    return (
      (c.code ?? "").toLowerCase().includes(q) ||
      `${titleOf(c)} ${c.code ?? ""} ${cu?.name ?? ""} ${cu?.company ?? ""} ${c.deal?.title ?? ""} ${c.notes ?? ""} ${agentsOf(c).join(" ")}`.toLowerCase().includes(q) ||
      anyPhoneMatches([cu?.phone, ...(cu?.extra_phones ?? [])], search.value) ||
      extraNamesMatch(cu?.extra_phone_names, search.value)
    );
  });
  // newest first: by the contract date (those with no date last, then by when they were generated), or by when generated
  return [...list].sort((a, b) =>
    sortMode.value === "signed"
      ? time(b.signed_on) - time(a.signed_on) || time(b.created_at) - time(a.created_at)
      : time(b.created_at) - time(a.created_at),
  );
});

const pagination = reactive({ page: 1, size: 50 });
watch([search, sortMode, from, to], () => (pagination.page = 1));
const pageCount = computed(() => Math.max(1, Math.ceil(rows.value.length / pagination.size)));
const paged = computed(() => rows.value.slice((pagination.page - 1) * pagination.size, pagination.page * pagination.size));
// the value of a contract: its own (a contract made by hand), else the value of the deal it came from
const valueOf = (c: ContractRow) => (c.value != null ? Number(c.value) : c.deal?.value != null ? Number(c.deal.value) : null);
const money = (v: number) => formatReportMoney(v, t("common.currency"));
const totalValue = computed(() => rows.value.reduce((n, c) => n + (valueOf(c) ?? 0), 0));
// the contract file: a short-lived link that saves it under its own name
const toast = useToast();
// ---- delete a contract (its file goes too; the customer's products stay, only unlinked from it)
const deleteTarget = ref<ContractRow | null>(null);
const deleteOpen = computed({ get: () => !!deleteTarget.value, set: (v) => { if (!v) deleteTarget.value = null; } });
const deleting = ref(false);
async function confirmDelete() {
  const c = deleteTarget.value;
  if (!c) return;
  deleting.value = true;
  // the row first: if that is refused the file must stay
  const { data, error } = await supabase.from("contracts").delete().eq("id", c.id).select("id");
  if (error || !data?.length) {
    deleting.value = false;
    toast.add({ title: t("crm.contracts.deleteFailed"), description: error?.message ?? t("crm.contracts.deleteNotAllowed"), color: "error" });
    return;
  }
  if (c.file_path) await supabase.storage.from("contract-files").remove([c.file_path]);
  deleting.value = false;
  deleteTarget.value = null;
  toast.add({ title: t("crm.contracts.deleted"), color: "success" });
  await refresh();
}

async function downloadFile(c: ContractRow) {
  if (!c.file_path) return;
  const { data, error } = await supabase.storage.from("contract-files").createSignedUrl(c.file_path, 60, { download: c.file_name ?? true });
  if (error || !data) {
    toast.add({ title: t("crm.contracts.fileFailed"), description: error?.message, color: "error" });
    return;
  }
  const a = document.createElement("a");
  a.href = data.signedUrl;
  document.body.appendChild(a);
  a.click();
  a.remove();
}
const customerTitle = (c: ContractRow) => c.customer?.company || c.customer?.name || "—";
</script>

<template>
  <UDashboardPanel :ui="{ body: 'kords-canvas' }">
    <template #header>
      <KPageHeader :title="t('crm.contracts.title')" :count="contracts?.length ?? 0">
        <template #right>
          <UButton v-if="canCreate" icon="i-lucide-plus" :label="t('crm.contracts.new')" @click="createOpen = true" />
        </template>
      </KPageHeader>
      <div class="kords-filterbar flex flex-wrap items-center gap-2 border-b border-default px-4 py-3 sm:px-6">
        <UInput v-model="search" icon="i-lucide-search" :placeholder="t('crm.contracts.search')" class="min-w-0 flex-1 basis-60 lg:max-w-96 lg:flex-none" />
        <USelect v-model="sortMode" :items="sortItems" value-key="value" icon="i-lucide-arrow-down-wide-narrow" class="w-48" />
      </div>
      <!-- Contract dates: how many contracts were made in a period -->
      <div class="kords-filterbar flex flex-wrap items-end gap-3 border-b border-default px-4 py-3 sm:px-6">
        <div class="flex flex-wrap items-center gap-2">
          <button v-for="k in quickRanges" :key="k" type="button" class="kords-chip" :class="activeRange === k && 'kords-chip-on'" @click="setRange(k)">{{ t(`reports.${k}`) }}</button>
        </div>
        <UFormField :label="t('crm.contracts.dateFrom')"><UInput v-model="from" type="date" class="w-40" /></UFormField>
        <UFormField :label="t('crm.contracts.dateTo')"><UInput v-model="to" type="date" class="w-40" /></UFormField>
        <UButton v-if="hasPeriod" icon="i-lucide-x" color="neutral" variant="ghost" size="sm" :label="t('crm.contracts.clearPeriod')" @click="clearPeriod" />
        <KBadge v-if="hasPeriod" :label="t('crm.contracts.inPeriod', { count: rows.length })" tone="primary" class="ms-auto" />
        <KBadge v-if="totalValue > 0" :label="`${t('crm.contracts.totalValue')}: ${money(totalValue)}`" tone="success" :class="!hasPeriod && 'ms-auto'" />
      </div>
    </template>

    <template #body>
      <div v-if="status === 'pending'" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>
      <p v-else-if="!rows.length" class="kords-card p-10 text-center text-sm text-muted">{{ t("crm.contracts.empty") }}</p>
      <template v-else>
        <!-- Phone: cards -->
        <div class="space-y-2 md:hidden">
          <NuxtLink v-for="c in paged" :key="c.id" :to="`/crm/contracts/${c.id}`" class="kords-kcard block border border-default bg-default p-3">
            <div class="flex items-start justify-between gap-2">
              <span class="min-w-0 font-semibold text-highlighted">{{ titleOf(c) }}</span>
              <span class="flex shrink-0 items-center gap-1 text-xs text-muted">{{ formatDMY(c.created_at) }}<UButton v-if="canDelete" icon="i-lucide-trash" color="error" variant="ghost" size="xs" :aria-label="t('crm.contracts.delete')" @click.prevent.stop="deleteTarget = c" /></span>
            </div>
            <p class="mt-1 truncate text-sm text-toned">{{ customerTitle(c) }}<template v-if="c.code"> · <bdi dir="ltr">#{{ c.code }}</bdi></template></p>
            <p v-if="agentsOf(c).length" class="mt-0.5 flex items-center gap-1 text-xs text-muted"><UIcon name="i-lucide-user" class="size-3" />{{ agentsOf(c).join("، ") }}</p>
            <p v-if="valueOf(c) !== null" class="mt-0.5 text-sm font-medium text-success">{{ money(valueOf(c)!) }}</p>
            <p v-if="c.signed_on" class="mt-0.5 text-xs text-muted">{{ t("crm.contracts.signedOn") }}: {{ formatDMY(c.signed_on) }}</p>
          </NuxtLink>
        </div>

        <!-- Desktop: table -->
        <div class="kords-card hidden overflow-x-auto md:block">
          <table class="w-full min-w-[44rem] text-sm">
            <thead>
              <tr class="border-b border-default text-xs text-muted">
                <th class="px-4 py-3 text-start font-medium">{{ t("crm.contracts.code") }}</th>
                <th class="px-4 py-3 text-start font-medium">{{ t("crm.contracts.customer") }}</th>
                <th class="px-4 py-3 text-start font-medium">{{ t("crm.contracts.agent") }}</th>
                <th class="px-4 py-3 text-start font-medium">{{ t("crm.contracts.deal") }}</th>
                <th class="px-4 py-3 text-end font-medium">{{ t("crm.contracts.value") }}</th>
                <th class="px-4 py-3 text-start font-medium">{{ t("crm.contracts.signedOn") }}</th>
                <th class="px-4 py-3 text-start font-medium">{{ t("crm.contracts.generatedOn") }}</th>
                <th class="w-12 px-2 py-3"><span class="sr-only">{{ t("crm.contracts.file") }}</span></th>
                <th v-if="canDelete" class="w-12 px-2 py-3"><span class="sr-only">{{ t("common.delete") }}</span></th>
              </tr>
            </thead>
            <tbody class="divide-y divide-default">
              <tr v-for="c in paged" :key="c.id" class="cursor-pointer hover:bg-elevated" @click="navigateTo(`/crm/contracts/${c.id}`)">
                <td class="max-w-72 px-4 py-3">
                  <NuxtLink :to="`/crm/contracts/${c.id}`" class="block font-medium text-highlighted hover:text-primary">{{ titleOf(c) }}</NuxtLink>
                  <span v-if="c.code" class="text-xs text-muted"><bdi dir="ltr">#{{ c.code }}</bdi></span>
                </td>
                <td class="px-4 py-3">
                  <span class="font-medium text-highlighted">{{ customerTitle(c) }}</span>
                  <UBadge v-if="c.customer?.cs_pending" :label="t('crm.contracts.csPendingShort')" color="warning" variant="subtle" size="sm" class="ms-2 cds-tag" />
                  <div v-if="c.customer?.phone" class="text-xs text-muted" dir="ltr">{{ c.customer.phone }}</div>
                </td>
                <td class="px-4 py-3">{{ agentsOf(c).join("، ") || "—" }}</td>
                <td class="px-4 py-3">
                  <NuxtLink v-if="c.deal" :to="`/crm/deals/${c.deal.id}`" class="text-primary hover:underline" @click.stop>{{ c.deal.title }}</NuxtLink>
                  <span v-else class="text-muted">—</span>
                </td>
                <td class="whitespace-nowrap px-4 py-3 text-end font-medium">{{ valueOf(c) !== null ? money(valueOf(c)!) : "—" }}</td>
                <td class="whitespace-nowrap px-4 py-3">{{ c.signed_on ? formatDMY(c.signed_on) : "—" }}</td>
                <td class="whitespace-nowrap px-4 py-3 text-muted">{{ formatDMYTime(c.created_at) }}</td>
                <td class="px-2 py-2 text-end"><UButton v-if="c.file_path" icon="i-lucide-download" color="neutral" variant="ghost" size="sm" :title="c.file_name ?? t('crm.contracts.file')" :aria-label="t('crm.contracts.file')" @click.stop="downloadFile(c)" /></td>
                <td v-if="canDelete" class="px-2 py-2 text-end"><UButton icon="i-lucide-trash" color="error" variant="ghost" size="sm" :title="t('crm.contracts.delete')" :aria-label="t('crm.contracts.delete')" @click.stop="deleteTarget = c" /></td>
              </tr>
            </tbody>
          </table>
        </div>

        <div v-if="pageCount > 1" class="flex items-center justify-between gap-2 pt-3">
          <span class="text-sm text-muted">{{ t("crm.contracts.count", { count: rows.length }) }}</span>
          <div class="flex items-center gap-2">
            <UButton icon="i-lucide-chevron-right" color="neutral" variant="outline" size="sm" :disabled="pagination.page === 1" class="rtl:rotate-0 ltr:rotate-180" @click="pagination.page--" />
            <span class="text-sm">{{ pagination.page }} / {{ pageCount }}</span>
            <UButton icon="i-lucide-chevron-left" color="neutral" variant="outline" size="sm" :disabled="pagination.page === pageCount" class="rtl:rotate-0 ltr:rotate-180" @click="pagination.page++" />
          </div>
        </div>
      </template>
    </template>
  </UDashboardPanel>

  <KDeleteConfirmation v-model:open="deleteOpen" :title="t('crm.contracts.delete')" :message="t('crm.contracts.deleteBody', { name: deleteTarget ? titleOf(deleteTarget) : '' })" :loading="deleting" @confirm="confirmDelete" />

  <CrmContractModal v-model:open="createOpen" :taken-deal-ids="(contracts ?? []).map((c) => c.deal_id).filter((x): x is string => !!x)" @saved="refresh" />
</template>
