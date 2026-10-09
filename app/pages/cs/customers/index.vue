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
const { areas, stages, pipelines, stageColor, stageName, stageLabelFull, formatDate, loadAreas, loadPipelines, areaName } = useCs();

// Customer service sees every customer: the ones a won deal created in the CRM
// and the ones added here directly.
const { data: customers, refresh, status } = await useAsyncData<CsCustomer[]>("cs-customers", async () => {
  const { data, error } = await supabase
    .from("customers")
    .select("id, name, company, phone, email, address, area_id, created_at, customer_type")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as CsCustomer[];
});

const { data: products } = await useAsyncData<Pick<CsProduct, "customer_id" | "stage_id" | "category_id">[]>(
  "cs-customers-products",
  async () => {
    const { data, error } = await supabase.from("customer_products").select("customer_id, stage_id, category_id");
    if (error) throw error;
    return (data ?? []) as Pick<CsProduct, "customer_id" | "stage_id" | "category_id">[];
  },
);
const { data: categories } = await useAsyncData<{ id: string; name: string }[]>("cs-customers-categories", async () => {
  const { data, error } = await supabase.from("product_categories").select("id, name").order("sort_order");
  if (error) throw error;
  return data ?? [];
});
await useAsyncData("cs-customers-areas", async () => {
  await Promise.all([loadAreas(true), loadPipelines(true)]);
  return true;
});

const search = ref("");
const areaFilter = ref<string | null>(null);
const stageFilter = ref<string | null>(null);
// Filter by the product category (heaters, boilers, …) of a customer's products.
const categoryFilter = ref<string | null>(null);
// Quick switch above the list: everyone, individuals, or companies.
const typeFilter = ref<"all" | "individual" | "company">("all");

// List (a table) or cards; remembered per browser. Phones always get cards —
// a many-column table doesn't fit.
const viewMode = ref<"list" | "cards">("list");
onMounted(() => {
  try {
    const saved = localStorage.getItem("cs-customers-view");
    if (saved === "list" || saved === "cards") viewMode.value = saved;
  } catch {
    /* storage unavailable — keep the default */
  }
});
function setView(mode: "list" | "cards") {
  viewMode.value = mode;
  try {
    localStorage.setItem("cs-customers-view", mode);
  } catch {
    /* ignore */
  }
}

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

const filtered = computed(() =>
  (customers.value ?? []).filter((c) => {
    if (typeFilter.value !== "all" && (isCompanyCustomer(c) ? "company" : "individual") !== typeFilter.value) return false;
    if (areaFilter.value && c.area_id !== areaFilter.value) return false;
    if (stageFilter.value && !stagesOf(c.id).includes(stageFilter.value)) return false;
    if (categoryFilter.value) {
      const has = (products.value ?? []).some((p) => p.customer_id === c.id && p.category_id === categoryFilter.value);
      if (!has) return false;
    }
    if (search.value) {
      const q = search.value.toLowerCase();
      const hay = `${c.name} ${c.company ?? ""} ${c.email ?? ""} ${c.address ?? ""}`.toLowerCase();
      if (!hay.includes(q) && !phoneMatches(c.phone, search.value)) return false;
    }
    return true;
  }),
);

// One badge per distinct stage among a customer's products, most advanced last.
function stageBadges(customerId: string) {
  const order = new Map(orderedStages.value.map((s, i) => [s.id, i]));
  return [...new Set(stagesOf(customerId))].sort((a, b) => (order.get(a) ?? 0) - (order.get(b) ?? 0));
}

// ---- List view
const columns = computed<TableColumn<CsCustomer>[]>(() => [
  { id: "created", header: t("cs.customers.created") },
  { id: "name", header: t("common.name") },
  { id: "contact", header: t("cs.customers.contact") },
  { id: "area", header: t("cs.customers.area") },
  { id: "address", header: t("cs.customers.address") },
  { id: "categories", header: t("cs.customers.categories") },
  { id: "stages", header: t("cs.customers.progress") },
]);
const pagination = ref({ pageIndex: 0, pageSize: 25 });
watch([search, areaFilter, stageFilter, categoryFilter, typeFilter], () => {
  pagination.value.pageIndex = 0;
});
// The cards (phones, and the card view) share the table's paging.
const pagedCards = computed(() =>
  filtered.value.slice(pagination.value.pageIndex * pagination.value.pageSize, (pagination.value.pageIndex + 1) * pagination.value.pageSize),
);

