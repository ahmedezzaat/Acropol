<script setup lang="ts">
import type { TableColumn } from "@nuxt/ui";
import { getPaginationRowModel } from "@tanstack/vue-table";

definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "cs_customers" },
});

useHead({ htmlAttrs: { class: "carbon" } });

const supabase = useSupabaseClient();
const { t } = useI18n();
const { hasPermission } = usePermissions();
const canViewAll = computed(() => hasPermission("cs_customers", "view_all"));
const { areas, stages, pipelines, stageColor, stageName, stageLabelFull, loadAreas, loadPipelines, areaName, formatDate } = useCs();

// Customer service sees every customer: the ones a won deal created in the CRM
// and the ones added here directly.
const { data: customers, refresh, status } = await useAsyncData<CsCustomer[]>("cs-customers", async () =>
  fetchAll<CsCustomer>((from, to) =>
    supabase
      .from("customers")
      .select("id, name, company, phone, extra_phones, extra_phone_names, email, address, area_id, created_at, customer_type, cs_agent_id")
      .order("created_at", { ascending: false })
      .order("id")
      .range(from, to) as never,
  ),
);

const { data: products, refresh: refreshProducts } = await useAsyncData<Pick<CsProduct, "customer_id" | "stage_id" | "category_id">[]>(
  "cs-customers-products",
  async () =>
    fetchAll<Pick<CsProduct, "customer_id" | "stage_id" | "category_id">>((from, to) =>
      supabase.from("customer_products").select("customer_id, stage_id, category_id").order("id").range(from, to) as never,
    ),
);
// Contract codes of every customer (shown in the list, and searchable).
const { data: contractRows, refresh: refreshContracts } = await useAsyncData<{ customer_id: string; code: string | null }[]>("cs-customers-contracts", async () =>
  fetchAll<{ customer_id: string; code: string | null }>((from, to) =>
    supabase.from("contracts").select("customer_id, code").order("signed_on", { ascending: false, nullsFirst: false }).order("id").range(from, to) as never,
  ),
);
const contractsByCustomer = computed(() => {
  const map = new Map<string, string[]>();
  for (const c of contractRows.value ?? []) {
    const code = c.code?.trim();
    if (code) map.set(c.customer_id, [...(map.get(c.customer_id) ?? []), code]);
  }
  return map;
});
const contractsOf = (customerId: string) => contractsByCustomer.value.get(customerId) ?? [];

const { data: categories } = await useAsyncData<{ id: string; name: string }[]>("cs-customers-categories", async () => {
  const { data, error } = await supabase.from("product_categories").select("id, name").order("sort_order");
  if (error) throw error;
  return data ?? [];
});
await useAsyncData("cs-customers-areas", async () => {
  await Promise.all([loadAreas(true), loadPipelines(true)]);
  return true;
});

// The Customer Service agents (for the filter, which only people who see every
// customer need).
const { data: people } = await useAsyncData<{ id: string; full_name: string | null; email: string }[]>("cs-customers-people", async () => {
  const { data } = await supabase.from("profiles").select("id, full_name, email");
  return data ?? [];
});
const agentFilter = ref<string | null>(null); // null = everyone, "none" = no agent
const agentItems = computed(() => [
  { label: t("cs.customers.allAgents"), value: null as string | null },
  { label: t("cs.customers.noAgent"), value: "none" as string | null },
  ...(people.value ?? []).map((u) => ({ label: u.full_name || u.email, value: u.id as string | null })),
]);

const search = ref("");
const areaFilter = ref<string | null>(null);
const stageFilter = ref<string | null>(null);
// Filter by the product category (heaters, boilers, …) of a customer's products.
const categoryFilter = ref<string | null>(null);
// Quick switch above the list: everyone, individuals, or companies.
const typeFilter = ref<"all" | "individual" | "company">("all");

const areaItems = computed(() => [
  { label: t("cs.customers.allAreas"), value: null },
  ...areas.value.map((a) => ({ label: a.name, value: a.id })),
]);
const categoryItems = computed(() => [
  { label: t("cs.customers.allCategories"), value: null },
  ...(categories.value ?? []).map((c) => ({ label: c.name, value: c.id })),
]);
function categoriesOf(customerId: string) {
  const ids = (products.value ?? []).filter((p) => p.customer_id === customerId).map((p) => p.category_id);
  return [...new Set(ids.filter((id): id is string => !!id))]
    .map((id) => categories.value?.find((c) => c.id === id)?.name)
    .filter((n): n is string => !!n);
}

