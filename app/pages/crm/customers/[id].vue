<script setup lang="ts">
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
const { t } = useI18n();
const { stageName, stageColor, formatDate, loadPipelines } = useCs();

interface Customer {
  id: string;
  name: string;
  company: string | null;
  phone: string | null;
  extra_phones: string[];
  email: string | null;
  address: string | null;
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
watchEffect(() => {
  if (customerPayload.value) customer.value = customerPayload.value;
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
const { data: products } = await useAsyncData<CsProduct[]>(`crm-customer-${customerId}-products`, async () => {
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
// Customer Service owns the product record; only its people can open it.
const canOpenProducts = computed(() => hasAnyModulePermission("cs_customers"));
function openProduct() {
  if (canOpenProducts.value) navigateTo({ path: "/cs/customers", query: { id: customerId } });
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
    extra_phones: (customer.value.extra_phones ?? []).map((p) => p.trim()).filter((p) => p.length > 0),
    email: customer.value.email,
    address: customer.value.address,
  };
  if (canAssign.value) payload.assigned_to = customer.value.assigned_to;

  const { error } = await supabase.from("customers").update(payload).eq("id", customerId);
  saving.value = false;

  if (error) {
    toast.add({ title: t("crm.customers.saveFailed"), description: error.message, color: "error" });
    return;
  }
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
        <section class="border border-default bg-default p-4 @container sm:p-5">
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
              <UButton v-if="customer.phone" :to="`tel:${customer.phone}`" icon="i-lucide-phone" color="neutral" variant="outline" :label="t('crm.deals.callContact')" />
              <UButton
                v-if="toWhatsAppLink(customer.phone)"
                :to="toWhatsAppLink(customer.phone)!"
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
                <ExtraPhones v-if="canEdit" v-model="customer.extra_phones" />
                <div v-else class="space-y-1 text-sm">
                  <bdi v-for="p in customer.extra_phones" :key="p" dir="ltr" class="block">{{ p }}</bdi>
                  <span v-if="!customer.extra_phones?.length" class="text-muted">—</span>
                </div>
              </UFormField>
              <UFormField :label="t('common.email')">
                <UInput v-model="customer.email" type="email" :disabled="!canEdit" class="w-full" />
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
              <UButton v-if="canEdit" :label="t('common.save')" :loading="saving" @click="save" />
            </div>
          </UPageCard>

          <div class="min-w-0 space-y-5">
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
            <section class="border border-default bg-default">
              <h3 class="flex items-center gap-2 border-b border-default px-4 py-3 text-sm font-semibold text-highlighted">
                {{ t("cs.profile.products") }}
                <UBadge :label="String(products?.length ?? 0)" color="neutral" variant="subtle" size="sm" class="cds-tag" />
              </h3>
              <p v-if="!products?.length" class="p-4 text-sm text-muted">{{ t("crm.customers.noProductsYet") }}</p>
              <ul v-else class="divide-y divide-default">
                <li v-for="p in products" :key="p.id">
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
    </template>
  </UDashboardPanel>
</template>
