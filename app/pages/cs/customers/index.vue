<script setup lang="ts">
definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "cs_customers" },
});

useHead({ htmlAttrs: { class: "carbon" } });

const supabase = useSupabaseClient();
const { t } = useI18n();
const { hasPermission } = usePermissions();
const canViewAll = computed(() => hasPermission("cs_customers", "view_all"));
const { areas, stages, pipelines, stageColor, stageName, stageLabelFull, loadAreas, loadPipelines } = useCs();

// Customer service sees every customer: the ones a won deal created in the CRM
// and the ones added here directly.
const { data: customers, refresh, status } = await useAsyncData<CsCustomer[]>("cs-customers", async () => {
  const { data, error } = await supabase
    .from("customers")
    .select("id, name, company, phone, extra_phones, email, address, area_id, created_at, customer_type, cs_agent_id")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as CsCustomer[];
});

const { data: products, refresh: refreshProducts } = await useAsyncData<Pick<CsProduct, "customer_id" | "stage_id" | "category_id">[]>(
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

const filtered = computed(() =>
  (customers.value ?? []).filter((c) => {
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
      const hay = `${c.name} ${c.company ?? ""} ${c.email ?? ""} ${c.address ?? ""}`.toLowerCase();
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

// ---- Master / detail
// The list sits on one side and the selected customer's record on the other (on
// a phone they take turns full-screen). The selection lives in ?id= so it
// survives a refresh and links from other pages open straight to a customer.
const route = useRoute();
const router = useRouter();
const selectedId = ref<string | null>(typeof route.query.id === "string" ? route.query.id : null);

function selectCustomer(id: string | null) {
  selectedId.value = id;
  const query = { ...route.query };
  if (id) query.id = id;
  else delete query.id;
  router.replace({ query });
}
watch(
  () => route.query.id,
  (id) => {
    selectedId.value = typeof id === "string" ? id : null;
  },
);

const selectedCustomer = computed(() => customers.value?.find((c) => c.id === selectedId.value) ?? null);

// On a wide screen there is room for both panes, so open the first customer
// instead of an empty details pane.
onMounted(() => {
  if (!selectedId.value && window.innerWidth >= 1024 && filtered.value[0]) {
    selectedId.value = filtered.value[0].id;
  }
});

function ago(value: string | undefined) {
  if (!value) return "";
  const rtf = new Intl.RelativeTimeFormat(undefined, { numeric: "auto" });
  const days = Math.round((new Date(value).getTime() - Date.now()) / 86_400_000);
  if (Math.abs(days) >= 365) return rtf.format(Math.round(days / 365), "year");
  if (Math.abs(days) >= 30) return rtf.format(Math.round(days / 30), "month");
  if (Math.abs(days) >= 1) return rtf.format(days, "day");
  return rtf.format(0, "day");
}

const createOpen = ref(false);
function openCreate() {
  createOpen.value = true;
}
// The record in the details pane changed something the list shows (name,
// products, stages): reload the list's data too.
async function onChanged() {
  await Promise.all([refresh(), refreshProducts()]);
}
async function onDeleted() {
  selectCustomer(null);
  await onChanged();
}
async function onCreated(id: string) {
  await Promise.all([refresh(), refreshProducts()]);
  selectCustomer(id);
}
</script>

<template>
  <!-- One screen tall with its body padding removed, so the list and the
  details each scroll on their own instead of the whole page. -->
  <UDashboardPanel :ui="{ root: 'h-svh', body: 'gap-0 overflow-hidden p-0 sm:p-0' }">
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
    </template>

    <template #body>
      <div class="flex min-h-0 flex-1">
        <!-- ===== Customer list ===== -->
        <aside
          class="min-h-0 w-full flex-col border-default lg:w-96 lg:shrink-0 lg:border-e"
          :class="selectedCustomer ? 'hidden lg:flex' : 'flex'"
        >
          <div class="shrink-0 space-y-3 border-b border-default p-3">
            <UInput v-model="search" icon="i-lucide-search" :placeholder="t('cs.customers.search')" class="w-full" />
            <UTabs v-model="typeFilter" :items="typeTabs" value-key="value" variant="pill" size="sm" :content="false" class="w-full" />
            <div class="grid grid-cols-2 gap-2">
              <USelect v-model="areaFilter" :items="areaItems" value-key="value" icon="i-lucide-map-pin" class="w-full" />
              <USelect v-model="stageFilter" :items="stageItems" value-key="value" icon="i-lucide-workflow" class="w-full" />
              <USelect v-model="categoryFilter" :items="categoryItems" value-key="value" icon="i-lucide-tags" :class="canViewAll ? 'w-full' : 'col-span-2 w-full'" />
              <USelect v-if="canViewAll" v-model="agentFilter" :items="agentItems" value-key="value" icon="i-lucide-user-round" class="w-full" />
            </div>
          </div>

          <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-10">
            <UIcon name="i-lucide-loader-2" class="size-5 animate-spin text-muted" />
          </div>
          <p v-else-if="!filtered.length" class="p-8 text-center text-sm text-muted">{{ t("cs.customers.empty") }}</p>

          <ul v-else class="min-h-0 flex-1 divide-y divide-default overflow-y-auto overscroll-contain">
            <li v-for="c in filtered" :key="c.id">
              <button
                type="button"
                class="flex w-full items-center gap-3 px-3 py-3 text-start transition-colors hover:bg-elevated"
                :class="c.id === selectedId && 'bg-primary/10'"
                @click="selectCustomer(c.id)"
              >
                <UAvatar
                  :text="isCompanyCustomer(c) ? undefined : customerTitle(c).trim().charAt(0).toUpperCase()"
                  :icon="isCompanyCustomer(c) ? 'i-lucide-building-2' : undefined"
                  size="md"
                />
                <span class="min-w-0 flex-1">
                  <span class="block truncate font-medium text-highlighted">{{ customerTitle(c) }}</span>
                  <span v-if="customerSubtitle(c)" class="block truncate text-xs text-toned">{{ customerSubtitle(c) }}</span>
                  <span class="mt-0.5 flex items-center gap-1.5 text-xs text-muted">
                    <bdi v-if="c.phone" dir="ltr">{{ c.phone }}</bdi>
                    <span v-if="c.phone">·</span>
                    <span>{{ ago(c.created_at) }}</span>
                  </span>
                </span>
                <span class="flex shrink-0 items-center gap-2">
                  <span v-if="stagesOf(c.id).length" class="flex items-center gap-1">
                    <UBadge
                      :label="stageName(stageBadges(c.id)[stageBadges(c.id).length - 1]!)"
                      :color="stageColor(stageBadges(c.id)[stageBadges(c.id).length - 1]!)"
                      variant="subtle"
                      size="sm"
                      class="cds-tag hidden sm:inline-flex"
                    />
                    <span class="text-xs text-muted">{{ stagesOf(c.id).length }}</span>
                  </span>
                  <a
                    v-if="toWhatsAppLink(c.phone)"
                    :href="toWhatsAppLink(c.phone)!"
                    target="_blank"
                    rel="noopener noreferrer"
                    :aria-label="t('crm.deals.chatOnWhatsApp')"
                    class="flex size-8 items-center justify-center text-[#25D366] hover:opacity-80"
                    @click.stop
                  >
                    <UIcon name="i-simple-icons-whatsapp" class="size-5" />
                  </a>
                </span>
              </button>
            </li>
          </ul>
        </aside>

        <!-- ===== Details ===== -->
        <section class="min-h-0 min-w-0 flex-1 flex-col overflow-y-auto" :class="selectedCustomer ? 'flex' : 'hidden lg:flex'">
          <div v-if="!selectedCustomer" class="flex flex-1 flex-col items-center justify-center gap-2 p-8 text-center text-muted">
            <UIcon name="i-lucide-user-round-search" class="size-10" />
            <p class="text-sm">{{ t("cs.customers.selectCustomer") }}</p>
          </div>
          <div v-else class="p-4 sm:p-6">
            <CsCustomerProfile :key="selectedCustomer.id" :customer-id="selectedCustomer.id" @back="selectCustomer(null)" @changed="onChanged" @deleted="onDeleted" />
          </div>
        </section>
      </div>
    </template>
  </UDashboardPanel>

  <CustomerFormModal v-model:open="createOpen" @saved="onCreated" />
</template>