// Every stage of every pipeline, in funnel order.
const orderedStages = computed(() =>
  [...stages.value].sort((a, b) => {
    const pa = pipelines.value.find((p) => p.id === a.pipeline_id)?.sort_order ?? 0;
    const pb = pipelines.value.find((p) => p.id === b.pipeline_id)?.sort_order ?? 0;
    return pa - pb || a.sort_order - b.sort_order;
  }),
);
const stageItems = computed(() => [
  { label: t("cs.customers.allStages"), value: null },
  ...orderedStages.value.map((s) => ({ label: stageLabelFull(s.id), value: s.id })),
]);

function stagesOf(customerId: string) {
  return (products.value ?? []).filter((p) => p.customer_id === customerId).map((p) => p.stage_id);
}

const typeCounts = computed(() => {
  const all = customers.value ?? [];
  const companies = all.filter((c) => isCompanyCustomer(c)).length;
  return { all: all.length, company: companies, individual: all.length - companies };
});
const typeTabs = computed(() =>
  (["all", "individual", "company"] as const).map((k) => ({
    value: k,
    label: `${k === "all" ? t("common.all") : t(`crm.leads.type.${k}`)} (${typeCounts.value[k]})`,
  })),
);

// Order of the list: by when the customer was added (newest first by default).
type SortMode = "newest" | "oldest" | "name";
const sortMode = ref<SortMode>("newest");
const sortItems = computed(() => [
  { label: t("cs.customers.sortNewest"), value: "newest" },
  { label: t("cs.customers.sortOldest"), value: "oldest" },
  { label: t("cs.customers.sortName"), value: "name" },
]);
const sortedCustomers = computed(() => {
  const list = [...(customers.value ?? [])];
  const time = (c: CsCustomer) => new Date(c.created_at ?? 0).getTime();
  if (sortMode.value === "name") return list.sort((a, b) => customerTitle(a).localeCompare(customerTitle(b), "ar"));
  return list.sort((a, b) => (sortMode.value === "oldest" ? time(a) - time(b) : time(b) - time(a)));
});

const filtered = computed(() =>
  sortedCustomers.value.filter((c) => {
    if (typeFilter.value !== "all" && (isCompanyCustomer(c) ? "company" : "individual") !== typeFilter.value) return false;
    if (areaFilter.value && c.area_id !== areaFilter.value) return false;
    if (agentFilter.value && (agentFilter.value === "none" ? !!c.cs_agent_id : c.cs_agent_id !== agentFilter.value)) return false;
    if (stageFilter.value && !stagesOf(c.id).includes(stageFilter.value)) return false;
    if (categoryFilter.value) {
      const has = (products.value ?? []).some((p) => p.customer_id === c.id && p.category_id === categoryFilter.value);
      if (!has) return false;
    }
    if (search.value) {
      const q = search.value.toLowerCase();
      const hay = `${c.name} ${c.company ?? ""} ${c.email ?? ""} ${c.address ?? ""} ${contractsOf(c.id).join(" ")}`.toLowerCase();
      if (!hay.includes(q) && !phoneMatches(c.phone, search.value) && !(c.extra_phones ?? []).some((p) => phoneMatches(p, search.value))) return false;
    }
    return true;
  }),
);

// One badge per distinct stage among a customer's products, most advanced last.
function stageBadges(customerId: string) {
  const order = new Map(orderedStages.value.map((s, i) => [s.id, i]));
  return [...new Set(stagesOf(customerId))].sort((a, b) => (order.get(a) ?? 0) - (order.get(b) ?? 0));
}

function ago(value: string | undefined) {
  if (!value) return "";
  const rtf = new Intl.RelativeTimeFormat(undefined, { numeric: "auto" });
  const days = Math.round((new Date(value).getTime() - Date.now()) / 86_400_000);
  if (Math.abs(days) >= 365) return rtf.format(Math.round(days / 365), "year");
  if (Math.abs(days) >= 30) return rtf.format(Math.round(days / 30), "month");
  if (Math.abs(days) >= 1) return rtf.format(days, "day");
  return rtf.format(0, "day");
}

