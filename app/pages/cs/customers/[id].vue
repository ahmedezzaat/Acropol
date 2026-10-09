<script setup lang="ts">
definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "cs_customers" },
});

useHead({ htmlAttrs: { class: "carbon" } });

const route = useRoute();
const customerId = route.params.id as string;

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();
const { hasPermission, hasAnyModulePermission } = usePermissions();
const { stageById, stageLimitDays, dateIndex, dateOf, daysSince, formatDate, formatDateTime, maintenanceDue, loadAreas, loadPipelines, areaName } = useCs();

const canEdit = computed(() => hasPermission("cs_customers", "edit"));
const canDelete = computed(() => hasPermission("cs_customers", "delete"));
const canSeeDeals = computed(() => hasAnyModulePermission("crm_deals"));

// Synced through useAsyncData's own `data` (see crm/leads/[id].vue for why).
const { data: customer, refresh: refreshCustomer, status } = await useAsyncData<CsCustomer | null>(
  `cs-customer-${customerId}`,
  async () => {
    const { data, error } = await supabase
      .from("customers")
      .select("id, name, company, phone, email, address, area_id, converted_from_lead_id, created_at, customer_type")
      .eq("id", customerId)
      .maybeSingle();
    if (error) throw error;
    return (data ?? null) as CsCustomer | null;
  },
);
await useAsyncData("cs-customer-areas", async () => {
  await Promise.all([loadAreas(true), loadPipelines(true)]);
  return true;
});

const { data: productData, refresh: refreshProducts } = await useAsyncData<{
  products: CsProduct[];
  items: CsProductItem[];
  dates: CsStageDate[];
}>(
  `cs-customer-${customerId}-products`,
  async () => {
    const { data: products, error } = await supabase
      .from("customer_products")
      .select("*")
      .eq("customer_id", customerId)
      .order("created_at", { ascending: false });
    if (error) throw error;
    const ids = (products ?? []).map((p) => p.id);
    const [{ data: items }, { data: dates }] = ids.length
      ? await Promise.all([
          supabase.from("customer_product_items").select("*").in("product_id", ids).order("sort_order"),
          supabase.from("customer_product_stage_dates").select("product_id, stage_id, reached_on").in("product_id", ids),
        ])
      : [{ data: [] }, { data: [] }];
    return {
      products: (products ?? []) as CsProduct[],
      items: (items ?? []) as CsProductItem[],
      dates: (dates ?? []) as CsStageDate[],
    };
  },
);
const products = computed(() => productData.value?.products ?? []);
const dates = computed(() => dateIndex(productData.value?.dates ?? []));
function itemsOf(productId: string) {
  return (productData.value?.items ?? []).filter((i) => i.product_id === productId);
}

