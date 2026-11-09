<script setup lang="ts">
const { waLink } = useWaLink();
definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "crm_customers" },
});

const route = useRoute();
const customerId = route.params.id as string;
useHead({ htmlAttrs: { class: "carbon" } });

const supabase = useSupabaseClient();
const toast = useToast();
const { hasPermission, hasAnyModulePermission } = usePermissions();
const { t, locale } = useI18n();
const { stageName, stageColor, formatDate, loadPipelines } = useCs();

interface Customer {
  id: string;
  name: string;
  company: string | null;
  phone: string | null;
  extra_phones: string[];
  extra_phone_names?: string[];
  email: string | null;
  address: string | null;
  area_id?: string | null;
  assigned_to: string | null;
  created_at: string;
  customer_type: "individual" | "company";
}

interface Profile {
  id: string;
  full_name: string | null;
  email: string;
}

interface Deal {
  id: string;
  title: string;
  value: number | null;
  created_at: string;
  assigned_to: string | null;
  stage: { name: string; system_key: string | null; reason_category: string | null } | null;
}

interface Quote {
  id: string;
  quote_number: string;
  status: string;
  total: number;
}

const customer = ref<Customer | null>(null);
const saving = ref(false);
const canEdit = computed(() => hasPermission("crm_customers", "edit"));
const canDelete = computed(() => hasPermission("crm_customers", "delete"));
const canAssign = computed(() => hasPermission("crm_customers", "assign"));

// See leads/[id].vue for why this syncs via watchEffect from useAsyncData's
// own `data` rather than only mutating `customer` inside the handler.
const { data: customerPayload, status } = await useAsyncData(`crm-customer-${customerId}`, async () => {
  const { data, error } = await supabase.from("customers").select("*").eq("id", customerId).single();
  if (error) throw error;
  return data;
});
// The extra phones are edited as { phone, name } rows.
const extraContacts = ref<ExtraContact[]>([]);
watchEffect(() => {
  if (customerPayload.value) {
    customer.value = customerPayload.value;
    extraContacts.value = toExtraContacts(customerPayload.value.extra_phones, customerPayload.value.extra_phone_names);
  }
});

const { data: profiles } = await useAsyncData<Profile[]>(`crm-customer-${customerId}-profiles`, async () => {
  const { data, error } = await supabase.from("profiles").select("id, full_name, email").eq("is_active", true);
  if (error) throw error;
  return data ?? [];
});
const assigneeOptions = computed(() => [
  { label: t("common.unassigned"), value: null },
  ...(profiles.value ?? []).map((p) => ({ label: p.full_name || p.email, value: p.id })),
]);