// ---- The list. A customer opens on its own page (/cs/customers/:id).
function openCustomer(id: string) {
  navigateTo(`/cs/customers/${id}`);
}
function productCount(customerId: string) {
  return stagesOf(customerId).length;
}
// The latest (most advanced) stage among a customer's products.
function latestStage(customerId: string) {
  const list = stageBadges(customerId);
  return list[list.length - 1];
}
const agentName = (id: string | null) => {
  const u = id ? people.value?.find((x) => x.id === id) : null;
  return u ? u.full_name || u.email : null;
};

// ---- Merge: tick two or more customers (people allowed to edit and delete them).
const UCheckbox = resolveComponent("UCheckbox");
const canDelete = computed(() => hasPermission("cs_customers", "delete"));
const canMerge = computed(() => canDelete.value && hasPermission("cs_customers", "edit"));
const rowSelection = ref<Record<string, boolean>>({});
const selectedCustomers = computed(() => filtered.value.filter((c) => rowSelection.value[c.id]));
const productCounts = computed(() => {
  const counts: Record<string, number> = {};
  for (const p of products.value ?? []) counts[p.customer_id] = (counts[p.customer_id] ?? 0) + 1;
  return counts;
});
const deleteOpen = ref(false);
function openBulkDelete() {
  deleteOpen.value = true;
}
const mergeOpen = ref(false);
function openMerge() {
  mergeOpen.value = true;
}
function clearSelection() {
  rowSelection.value = {};
}
async function onMerged() {
  clearSelection();
  await Promise.all([refresh(), refreshProducts(), refreshContracts()]);
}