// Deals the CRM has for this customer (read-only context for the agent).
interface LinkedDeal {
  id: string;
  title: string;
  value: number | null;
  created_at: string;
}
const { data: deals } = await useAsyncData<LinkedDeal[]>(`cs-customer-${customerId}-deals`, async () => {
  if (!canSeeDeals.value) return [];
  const { data, error } = await supabase
    .from("deals")
    .select("id, title, value, created_at")
    .eq("customer_id", customerId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data ?? [];
});

const { data: people } = await useAsyncData<{ id: string; full_name: string | null; email: string }[]>("cs-customer-people", async () => {
  const { data } = await supabase.from("profiles").select("id, full_name, email");
  return data ?? [];
});
function salesPersonName(id: string | null) {
  const u = id ? people.value?.find((x) => x.id === id) : null;
  return u ? u.full_name || u.email : null;
}

const { data: categories } = await useAsyncData<{ id: string; name: string; maintenance_interval_months: number | null }[]>("cs-customer-categories", async () => {
  const { data } = await supabase.from("product_categories").select("id, name, maintenance_interval_months");
  return data ?? [];
});
function categoryName(id: string | null) {
  return id ? (categories.value?.find((c) => c.id === id)?.name ?? "") : "";
}

// ---- At-a-glance numbers for the header strip
const completedCount = computed(() => products.value.filter((p) => stageById(p.stage_id)?.is_final).length);
const inProgressCount = computed(() => products.value.length - completedCount.value);
const unpaidCount = computed(() => products.value.filter((p) => p.payment_status === "unpaid").length);
const inWarrantyCount = computed(() => products.value.filter((p) => p.warranty_status === "in_warranty").length);
const overdueCount = computed(() => products.value.filter((p) => isOverdue(p)).length);
const kpis = computed(() => [
  { key: "products", icon: "i-lucide-package", value: products.value.length, tone: "" },
  { key: "inProgress", icon: "i-lucide-loader", value: inProgressCount.value, tone: overdueCount.value ? "text-warning" : "" },
  { key: "completed", icon: "i-lucide-circle-check", value: completedCount.value, tone: completedCount.value ? "text-success" : "" },
  { key: "inWarranty", icon: "i-lucide-shield-check", value: inWarrantyCount.value, tone: "" },
  { key: "unpaid", icon: "i-lucide-banknote", value: unpaidCount.value, tone: unpaidCount.value ? "text-error" : "" },
]);

const customerSince = computed(() => formatDate(customer.value?.created_at?.slice(0, 10)));
const mapsLink = computed(() =>
  customer.value?.address ? `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(customer.value.address)}` : null,
);

async function copyText(text: string | null | undefined) {
  if (!text) return;
  try {
    await navigator.clipboard.writeText(text);
    toast.add({ title: t("cs.profile.copied"), color: "success", duration: 1500 });
  } catch {
    // clipboard blocked: nothing to do
  }
}

function productMenu(p: CsProduct) {
  return [
    [
      { label: t("cs.profile.editProduct"), icon: "i-lucide-pencil", onSelect: () => openEditProduct(p) },
      ...(canDelete.value
        ? [{ label: t("common.delete"), icon: "i-lucide-trash", color: "error" as const, onSelect: () => askDelete(p) }]
        : []),
    ],
  ];
}

function formatMoney(value: number | null) {
  return value ? `${value.toLocaleString("en-US")} ${t("common.currency")}` : null;
}

// ---- Edit customer
const editOpen = ref(false);
async function onCustomerSaved() {
  await refreshCustomer();
}
function openEdit() {
  editOpen.value = true;
}

// ---- Products
const productModalOpen = ref(false);
const editingProduct = ref<CsProduct | null>(null);
function openAddProduct() {
  editingProduct.value = null;
  productModalOpen.value = true;
}
function openEditProduct(p: CsProduct) {
  editingProduct.value = p;
  productModalOpen.value = true;
}

const stageModalOpen = ref(false);
const stageProduct = ref<CsProduct | null>(null);
function openStage(p: CsProduct) {
  stageProduct.value = p;
  stageModalOpen.value = true;
}

// Maintenance can be scheduled once a product reached the completed stage.
const doneOpen = ref(false);
const doneProduct = ref<CsProduct | null>(null);
function openDone(p: CsProduct) {
  doneProduct.value = p;
  doneOpen.value = true;
}
const maintenanceOpen = ref(false);
const maintenanceProduct = ref<CsProduct | null>(null);
function openMaintenance(p: CsProduct) {
  maintenanceProduct.value = p;
  maintenanceOpen.value = true;
}
function intervalOf(p: CsProduct) {
  return categories.value?.find((c) => c.id === p.category_id)?.maintenance_interval_months ?? null;
}
function periodicDue(p: CsProduct) {
  return p.maintenance_declined_at ? null : maintenanceDue(p, intervalOf(p));
}
const canSchedule = (p: CsProduct) => !!stageById(p.stage_id)?.is_final || !!p.next_maintenance_at || !!p.maintenance_declined_at;
const maintenanceLate = (p: CsProduct) => !p.maintenance_declined_at && !!p.next_maintenance_at && new Date(p.next_maintenance_at).getTime() < Date.now();

const deleteOpen = ref(false);
const deleteTarget = ref<CsProduct | null>(null);
const deleting = ref(false);
function askDelete(p: CsProduct) {
  deleteTarget.value = p;
  deleteOpen.value = true;
}
function closeDelete() {
  deleteOpen.value = false;
}
async function confirmDelete() {
  if (!deleteTarget.value) return;
  deleting.value = true;
  const { error } = await supabase.from("customer_products").delete().eq("id", deleteTarget.value.id);
  deleting.value = false;
  if (error) {
    toast.add({ title: t("cs.profile.productSaveFailed"), description: error.message, color: "error" });
    return;
  }
  deleteOpen.value = false;
  toast.add({ title: t("cs.profile.productDeleted"), color: "success" });
  refreshProducts();
}

// Days the product has been in its current stage, and whether that is past the
// stage's maximum stay (set in Settings, like the CRM's stage limits).
function daysInCurrent(p: CsProduct) {
  return daysSince(dateOf(dates.value, p.id, p.stage_id) ?? p.contract_date);
}
function isOverdue(p: CsProduct) {
  const limit = stageLimitDays(stageById(p.stage_id));
  const days = daysInCurrent(p);
  return limit !== null && days !== null && days > limit;
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="customer ? customerTitle(customer) : t('cs.customers.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton
            icon="i-lucide-arrow-right"
            color="neutral"
            variant="ghost"
            to="/cs/customers"
            :label="t('cs.profile.back')"
            class="rtl:flex-row-reverse"
          />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>
      <p v-else-if="!customer" class="py-16 text-center text-sm text-muted">{{ t("cs.profile.notFound") }}</p>

      <div v-else class="mx-auto w-full max-w-6xl space-y-5">
        <!-- ===== Header ===== -->
        <div class="border border-default bg-default p-4 sm:p-5">
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
                <UBadge v-if="areaName(customer.area_id)" :label="areaName(customer.area_id)" icon="i-lucide-map-pin" color="neutral" variant="outline" size="sm" class="cds-tag" />
                <span class="text-xs text-muted">{{ t("cs.profile.customerSince", { date: customerSince }) }}</span>
              </div>
            </div>
            <div class="flex w-full shrink-0 flex-wrap items-center gap-2 sm:w-auto">
              <UButton
                v-if="customer.phone"
                :to="`tel:${customer.phone}`"
                icon="i-lucide-phone"
                color="neutral"
                variant="outline"
                :label="t('crm.deals.callContact')"
              />
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
              <UButton
                v-if="customer.email"
                :to="`mailto:${customer.email}`"
                icon="i-lucide-mail"
                color="neutral"
                variant="outline"
                :aria-label="t('common.email')"
              />
              <UButton v-if="canEdit" icon="i-lucide-pencil" :label="t('cs.customers.edit')" @click="openEdit" />
            </div>
          </div>
        </div>

        <div class="grid items-start gap-5 lg:grid-cols-[19rem_minmax(0,1fr)]">
          <!-- ===== Contact details ===== -->
          <aside class="space-y-5 lg:sticky lg:top-0">
            <section class="border border-default bg-default">
              <h3 class="border-b border-default px-4 py-3 text-sm font-semibold text-highlighted">{{ t("cs.profile.contactInfo") }}</h3>
              <dl class="divide-y divide-default text-sm">
                <div class="flex items-start justify-between gap-3 px-4 py-3">
                  <div class="min-w-0">
                    <dt class="text-xs text-muted">{{ t("common.phone") }}</dt>
                    <dd class="font-medium text-highlighted"><bdi dir="ltr">{{ customer.phone || "—" }}</bdi></dd>
                  </div>
                  <UButton
                    v-if="customer.phone"
                    icon="i-lucide-copy"
                    size="xs"
                    color="neutral"
                    variant="ghost"
                    :aria-label="t('cs.profile.copy')"
                    @click="copyText(customer.phone)"
                  />
                </div>
                <div class="flex items-start justify-between gap-3 px-4 py-3">
                  <div class="min-w-0">
                    <dt class="text-xs text-muted">{{ t("common.email") }}</dt>
                    <dd class="break-all font-medium text-highlighted">{{ customer.email || "—" }}</dd>
                  </div>
                  <UButton
                    v-if="customer.email"
                    icon="i-lucide-copy"
                    size="xs"
                    color="neutral"
                    variant="ghost"
                    :aria-label="t('cs.profile.copy')"
                    @click="copyText(customer.email)"
                  />
                </div>
                <div class="px-4 py-3">
                  <dt class="text-xs text-muted">{{ t("cs.customers.area") }}</dt>
                  <dd class="font-medium text-highlighted">{{ areaName(customer.area_id) || "—" }}</dd>
                </div>
                <div class="px-4 py-3">
                  <dt class="flex items-center justify-between gap-2 text-xs text-muted">
                    {{ t("cs.customers.address") }}
                    <a
                      v-if="mapsLink"
                      :href="mapsLink"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="flex items-center gap-1 text-primary hover:underline"
                    >
                      <UIcon name="i-lucide-map" class="size-3.5" />{{ t("cs.profile.openMap") }}
                    </a>
                  </dt>
                  <dd class="mt-0.5 whitespace-pre-line font-medium text-highlighted">{{ customer.address || "—" }}</dd>
                </div>
                <div v-if="canSeeDeals && customer.converted_from_lead_id" class="px-4 py-3">
                  <NuxtLink :to="`/crm/leads?id=${customer.converted_from_lead_id}`" class="flex items-center gap-1.5 text-sm text-primary hover:underline">
                    <UIcon name="i-lucide-user-plus" class="size-4" />{{ t("cs.profile.fromLead") }}
                  </NuxtLink>
                </div>
              </dl>
            </section>

            <!-- ===== CRM context ===== -->
            <section v-if="canSeeDeals && deals?.length" class="border border-default bg-default">
              <h3 class="border-b border-default px-4 py-3 text-sm font-semibold text-highlighted">{{ t("cs.profile.linkedDeals") }}</h3>
              <ul class="divide-y divide-default">
                <li v-for="d in deals" :key="d.id">
                  <NuxtLink
                    :to="`/crm/deals/${d.id}`"
                    class="flex flex-wrap items-center justify-between gap-2 px-4 py-3 text-sm transition-colors hover:bg-elevated"
                  >
                    <span class="font-medium text-highlighted">{{ d.title || "—" }}</span>
                    <span v-if="formatMoney(d.value)" class="font-semibold text-success">{{ formatMoney(d.value) }}</span>
                  </NuxtLink>
                </li>
              </ul>
            </section>
          </aside>

          <!-- ===== Overview + products ===== -->
          <div class="min-w-0 space-y-5">
            <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 xl:grid-cols-5">
              <div v-for="k in kpis" :key="k.key" class="border border-default bg-default p-3">
                <div class="flex items-center gap-1.5 text-xs text-muted">
                  <UIcon :name="k.icon" class="size-3.5" />{{ t(`cs.profile.kpi.${k.key}`) }}
                </div>
                <div class="mt-1 text-2xl font-bold" :class="k.tone || 'text-highlighted'">{{ k.value }}</div>
              </div>
            </div>

            <section class="space-y-3">
              <div class="flex items-center justify-between gap-2">
                <h3 class="flex items-center gap-2 text-lg font-semibold text-highlighted">
                  {{ t("cs.profile.products") }}
                  <UBadge :label="String(products.length)" color="neutral" variant="subtle" class="cds-tag" />
                </h3>
                <UButton v-if="canEdit" icon="i-lucide-plus" :label="t('cs.profile.addProduct')" @click="openAddProduct" />
              </div>

              <div v-if="!products.length" class="flex flex-col items-center gap-3 border border-dashed border-default p-10 text-center">
                <UIcon name="i-lucide-package-plus" class="size-8 text-muted" />
                <p class="text-sm text-muted">{{ t("cs.profile.noProducts") }}</p>
                <UButton v-if="canEdit" icon="i-lucide-plus" :label="t('cs.profile.addProduct')" @click="openAddProduct" />
              </div>

              <ProductCard
                v-for="p in products"
                :key="p.id"
                :product="p"
                :dates="dates"
                :items="itemsOf(p.id)"
                :category-name="categoryName(p.category_id)"
                :sales-person-name="salesPersonName(p.sales_person_id)"
              >
                <template #actions>
                  <div v-if="canEdit" class="flex shrink-0 items-center gap-1">
                    <UButton icon="i-lucide-workflow" size="sm" :label="t('cs.installations.updateProgress')" @click="openStage(p)" />
                    <UDropdownMenu :items="productMenu(p)">
                      <UButton icon="i-lucide-ellipsis-vertical" size="sm" color="neutral" variant="outline" :aria-label="t('cs.profile.moreActions')" />
                    </UDropdownMenu>
                  </div>
                </template>
                <template #extra>
                <!-- Next maintenance -->
                <div
                  v-if="canSchedule(p)"
                  class="flex flex-wrap items-center justify-between gap-3 border p-3"
                  :class="maintenanceLate(p) ? 'border-error/40 bg-error/5' : 'border-default bg-muted'"
                >
                  <div class="flex min-w-0 items-start gap-2.5">
                    <UIcon name="i-lucide-wrench" class="mt-0.5 size-4 shrink-0" :class="maintenanceLate(p) ? 'text-error' : 'text-muted'" />
                    <div class="min-w-0 text-sm">
                      <div class="text-xs text-muted">{{ t("cs.maintenance.next") }}</div>
                      <div v-if="p.maintenance_declined_at" class="font-medium text-error">{{ t("cs.maintenance.declinedNote") }}</div>
                      <div v-else-if="p.next_maintenance_at" class="font-medium" :class="maintenanceLate(p) ? 'text-error' : 'text-highlighted'">
                        {{ formatDateTime(p.next_maintenance_at) }}
                      </div>
                      <div v-else class="text-muted">{{ t("cs.maintenance.notScheduled") }}</div>
                      <p v-if="p.next_maintenance_note" class="mt-0.5 whitespace-pre-line text-toned">{{ p.next_maintenance_note }}</p>
                      <p v-if="intervalOf(p)" class="mt-1 text-xs text-muted">
                        {{ t("cs.maintenance.periodic", { months: intervalOf(p) }) }}
                        <template v-if="periodicDue(p)">· {{ t("cs.maintenance.dueOn", { date: formatDate(periodicDue(p)) }) }}</template>
                        <template v-if="p.last_maintenance_on">· {{ t("cs.maintenance.lastDone") }}: {{ formatDate(p.last_maintenance_on) }}</template>
                      </p>
                    </div>
                  </div>
                  <div class="flex flex-wrap items-center gap-2">
                    <UButton
                      :to="`/cs/maintenance/${p.id}`"
                      icon="i-lucide-clipboard-list"
                      size="sm"
                      color="neutral"
                      variant="ghost"
                      :label="t('cs.maintenance.record')"
                    />
                    <template v-if="canEdit && !p.maintenance_declined_at">
                    <UButton v-if="p.next_maintenance_at" icon="i-lucide-check" size="sm" color="success" variant="soft" :label="t('cs.maintenance.markDone')" @click="openDone(p)" />
                    <UButton
                      :icon="p.next_maintenance_at ? 'i-lucide-calendar-sync' : 'i-lucide-calendar-plus'"
                      size="sm"
                      color="neutral"
                      variant="outline"
                      :label="t(p.next_maintenance_at ? 'cs.maintenance.reschedule' : 'cs.maintenance.schedule')"
                      @click="openMaintenance(p)"
                    />
                    </template>
                  </div>
                </div>
                </template>
              </ProductCard>
            </section>
          </div>
        </div>
      </div>
    </template>
  </UDashboardPanel>

  <CustomerFormModal v-model:open="editOpen" :customer="customer" @saved="onCustomerSaved" />
  <ProductFormModal
    v-model:open="productModalOpen"
    :customer-id="customerId"
    :product="editingProduct"
    @saved="refreshProducts"
  />
  <ProductStageModal v-model:open="stageModalOpen" :product="stageProduct" @saved="refreshProducts" />
  <MaintenanceModal v-model:open="maintenanceOpen" :product="maintenanceProduct" @saved="refreshProducts" />
  <MaintenanceDoneModal v-model:open="doneOpen" :product="doneProduct" @saved="refreshProducts" />

  <UModal v-model:open="deleteOpen" :title="t('cs.profile.deleteProduct')">
    <template #body>
      <div class="space-y-4">
        <p class="text-sm text-muted">{{ t("cs.profile.deleteConfirm", { name: deleteTarget?.name ?? "" }) }}</p>
        <div class="flex gap-2">
          <UButton color="neutral" variant="outline" :label="t('common.cancel')" class="flex-1 justify-center" @click="closeDelete" />
          <UButton color="error" :label="t('common.delete')" :loading="deleting" class="flex-1 justify-center" @click="confirmDelete" />
        </div>
      </div>
    </template>
  </UModal>
</template>