const { data: deals } = await useAsyncData<Deal[]>(`crm-customer-${customerId}-deals`, async () => {
  const { data, error } = await supabase
    .from("deals")
    .select("id, title, value, created_at, assigned_to, stage:pipeline_stages(name, system_key, reason_category)")
    .eq("customer_id", customerId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data ?? [];
});

const { data: quotes } = await useAsyncData<Quote[]>(`crm-customer-${customerId}-quotes`, async () => {
  const { data, error } = await supabase
    .from("quotes")
    .select("id, quote_number, status, total")
    .eq("customer_id", customerId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data ?? [];
});

function personName(id: string | null) {
  const p = id ? profiles.value?.find((x) => x.id === id) : null;
  return p ? p.full_name || p.email : null;
}
// Closed-won reads as success, bought-from-competitor as error, archived as
// neutral, everything still open as the brand colour.
function dealColor(deal: Deal) {
  const key = deal.stage?.system_key;
  if (key === "won") return "success" as const;
  if (key === "competitor" || deal.stage?.reason_category === "competitor") return "error" as const;
  if (key === "archive" || deal.stage?.reason_category === "archive") return "neutral" as const;
  return "primary" as const;
}
function formatMoney(value: number | null) {
  return value ? `${value.toLocaleString("en-US")} ${t("common.currency")}` : null;
}
const wonValue = computed(() =>
  (deals.value ?? []).filter((d) => d.stage?.system_key === "won").reduce((sum, d) => sum + (d.value ?? 0), 0),
);

// The products this customer bought (Customer Service products), with the
// deal each one was sold in.
const { data: products, refresh: refreshProducts } = await useAsyncData<CsProduct[]>(`crm-customer-${customerId}-products`, async () => {
  await loadPipelines(true);
  const { data, error } = await supabase
    .from("customer_products")
    .select("*")
    .eq("customer_id", customerId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as CsProduct[];
});
const { data: categories } = await useAsyncData<{ id: string; name: string }[]>(`crm-customer-${customerId}-categories`, async () => {
  const { data } = await supabase.from("product_categories").select("id, name");
  return data ?? [];
});
function categoryName(id: string | null) {
  return id ? (categories.value?.find((c) => c.id === id)?.name ?? null) : null;
}
function dealTitle(id: string | null) {
  return id ? (deals.value?.find((d) => d.id === id)?.title ?? null) : null;
}
// ---- The customer's contracts, with everything entered on them (and on the products they cover)
interface ContractFull {
  id: string; code: string; signed_on: string | null; value: number | null; notes: string | null; file_name: string | null; file_path: string | null;
  deal_id: string | null; created_by: string | null; created_at: string;
}
const { data: contracts, refresh: refreshContracts } = await useAsyncData<ContractFull[]>(`crm-customer-${customerId}-contracts`, async () => {
  const { data } = await supabase
    .from("contracts")
    .select("id, code, signed_on, value, notes, file_name, file_path, deal_id, created_by, created_at")
    .eq("customer_id", customerId)
    .order("signed_on", { ascending: false });
  return (data ?? []) as ContractFull[];
});
const contractsTotal = computed(() => (contracts.value ?? []).reduce((sum, c) => sum + (c.value ?? 0), 0));
const openDeals = computed(() => (deals.value ?? []).filter((d) => dealColor(d) === "primary").length);
// a product belongs to a contract by its id, or (older records) by the contract code
const productsOf = (c: ContractFull) => (products.value ?? []).filter((p) => (p.contract_id ? p.contract_id === c.id : !!p.contract_code && p.contract_code === c.code));
// a contract is named after what was bought
const contractTitleOf = (c: ContractFull) => {
  const names = productsOf(c).filter((p) => p.name?.trim()).map((p) => (p.quantity > 1 ? `${p.name.trim()} × ${p.quantity}` : p.name.trim()));
  return names.join("، ") || dealTitle(c.deal_id) || `#${c.code}`;
};
const looseProducts = computed(() => (products.value ?? []).filter((p) => !(contracts.value ?? []).some((c) => productsOf(c).some((x) => x.id === p.id))));
const agentsOfContract = (c: ContractFull) => [...new Set(productsOf(c).map((p) => personName(p.sales_person_id)).filter((x): x is string => !!x))];
const moneyFull = (v: number | null) => (v === null || v === undefined ? "—" : formatReportMoney(v, t("common.currency")));
async function downloadContractFile(c: ContractFull) {
  if (!c.file_path) return;
  const { data, error } = await supabase.storage.from("contract-files").createSignedUrl(c.file_path, 60, { download: c.file_name ?? true });
  if (error || !data) {
    toast.add({ title: t("crm.contracts.fileFailed"), description: error?.message, color: "error" });
    return;
  }
  const a = document.createElement("a");
  a.href = data.signedUrl;
  a.click();
}
const canCreateContract = computed(() => hasPermission("crm_customers", "create"));
const newContractOpen = ref(false);
async function onContractSaved() {
  await Promise.all([refreshContracts(), refreshProducts()]);
}

// ---- unsaved changes in the details form
const formState = () => JSON.stringify([customer.value?.name, customer.value?.company, customer.value?.phone, customer.value?.email, customer.value?.address, customer.value?.area_id, customer.value?.assigned_to, extraContacts.value]);
const snapshot = ref("");
watch(customerPayload, () => (snapshot.value = formState()), { immediate: true });
const dirty = computed(() => snapshot.value !== formState());

// Files come from the customer's deals, so they follow the deals permission.
const canSeeFiles = computed(() => hasAnyModulePermission("crm_deals"));
const mainTab = ref<"main" | "files">("main");
const mainTabs = computed(() => [
  { value: "main", label: t("files.detailsTab") },
  { value: "files", label: t("files.tab") },
]);
// Customer Service owns the product record; only its people can open it.
const canOpenProducts = computed(() => hasAnyModulePermission("cs_customers"));
function openProduct() {
  if (canOpenProducts.value) navigateTo(`/cs/customers/${customerId}`);
}
const warrantyColor = { in_warranty: "success", out_of_warranty: "neutral" } as const;
const paymentColor = { paid: "success", unpaid: "error" } as const;

async function save() {
  if (!customer.value) return;
  saving.value = true;
  const payload: Record<string, unknown> = {
    name: customer.value.name,
    company: customer.value.company,
    phone: trimOrNull(customer.value.phone),
    ...fromExtraContacts(extraContacts.value),
    email: customer.value.email,
    address: customer.value.address,
    area_id: customer.value.area_id || null,
  };
  if (canAssign.value) payload.assigned_to = customer.value.assigned_to;

  const { error } = await supabase.from("customers").update(payload).eq("id", customerId);
  saving.value = false;

  if (error) {
    toast.add({ title: t("crm.customers.saveFailed"), description: error.message, color: "error" });
    return;
  }
  snapshot.value = formState();
  toast.add({ title: t("crm.customers.customerSaved"), color: "success" });
}

async function remove() {
  const { error } = await supabase.from("customers").delete().eq("id", customerId);
  if (error) {
    toast.add({ title: t("crm.customers.deleteFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("crm.customers.customerDeleted"), color: "success" });
  navigateTo("/crm/customers");
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="customer?.name ?? t('crm.customers.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton to="/crm/contracts" icon="i-lucide-arrow-right" color="neutral" variant="ghost" :label="t('crm.customers.backToContracts')" class="hidden sm:inline-flex" />
          <UButton v-if="canDelete" icon="i-lucide-trash" color="error" variant="soft" @click="remove" />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>

      <div v-else-if="customer" class="mx-auto w-full max-w-6xl space-y-5">
        <!-- ===== Header ===== -->
        <section class="kords-card kords-card-dark p-4 @container sm:p-5">
          <div class="flex flex-wrap items-center gap-4">
            <UAvatar
              :text="isCompanyCustomer(customer) ? undefined : customerTitle(customer).trim().charAt(0).toUpperCase()"
              :icon="isCompanyCustomer(customer) ? 'i-lucide-building-2' : undefined"
              size="3xl"
            />
            <div class="min-w-0 flex-1 basis-56">
              <h2 class="text-xl font-semibold text-highlighted sm:text-2xl">{{ customerTitle(customer) }}</h2>
              <p v-if="customerSubtitle(customer)" class="text-sm text-toned">{{ customerSubtitle(customer) }}</p>
              <div class="mt-2 flex flex-wrap items-center gap-1.5">
                <UBadge
                  :label="t(`crm.leads.type.${isCompanyCustomer(customer) ? 'company' : 'individual'}`)"
                  color="neutral"
                  variant="subtle"
                  size="sm"
                  class="cds-tag"
                />
                <span class="text-xs text-muted">{{ t("cs.profile.customerSince", { date: formatDate(customer.created_at?.slice(0, 10)) }) }}</span>
                <span v-if="wonValue" class="text-xs font-medium text-success">{{ t("crm.customers.wonTotal", { value: formatMoney(wonValue) }) }}</span>
              </div>
            </div>
            <div class="flex w-full shrink-0 flex-wrap items-center gap-2 sm:w-auto">
              <UButton v-if="canCreateContract" icon="i-lucide-file-plus" :label="t('crm.contracts.new')" @click="newContractOpen = true" />
              <UButton v-if="customer.phone" :to="`tel:${customer.phone}`" icon="i-lucide-phone" color="neutral" variant="outline" :label="t('crm.deals.callContact')" />
              <UButton
                v-if="waLink(customer.phone)"
                :to="waLink(customer.phone)!"
                target="_blank"
                rel="noopener noreferrer"
                icon="i-simple-icons-whatsapp"
                color="neutral"
                variant="outline"
                :label="t('cs.profile.whatsapp')"
              />
            </div>
          </div>
        </section>

        <!-- ===== At a glance ===== -->
        <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <div v-for="k in [
            { icon: 'i-lucide-file-signature', label: t('crm.customers.kpi.contracts'), value: String(contracts?.length ?? 0) },
            { icon: 'i-lucide-banknote', label: t('crm.customers.kpi.value'), value: moneyFull(contractsTotal) },
            { icon: 'i-lucide-handshake', label: t('crm.customers.kpi.openDeals'), value: String(openDeals) },
            { icon: 'i-lucide-package', label: t('crm.customers.kpi.products'), value: String(products?.length ?? 0) },
          ]" :key="k.label" class="kords-card flex items-center gap-3 p-3">
            <span class="grid size-9 shrink-0 place-items-center rounded-full bg-primary/10 text-primary"><UIcon :name="k.icon" class="size-4.5" /></span>
            <span class="min-w-0"><span class="block text-xs text-muted">{{ k.label }}</span><span class="block truncate text-base font-semibold text-highlighted">{{ k.value }}</span></span>
          </div>
        </div>

        <div class="grid items-start gap-5 lg:grid-cols-[22rem_minmax(0,1fr)]">
          <!-- ===== Details ===== -->
          <UPageCard :title="t('common.details')">
            <div class="space-y-4">
              <UFormField :label="t('common.name')">
                <UInput v-model="customer.name" :disabled="!canEdit" class="w-full" />
              </UFormField>
              <UFormField :label="t('crm.customers.company')">
                <UInput v-model="customer.company" :disabled="!canEdit" class="w-full" />
              </UFormField>
              <UFormField :label="t('common.phone')">
                <PhoneInput v-model="customer.phone" :disabled="!canEdit" />
              </UFormField>
              <UFormField :label="t('common.extraPhones')">
                <ExtraPhones v-if="canEdit" v-model="extraContacts" />
                <div v-else class="space-y-1 text-sm">
                  <div v-for="c in toExtraContacts(customer.extra_phones, customer.extra_phone_names)" :key="c.phone" class="flex items-center gap-2">
                    <bdi dir="ltr">{{ c.phone }}</bdi>
                    <span v-if="c.name" class="text-muted">· {{ c.name }}</span>
                  </div>
                  <span v-if="!customer.extra_phones?.length" class="text-muted">—</span>
                </div>
              </UFormField>
              <UFormField :label="t('common.email')">
                <UInput v-model="customer.email" type="email" :disabled="!canEdit" class="w-full" />
              </UFormField>
              <UFormField :label="t('cs.customers.area')">
                <AreaSelect v-model="customer.area_id" :disabled="!canEdit" />
              </UFormField>
              <UFormField :label="t('crm.customers.address')">
                <UTextarea v-model="customer.address" :disabled="!canEdit" class="w-full" />
              </UFormField>
              <UFormField :label="t('crm.customers.assignedTo')">
                <USelect
                  v-model="customer.assigned_to"
                  :items="assigneeOptions"
                  value-key="value"
                  :disabled="!canAssign"
                  class="w-full"
                />
                <p v-if="!canAssign" class="mt-1 text-xs text-muted">{{ t("crm.customers.assignPermissionHint") }}</p>
              </UFormField>
              <div v-if="canEdit" class="flex items-center gap-3">
                <UButton :label="t('common.save')" :loading="saving" :disabled="!dirty" @click="save" />
                <span v-if="dirty" class="text-xs text-warning">{{ t("crm.customers.unsaved") }}</span>
              </div>
            </div>
          </UPageCard>

          <div class="min-w-0 space-y-5">
            <UTabs v-if="canSeeFiles" v-model="mainTab" :items="mainTabs" value-key="value" variant="link" :content="false" class="kords-pilltabs" />

            <FilesPanel v-if="canSeeFiles && mainTab === 'files'" :customer-id="customerId" />

            <div v-show="mainTab === 'main'" class="space-y-5">
            <!-- ===== Contracts: everything entered on each one ===== -->
            <section class="space-y-3">
              <div class="flex items-center justify-between gap-2">
                <h3 class="flex items-center gap-2 text-sm font-semibold text-highlighted">
                  {{ t("crm.customers.contractsTitle") }}
                  <UBadge :label="String(contracts?.length ?? 0)" color="neutral" variant="subtle" size="sm" class="cds-tag" />
                </h3>
                <UButton v-if="canCreateContract" size="xs" icon="i-lucide-plus" :label="t('crm.contracts.new')" @click="newContractOpen = true" />
              </div>
              <p v-if="!contracts?.length" class="kords-card p-4 text-sm text-muted">{{ t("crm.customers.noContractsYet") }}</p>
              <ul v-else class="kords-card divide-y divide-default">
                <li v-for="c in contracts" :key="c.id">
                  <NuxtLink :to="`/crm/contracts/${c.id}`" class="flex flex-wrap items-center justify-between gap-x-4 gap-y-1 px-4 py-3 transition-colors hover:bg-elevated">
                    <span class="min-w-0">
                      <span class="flex items-center gap-2 font-medium text-highlighted"><UIcon name="i-lucide-file-signature" class="size-4 text-primary" /><span class="truncate">{{ contractTitleOf(c) }}</span><bdi dir="ltr" class="text-xs font-normal text-muted">#{{ c.code }}</bdi></span>
                      <span class="block text-xs text-muted">{{ t("crm.contracts.signedOn") }}: {{ c.signed_on ? formatDate(c.signed_on) : "—" }}<template v-if="agentsOfContract(c).length"> · {{ agentsOfContract(c).join("، ") }}</template></span>
                    </span>
                    <span class="flex shrink-0 items-center gap-3 text-sm"><span class="font-semibold text-success">{{ moneyFull(c.value) }}</span><UIcon name="i-lucide-chevron-left" class="size-4 text-muted" /></span>
                  </NuxtLink>
                </li>
              </ul>
            </section>

            <!-- ===== Deals ===== -->
            <section class="border border-default bg-default">
              <h3 class="flex items-center gap-2 border-b border-default px-4 py-3 text-sm font-semibold text-highlighted">
                {{ t("crm.customers.dealsTitle") }}
                <UBadge :label="String(deals?.length ?? 0)" color="neutral" variant="subtle" size="sm" class="cds-tag" />
              </h3>
              <p v-if="!deals?.length" class="p-4 text-sm text-muted">{{ t("crm.customers.noDealsYet") }}</p>
              <ul v-else class="divide-y divide-default">
                <li v-for="deal in deals" :key="deal.id">
                  <NuxtLink :to="`/crm/deals/${deal.id}`" class="flex flex-wrap items-center justify-between gap-x-4 gap-y-1 px-4 py-3 transition-colors hover:bg-elevated">
                    <span class="min-w-0">
                      <span class="block truncate font-medium text-highlighted">{{ deal.title || "—" }}</span>
                      <span class="block text-xs text-muted">
                        {{ formatDate(deal.created_at?.slice(0, 10)) }}<template v-if="personName(deal.assigned_to)"> · {{ personName(deal.assigned_to) }}</template>
                      </span>
                    </span>
                    <span class="flex shrink-0 items-center gap-3 text-sm">
                      <span v-if="formatMoney(deal.value)" class="font-semibold" :class="deal.stage?.system_key === 'won' ? 'text-success' : 'text-highlighted'">{{ formatMoney(deal.value) }}</span>
                      <UBadge v-if="deal.stage" :label="deal.stage.name" :color="dealColor(deal)" variant="subtle" size="sm" class="cds-tag" />
                    </span>
                  </NuxtLink>
                </li>
              </ul>
            </section>

            <!-- ===== Products ===== -->
            <section v-if="looseProducts.length" class="border border-default bg-default">
              <h3 class="flex items-center gap-2 border-b border-default px-4 py-3 text-sm font-semibold text-highlighted">
                {{ t("crm.customers.otherProducts") }}
                <UBadge :label="String(looseProducts.length)" color="neutral" variant="subtle" size="sm" class="cds-tag" />
              </h3>
              <ul class="divide-y divide-default">
                <li v-for="p in looseProducts" :key="p.id">
                  <component
                    :is="canOpenProducts ? 'button' : 'div'"
                    :type="canOpenProducts ? 'button' : undefined"
                    class="flex w-full flex-wrap items-center justify-between gap-x-4 gap-y-2 px-4 py-3 text-start"
                    :class="canOpenProducts && 'transition-colors hover:bg-elevated'"
                    @click="openProduct"
                  >
                    <span class="min-w-0">
                      <span class="block truncate font-medium text-highlighted">
                        {{ p.name }}
                        <bdi v-if="p.contract_code" dir="ltr" class="ms-1 text-xs font-normal text-muted">#{{ p.contract_code }}</bdi>
                      </span>
                      <span class="block text-xs text-muted">
                        <template v-if="categoryName(p.category_id)">{{ categoryName(p.category_id) }} · </template>{{ formatDate(p.contract_date) }}<template v-if="dealTitle(p.deal_id)"> · {{ t("crm.customers.fromDeal", { deal: dealTitle(p.deal_id) }) }}</template>
                      </span>
                    </span>
                    <span class="flex shrink-0 flex-wrap items-center gap-1.5">
                      <UBadge :label="stageName(p.stage_id)" :color="stageColor(p.stage_id)" variant="subtle" size="sm" class="cds-tag" />
                      <UBadge
                        v-if="p.warranty_status"
                        :label="t(`cs.profile.warranty.${p.warranty_status}`)"
                        icon="i-lucide-shield"
                        :color="warrantyColor[p.warranty_status as keyof typeof warrantyColor] ?? 'neutral'"
                        variant="subtle"
                        size="sm"
                        class="cds-tag"
                      />
                      <UBadge
                        v-if="p.payment_status"
                        :label="t(`cs.profile.payment.${p.payment_status}`)"
                        icon="i-lucide-banknote"
                        :color="paymentColor[p.payment_status as keyof typeof paymentColor] ?? 'neutral'"
                        variant="subtle"
                        size="sm"
                        class="cds-tag"
                      />
                    </span>
                  </component>
                </li>
              </ul>
            </section>

            <UPageCard :title="t('crm.customers.quotesTitle')">
              <div v-if="!quotes?.length" class="text-sm text-muted">{{ t("crm.customers.noQuotesYet") }}</div>
              <ul v-else class="divide-y divide-default">
                <li v-for="quote in quotes" :key="quote.id" class="py-2">
                  <ULink :to="`/crm/quotes/${quote.id}`" class="flex items-center justify-between">
                    <span>{{ quote.quote_number }}</span>
                    <span class="text-sm text-muted">{{ t(`crm.quotes.statusValues.${quote.status}`) }} · {{ quote.total }}</span>
                  </ULink>
                </li>
              </ul>
            </UPageCard>
            </div>
          </div>
        </div>
      </div>
    </template>
  </UDashboardPanel>

  <CrmContractModal v-if="customer" v-model:open="newContractOpen" :taken-deal-ids="(contracts ?? []).map((c) => c.deal_id).filter((x): x is string => !!x)" :customer-id="customerId" :customer-label="customerTitle(customer)" @saved="onContractSaved" />
</template>