const columns = computed<TableColumn<CsCustomer>[]>(() => [
  ...(canDelete.value
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
  { id: "contracts", header: t("cs.profile.contracts") },
  { id: "customer", header: t("cs.installations.customer") },
  { id: "contact", header: t("cs.customers.contact") },
  { id: "area", header: t("cs.customers.area") },
  { id: "products", header: t("cs.profile.products") },
  { id: "stage", header: t("cs.installations.stage") },
  ...(canViewAll.value ? [{ id: "agent", header: t("cs.customers.agent") }] : []),
  { id: "actions", header: "" },
]);

const pagination = ref({ pageIndex: 0, pageSize: 50 });
watch([search, areaFilter, stageFilter, categoryFilter, agentFilter, typeFilter, sortMode], () => {
  rowSelection.value = {};
  pagination.value = { ...pagination.value, pageIndex: 0 };
});
const pagedCards = computed(() =>
  filtered.value.slice(pagination.value.pageIndex * pagination.value.pageSize, (pagination.value.pageIndex + 1) * pagination.value.pageSize),
);

const activeFilterCount = computed(
  () => [areaFilter.value, stageFilter.value, categoryFilter.value, agentFilter.value, search.value].filter(Boolean).length,
);
function clearFilters() {
  search.value = "";
  areaFilter.value = null;
  stageFilter.value = null;
  categoryFilter.value = null;
  agentFilter.value = null;
}

const createOpen = ref(false);
function openCreate() {
  createOpen.value = true;
}
async function onCreated(id: string) {
  await Promise.all([refresh(), refreshProducts(), refreshContracts()]);
  openCustomer(id);
}
</script>

<template>
  <UDashboardPanel :ui="{ body: 'kords-canvas' }">
    <template #header>
      <KPageHeader :title="t('cs.customers.title')" :count="customers?.length ?? 0">
        <template #right>
          <UButton v-if="hasPermission('cs_customers', 'create')" icon="i-lucide-plus" :label="t('cs.customers.new')" @click="openCreate" />
        </template>
      </KPageHeader>

      <!-- Search, type tabs and filters in one bar -->
      <div class="kords-filterbar w-full space-y-3 border-b border-default px-4 py-3 sm:px-6">
        <div class="-mx-4 overflow-x-auto overflow-y-hidden px-4 [scrollbar-width:none] sm:mx-0 sm:px-0 [&::-webkit-scrollbar]:hidden">
          <UTabs v-model="typeFilter" :items="typeTabs" value-key="value" variant="link" size="sm" :content="false" class="kords-pilltabs w-max min-w-full" />
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <UInput v-model="search" icon="i-lucide-search" :placeholder="t('cs.customers.search')" class="min-w-0 flex-1 basis-60 lg:max-w-80 lg:flex-none" />
          <USelect v-model="areaFilter" :items="areaItems" value-key="value" icon="i-lucide-map-pin" class="w-40" />
          <USelect v-model="stageFilter" :items="stageItems" value-key="value" icon="i-lucide-workflow" class="w-44" />
          <USelect v-model="categoryFilter" :items="categoryItems" value-key="value" icon="i-lucide-tags" class="w-40" />
          <USelect v-if="canViewAll" v-model="agentFilter" :items="agentItems" value-key="value" icon="i-lucide-user-round" class="w-40" />
          <USelect v-model="sortMode" :items="sortItems" value-key="value" icon="i-lucide-arrow-down-wide-narrow" class="w-44" />
          <UButton
            v-if="activeFilterCount"
            icon="i-lucide-x"
            color="neutral"
            variant="ghost"
            size="sm"
            :label="t('crm.deals.clearFilters')"
            @click="clearFilters"
          />
        </div>
      </div>
    </template>

    <template #body>
      <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>
      <div v-else-if="!filtered.length" class="kords-card flex flex-col items-center gap-2 p-12 text-center text-muted">
        <UIcon name="i-lucide-user-round-search" class="size-9" />
        <p class="text-sm">{{ t("cs.customers.empty") }}</p>
        <UButton v-if="activeFilterCount" color="neutral" variant="outline" size="sm" :label="t('crm.deals.clearFilters')" @click="clearFilters" />
      </div>

      <template v-else>
        <!-- Phone: cards -->
        <div class="space-y-2 md:hidden">
          <button
            v-for="c in pagedCards"
            :key="c.id"
            type="button"
            class="kords-kcard flex w-full items-center gap-3 border border-default bg-default p-3 text-start"
            @click="openCustomer(c.id)"
          >
            <KAvatar :name="isCompanyCustomer(c) ? null : customerTitle(c)" kind="contact" :icon="isCompanyCustomer(c) ? 'i-lucide-building-2' : undefined" size="lg" />
            <span class="min-w-0 flex-1">
              <span class="block truncate font-semibold text-highlighted">{{ customerTitle(c) }}</span>
              <span v-if="customerSubtitle(c)" class="block truncate text-xs text-toned">{{ customerSubtitle(c) }}</span>
              <span class="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-muted">
                <bdi v-if="c.phone" dir="ltr">{{ c.phone }}</bdi>
                <span v-if="areaName(c.area_id)" class="flex items-center gap-1"><UIcon name="i-lucide-map-pin" class="size-3" />{{ areaName(c.area_id) }}</span>
                <span v-if="productCount(c.id)">{{ t("cs.customers.productsCount", { count: productCount(c.id) }) }}</span>
              </span>
            </span>
            <KBadge v-if="latestStage(c.id)" :label="stageName(latestStage(c.id)!)" :tone="stageColor(latestStage(c.id)!)" class="shrink-0" />
          </button>
        </div>

        <!-- Desktop: table -->
        <div v-if="canDelete && selectedCustomers.length" class="hidden items-center gap-3 md:flex">
          <span class="text-sm text-muted">{{ t("cs.customers.mergeSelected", { count: selectedCustomers.length }) }}</span>
          <UButton v-if="canMerge" icon="i-lucide-git-merge" size="sm" :label="t('cs.customers.merge')" :disabled="selectedCustomers.length < 2" @click="openMerge" />
          <UButton icon="i-lucide-trash" size="sm" color="error" variant="soft" :label="t('common.delete')" @click="openBulkDelete" />
          <UButton icon="i-lucide-x" size="sm" color="neutral" variant="ghost" :label="t('cs.customers.clearSelection')" @click="clearSelection" />
        </div>
        <UTable
          v-model:row-selection="rowSelection"
          :get-row-id="(row: CsCustomer) => row.id"
          v-model:pagination="pagination"
          :data="filtered"
          :columns="columns"
          :pagination-options="{ getPaginationRowModel: getPaginationRowModel() }"
          :ui="{ root: 'kords-card hidden shrink-0 overflow-hidden md:block [&_tbody_tr]:cursor-pointer' }"
          @select="(_e, row) => openCustomer(row.original.id)"
        >
          <template #contracts-cell="{ row }">
            <div v-if="contractsOf(row.original.id).length" class="flex max-w-56 flex-wrap items-center gap-1">
              <KBadge v-for="code in contractsOf(row.original.id).slice(0, 3)" :key="code" :label="code" tone="primary" class="font-mono" />
              <span v-if="contractsOf(row.original.id).length > 3" class="text-xs text-muted" :title="contractsOf(row.original.id).join(' ، ')">
                +{{ contractsOf(row.original.id).length - 3 }}
              </span>
            </div>
            <span v-else class="text-sm text-muted">—</span>
          </template>
          <template #customer-cell="{ row }">
            <div class="flex min-w-0 items-center gap-3">
              <KAvatar
                :name="isCompanyCustomer(row.original) ? null : customerTitle(row.original)"
                kind="contact"
                :icon="isCompanyCustomer(row.original) ? 'i-lucide-building-2' : undefined"
                size="md"
              />
              <div class="min-w-0">
                <div class="truncate font-medium text-highlighted">{{ customerTitle(row.original) }}</div>
                <div v-if="customerSubtitle(row.original)" class="truncate text-xs text-toned">{{ customerSubtitle(row.original) }}</div>
              </div>
            </div>
          </template>
          <template #contact-cell="{ row }">
            <div class="text-sm">
              <bdi v-if="row.original.phone" dir="ltr" class="text-highlighted">{{ row.original.phone }}</bdi>
              <span v-else class="text-muted">—</span>
              <div v-if="row.original.extra_phones?.length" class="text-xs text-muted">
                +{{ row.original.extra_phones.length }}<template v-if="row.original.extra_phone_names?.some((n) => n)"> · {{ row.original.extra_phone_names.filter((n) => n).join("، ") }}</template>
              </div>
            </div>
          </template>
          <template #area-cell="{ row }">
            <span class="text-sm">{{ areaName(row.original.area_id) || "—" }}</span>
          </template>
          <template #products-cell="{ row }">
            <div v-if="productCount(row.original.id)" class="flex flex-wrap items-center gap-1">
              <KBadge :label="String(productCount(row.original.id))" tone="primary" />
              <KBadge v-for="n in categoriesOf(row.original.id).slice(0, 2)" :key="n" :label="n" tone="neutral" outlined />
              <span v-if="categoriesOf(row.original.id).length > 2" class="text-xs text-muted">+{{ categoriesOf(row.original.id).length - 2 }}</span>
            </div>
            <span v-else class="text-sm text-muted">—</span>
          </template>
          <template #stage-cell="{ row }">
            <KBadge v-if="latestStage(row.original.id)" :label="stageName(latestStage(row.original.id)!)" :tone="stageColor(latestStage(row.original.id)!)" />
            <span v-else class="text-sm text-muted">—</span>
          </template>
          <template #agent-cell="{ row }">
            <div v-if="agentName(row.original.cs_agent_id ?? null)" class="flex items-center gap-1.5 text-sm">
              <KAvatar :name="agentName(row.original.cs_agent_id ?? null)" kind="user" size="2xs" />
              <span class="truncate">{{ agentName(row.original.cs_agent_id ?? null) }}</span>
            </div>
            <span v-else class="text-sm text-muted">—</span>
          </template>
          <template #actions-cell="{ row }">
            <a
              v-if="toWhatsAppLink(row.original.phone)"
              :href="toWhatsAppLink(row.original.phone)!"
              target="_blank"
              rel="noopener noreferrer"
              :aria-label="t('crm.deals.chatOnWhatsApp')"
              class="inline-flex size-8 items-center justify-center text-[#25D366] hover:opacity-80"
              @click.stop
            >
              <UIcon name="i-simple-icons-whatsapp" class="size-5" />
            </a>
          </template>
        </UTable>

        <div class="mt-3 flex flex-wrap items-center justify-between gap-2">
          <span class="text-sm text-muted">{{ t("cs.customers.total", { count: filtered.length }) }}</span>
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

  <CustomerFormModal v-model:open="createOpen" @saved="onCreated" />
  <CustomerBulkDeleteModal v-model:open="deleteOpen" :customers="selectedCustomers" :product-counts="productCounts" @deleted="onMerged" />
  <CustomerMergeModal v-model:open="mergeOpen" :customers="selectedCustomers" :product-counts="productCounts" @merged="onMerged" />
</template>