const createOpen = ref(false);
function openCreate() {
  createOpen.value = true;
}
async function onCreated(id: string) {
  await refresh();
  await navigateTo(`/cs/customers/${id}`);
}
function openCustomer(id: string) {
  navigateTo(`/cs/customers/${id}`);
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
            {{ t("cs.customers.title") }}
            <UBadge :label="String(customers?.length ?? 0)" color="neutral" variant="subtle" class="cds-tag" />
          </span>
        </template>
        <template #right>
          <UButton
            v-if="hasPermission('cs_customers', 'create')"
            icon="i-lucide-plus"
            :label="t('cs.customers.new')"
            @click="openCreate"
          />
        </template>
      </UDashboardNavbar>

      <div class="w-full space-y-3 border-b border-default px-4 py-3 sm:px-6">
        <UTabs v-model="typeFilter" :items="typeTabs" value-key="value" variant="pill" size="sm" :content="false" />
        <div class="flex flex-wrap items-center gap-2">
          <UInput
            v-model="search"
            icon="i-lucide-search"
            :placeholder="t('cs.customers.search')"
            class="min-w-0 flex-1 basis-56"
          />
          <USelect v-model="areaFilter" :items="areaItems" value-key="value" icon="i-lucide-map-pin" class="w-44" />
          <USelect v-model="stageFilter" :items="stageItems" value-key="value" icon="i-lucide-workflow" class="w-44" />
          <USelect v-model="categoryFilter" :items="categoryItems" value-key="value" icon="i-lucide-tags" class="w-44" />
          <UButtonGroup class="ms-auto hidden md:inline-flex">
            <UButton
              icon="i-lucide-list"
              :color="viewMode === 'list' ? 'primary' : 'neutral'"
              :variant="viewMode === 'list' ? 'solid' : 'outline'"
              :aria-label="t('cs.customers.listView')"
              @click="setView('list')"
            />
            <UButton
              icon="i-lucide-layout-grid"
              :color="viewMode === 'cards' ? 'primary' : 'neutral'"
              :variant="viewMode === 'cards' ? 'solid' : 'outline'"
              :aria-label="t('cs.customers.cardView')"
              @click="setView('cards')"
            />
          </UButtonGroup>
        </div>
      </div>
    </template>

    <template #body>
      <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>
      <p v-else-if="!filtered.length" class="py-16 text-center text-sm text-muted">{{ t("cs.customers.empty") }}</p>

      <template v-else>
      <UTable
        v-if="viewMode === 'list'"
        v-model:pagination="pagination"
        :data="filtered"
        :columns="columns"
        :pagination-options="{ getPaginationRowModel: getPaginationRowModel() }"
        :ui="{ root: 'hidden md:block [&_tbody_tr]:cursor-pointer' }"
        @select="(_e, row) => openCustomer(row.original.id)"
      >
        <template #name-cell="{ row }">
          <div class="flex items-center gap-2.5">
            <UAvatar
              :text="isCompanyCustomer(row.original) ? undefined : customerTitle(row.original).trim().charAt(0).toUpperCase()"
              :icon="isCompanyCustomer(row.original) ? 'i-lucide-building-2' : undefined"
              size="sm"
            />
            <div class="min-w-0">
              <div class="truncate font-medium text-highlighted">{{ customerTitle(row.original) }}</div>
              <div v-if="customerSubtitle(row.original)" class="truncate text-xs text-toned">{{ customerSubtitle(row.original) }}</div>
            </div>
          </div>
        </template>
        <template #contact-cell="{ row }">
          <div class="flex items-center gap-1.5">
            <bdi v-if="row.original.phone" dir="ltr" class="text-sm">{{ row.original.phone }}</bdi>
            <span v-else class="text-muted">—</span>
            <a
              v-if="toWhatsAppLink(row.original.phone)"
              :href="toWhatsAppLink(row.original.phone)!"
              target="_blank"
              rel="noopener noreferrer"
              :aria-label="t('crm.deals.chatOnWhatsApp')"
              class="text-[#25D366] hover:opacity-80"
              @click.stop
            >
              <UIcon name="i-simple-icons-whatsapp" class="size-4" />
            </a>
          </div>
        </template>
        <template #area-cell="{ row }">
          <span class="text-sm">{{ areaName(row.original.area_id) || "—" }}</span>
        </template>
        <template #address-cell="{ row }">
          <span class="line-clamp-2 max-w-64 text-sm text-muted">{{ row.original.address || "—" }}</span>
        </template>
        <template #categories-cell="{ row }">
          <div v-if="categoriesOf(row.original.id).length" class="flex max-w-56 flex-wrap gap-1">
            <UBadge
              v-for="name in categoriesOf(row.original.id).slice(0, 3)"
              :key="name"
              :label="name"
              color="neutral"
              variant="subtle"
              size="sm"
              class="cds-tag"
            />
            <span v-if="categoriesOf(row.original.id).length > 3" class="text-xs text-muted">+{{ categoriesOf(row.original.id).length - 3 }}</span>
          </div>
          <span v-else class="text-muted">—</span>
        </template>
        <template #stages-cell="{ row }">
          <div v-if="stagesOf(row.original.id).length" class="flex flex-wrap items-center gap-1">
            <UBadge
              v-for="s in stageBadges(row.original.id)"
              :key="s"
              :label="stageName(s)"
              :color="stageColor(s)"
              variant="subtle"
              size="sm"
              class="cds-tag"
            />
            <span class="text-xs text-muted">· {{ stagesOf(row.original.id).length }}</span>
          </div>
          <span v-else class="text-sm text-muted">{{ t("cs.customers.noProducts") }}</span>
        </template>
        <template #created-cell="{ row }">
          <span class="text-sm text-muted">{{ formatDate(row.original.created_at?.slice(0, 10)) }}</span>
        </template>
      </UTable>

      <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-3" :class="viewMode === 'list' && 'md:hidden'">
        <button
          v-for="c in pagedCards"
          :key="c.id"
          type="button"
          class="flex flex-col gap-2 border border-default bg-default p-4 text-start transition-colors hover:border-primary hover:bg-elevated"
          @click="openCustomer(c.id)"
        >
          <div class="flex items-start gap-3">
            <UAvatar
              :text="isCompanyCustomer(c) ? undefined : customerTitle(c).trim().charAt(0).toUpperCase()"
              :icon="isCompanyCustomer(c) ? 'i-lucide-building-2' : undefined"
              size="md"
            />
            <div class="min-w-0 flex-1">
              <div class="truncate font-semibold text-highlighted">{{ customerTitle(c) }}</div>
              <div v-if="customerSubtitle(c)" class="truncate text-xs text-toned">{{ customerSubtitle(c) }}</div>
            </div>
            <a
              v-if="toWhatsAppLink(c.phone)"
              :href="toWhatsAppLink(c.phone)!"
              target="_blank"
              rel="noopener noreferrer"
              :aria-label="t('crm.deals.chatOnWhatsApp')"
              class="flex size-8 shrink-0 items-center justify-center text-[#25D366] hover:opacity-80"
              @click.stop
            >
              <UIcon name="i-simple-icons-whatsapp" class="size-5" />
            </a>
          </div>

          <div class="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted">
            <bdi v-if="c.phone" dir="ltr">{{ c.phone }}</bdi>
            <span v-if="areaName(c.area_id)" class="flex items-center gap-1">
              <UIcon name="i-lucide-map-pin" class="size-3.5" />{{ areaName(c.area_id) }}
            </span>
          </div>
          <p v-if="c.address" class="line-clamp-1 text-xs text-muted">{{ c.address }}</p>

          <div class="mt-1 flex flex-wrap items-center gap-1.5">
            <template v-if="stagesOf(c.id).length">
              <UBadge
                v-for="s in stageBadges(c.id)"
                :key="s"
                :label="stageName(s)"
                :color="stageColor(s)"
                variant="subtle"
                size="sm"
                class="cds-tag"
              />
              <span class="text-xs text-muted">· {{ t("cs.customers.productsCount", { count: stagesOf(c.id).length }) }}</span>
            </template>
            <span v-else class="text-xs text-muted">{{ t("cs.customers.noProducts") }}</span>
          </div>
        </button>
      </div>

      <div v-if="filtered.length" class="mt-3 flex flex-wrap items-center justify-between gap-2 border-t border-default pt-3">
        <span class="text-sm text-muted">{{ t("cs.customers.total", { count: filtered.length }) }}</span>
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

  <CustomerFormModal v-model:open="createOpen" @saved="onCreated" />
</template>
