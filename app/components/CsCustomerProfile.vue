<script setup lang="ts">
// The whole customer record: an identity card with the contact details on one
// side, the products (funnel, warranty, maintenance) on the other. It is the body
// of /cs/customers/:id; the page re-creates it for each customer (:key).
const props = defineProps<{ customerId: string }>();
const emit = defineEmits<{ changed: []; deleted: [] }>();
const customerId = props.customerId;

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();
const { hasPermission, hasAnyModulePermission } = usePermissions();
const { stageById, stageLimitDays, dateIndex, dateOf, daysSince, formatDate, formatDateTime, maintenanceDue, loadAreas, loadPipelines, areaName } = useCs();

const canEdit = computed(() => hasPermission("cs_customers", "edit"));
const canMaintenance = computed(() => hasAnyModulePermission("cs_maintenance"));
const canDoMaintenance = computed(() => hasPermission("cs_maintenance", "complete"));
const canScheduleMaintenance = computed(() => hasPermission("cs_maintenance", "schedule"));
const canDelete = computed(() => hasPermission("cs_customers", "delete"));
const canAssign = computed(() => hasPermission("cs_customers", "assign"));

// ---- Assign the customer to an agent
const assignOpen = ref(false);
function openAssign() {
  assignOpen.value = true;
}
async function onAssigned() {
  await refreshCustomer();
  emit("changed");
}
const canSeeDeals = computed(() => hasAnyModulePermission("crm_deals"));

// Synced through useAsyncData's own `data` (see crm/leads/[id].vue for why).
const { data: customer, refresh: refreshCustomer, status } = useAsyncData<CsCustomer | null>(
  `cs-customer-${customerId}`,
  async () => {
    const { data, error } = await supabase
      .from("customers")
      .select("id, name, company, phone, extra_phones, extra_phone_names, email, address, area_id, converted_from_lead_id, created_at, customer_type, cs_agent_id")
      .eq("id", customerId)
      .maybeSingle();
    if (error) throw error;
    return (data ?? null) as CsCustomer | null;
  },
);
useAsyncData("cs-customer-areas", async () => {
  await Promise.all([loadAreas(true), loadPipelines(true)]);
  return true;
});

const { data: productData, refresh: refreshProductsRaw } = useAsyncData<{
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
// The maintenance history of all of this customer's products (done visits,
// appointments, cancellations), for people allowed to see maintenance.
const { data: logData, refresh: refreshLog } = useAsyncData<CsMaintenanceLog[]>(`cs-customer-${customerId}-mlog`, async () => {
  if (!canMaintenance.value) return [];
  const { data: ps } = await supabase.from("customer_products").select("id").eq("customer_id", customerId);
  const ids = (ps ?? []).map((p) => p.id);
  if (!ids.length) return [];
  const { data, error } = await supabase.from("product_maintenance_log").select("*").in("product_id", ids);
  if (error) throw error;
  return (data ?? []) as CsMaintenanceLog[];
});
// The spare parts used in the done visits, by log entry.
const { data: usedPartsData, refresh: refreshUsedParts } = useAsyncData<{ log_id: string; name: string; quantity: number }[]>(`cs-customer-${customerId}-usedparts`, async () => {
  const ids = (logData.value ?? []).filter((l) => l.kind === "done").map((l) => l.id);
  if (!ids.length) return [];
  const { data } = await supabase.from("maintenance_used_parts").select("log_id, name, quantity").in("log_id", ids);
  return data ?? [];
}, { watch: [logData] });
async function openSignature(path: string) {
  const { data } = await supabase.storage.from("visit-signatures").createSignedUrl(path, 60);
  if (data) window.open(data.signedUrl, "_blank");
}
const usedPartsText = (logId: string) =>
  (usedPartsData.value ?? []).filter((u) => u.log_id === logId).map((u) => (u.quantity > 1 ? `${u.name} × ${u.quantity}` : u.name)).join("، ");
const { data: visitData, refresh: refreshVisits } = useAsyncData<CsMaintenanceVisit[]>(`cs-customer-${customerId}-visits`, async () => {
  if (!canMaintenance.value) return [];
  const { data, error } = await supabase.from("maintenance_visits").select("*").eq("customer_id", customerId);
  if (error) throw error;
  return (data ?? []) as CsMaintenanceVisit[];
});
// Reload this customer's products and tell the list (stage badges, counts).
async function refreshProducts() {
  await Promise.all([refreshProductsRaw(), refreshLog(), refreshContracts(), refreshVisits()]);
  await refreshUsedParts();
  emit("changed");
}
const products = computed(() => productData.value?.products ?? []);

// The customer's contracts (a won deal, or one recorded here); products are grouped under them.
const { data: contractData, refresh: refreshContracts } = useAsyncData<CsContract[]>(`cs-customer-${customerId}-contracts`, async () => {
  const { data, error } = await supabase
    .from("contracts")
    .select("*")
    .eq("customer_id", customerId)
    .order("signed_on", { ascending: false, nullsFirst: false })
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as CsContract[];
});
const contracts = computed(() => contractData.value ?? []);
// Every contract (even an empty one) with its products, then the products that have none.
const groups = computed(() => {
  const list: { contract: CsContract | null; products: CsProduct[] }[] = contracts.value.map((c) => ({
    contract: c,
    products: products.value.filter((p) => p.contract_id === c.id),
  }));
  const loose = products.value.filter((p) => !p.contract_id || !contracts.value.some((c) => c.id === p.contract_id));
  if (loose.length) list.push({ contract: null, products: loose });
  return list;
});

// ---- Contracts
const contractOpen = ref(false);
const editingContract = ref<CsContract | null>(null);
function openAddContract() {
  editingContract.value = null;
  contractOpen.value = true;
}
function openEditContract(c: CsContract) {
  editingContract.value = c;
  contractOpen.value = true;
}
async function onContractSaved() {
  await Promise.all([refreshContracts(), refreshProductsRaw()]);
  emit("changed");
}
const deleteContractOpen = ref(false);
const deleteContractTarget = ref<CsContract | null>(null);
const deletingContract = ref(false);
function askDeleteContract(c: CsContract) {
  deleteContractTarget.value = c;
  deleteContractOpen.value = true;
}
async function confirmDeleteContract() {
  if (!deleteContractTarget.value) return;
  deletingContract.value = true;
  const { error } = await supabase.from("contracts").delete().eq("id", deleteContractTarget.value.id);
  deletingContract.value = false;
  if (error) {
    toast.add({ title: t("cs.profile.contractSaveFailed"), description: error.message, color: "error" });
    return;
  }
  deleteContractOpen.value = false;
  toast.add({ title: t("cs.profile.contractDeleted"), color: "success" });
  await onContractSaved();
}
const contractTitle = (c: CsContract) => c.code || t("cs.profile.contractMissing");
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
const { data: deals } = useAsyncData<LinkedDeal[]>(`cs-customer-${customerId}-deals`, async () => {
  if (!canSeeDeals.value) return [];
  const { data, error } = await supabase
    .from("deals")
    .select("id, title, value, created_at")
    .eq("customer_id", customerId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data ?? [];
});

const mainTab = ref<"main" | "files">("main");
const mainTabs = computed(() => [
  { value: "main", label: t("cs.profile.products") },
  { value: "files", label: t("files.tab") },
]);

const { data: people } = useAsyncData<{ id: string; full_name: string | null; email: string }[]>("cs-customer-people", async () => {
  const { data } = await supabase.from("profiles").select("id, full_name, email");
  return data ?? [];
});
function salesPersonName(id: string | null) {
  const u = id ? people.value?.find((x) => x.id === id) : null;
  return u ? u.full_name || u.email : null;
}

const { data: categories } = useAsyncData<{ id: string; name: string; maintenance_interval_months: number | null }[]>("cs-customer-categories", async () => {
  const { data } = await supabase.from("product_categories").select("id, name, maintenance_interval_months");
  return data ?? [];
});
function categoryName(id: string | null) {
  return id ? (categories.value?.find((c) => c.id === id)?.name ?? "") : "";
}

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
  emit("changed");
}
// ---- Delete the customer: not while it has products (they carry the
// installation and the whole maintenance history). The database refuses too.
const deleteCustomerOpen = ref(false);
const deletingCustomer = ref(false);
function askDeleteCustomer() {
  deleteCustomerOpen.value = true;
}
function closeDeleteCustomer() {
  deleteCustomerOpen.value = false;
}
async function confirmDeleteCustomer() {
  if (!customer.value || products.value.length) return;
  deletingCustomer.value = true;
  const { error } = await supabase.from("customers").delete().eq("id", customerId);
  deletingCustomer.value = false;
  if (error) {
    toast.add({
      title: t("cs.customers.deleteFailed"),
      description: error.message.includes("customer_has_products") ? t("cs.customers.deleteBlocked") : error.message,
      color: "error",
    });
    return;
  }
  deleteCustomerOpen.value = false;
  toast.add({ title: t("cs.customers.deleted"), color: "success" });
  emit("deleted");
}

function openEdit() {
  editOpen.value = true;
}

// ---- Products
const productModalOpen = ref(false);
const editingProduct = ref<CsProduct | null>(null);
const defaultContractId = ref<string | null>(null);
function openAddProduct(contractId: string | null = null) {
  editingProduct.value = null;
  defaultContractId.value = contractId;
  productModalOpen.value = true;
}
function openEditProduct(p: CsProduct) {
  editingProduct.value = p;
  defaultContractId.value = null;
  productModalOpen.value = true;
}

const stageModalOpen = ref(false);
const stageProduct = ref<CsProduct | null>(null);
function openStage(p: CsProduct) {
  stageProduct.value = p;
  stageModalOpen.value = true;
}

// Maintenance can be scheduled once a product reached the completed stage.
const confirmOpen = ref(false);
const confirmProduct = ref<CsProduct | null>(null);
function openConfirm(p: CsProduct) {
  confirmProduct.value = p;
  confirmOpen.value = true;
}
const isConfirmed = (p: CsProduct) => !!p.next_maintenance_at && !!p.maintenance_confirmed_at;

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

// ---- Maintenance history: filter by type, newest first, add an entry.
type HistoryType = "done" | "scheduled" | "cancelled";
const historyFilter = ref<HistoryType | "all">("all");
const typeOfEntry = (e: CsMaintenanceLog): HistoryType | "other" =>
  e.kind === "done" ? "done" : e.kind === "scheduled" || e.kind === "rescheduled" || e.kind === "confirmed" || e.kind === "assigned" ? "scheduled" : e.kind === "cancelled" || e.kind === "declined" ? "cancelled" : "other";
const entryTone = { done: "success", scheduled: "info", cancelled: "error", other: "neutral" } as const;
const entryLabel = (e: CsMaintenanceLog) => {
  if (e.kind === "confirmed") return t("cs.maintenance.evConfirmed");
  if (e.kind === "assigned") return t("cs.maintenance.evAssigned");
  const k = typeOfEntry(e);
  return k === "other" ? t("cs.profile.otherEntry") : t(`cs.maintenance.stat.${k === "cancelled" ? "declined" : k}`);
};
// The date an entry is about: the visit date, or the appointment time.
const entryDate = (e: CsMaintenanceLog) => (e.kind === "done" && e.done_on ? e.done_on : (e.scheduled_for ?? e.happened_at));
// One card per visit (all the products serviced in it) or per single entry made
// outside a visit (older records, or one made from a product's own page).
interface HistoryItem {
  key: string;
  type: HistoryType | "other";
  date: string;
  entries: CsMaintenanceLog[];
  visit: CsMaintenanceVisit | null;
}
const historyItems = computed<HistoryItem[]>(() => {
  const items: HistoryItem[] = [];
  const byVisit = new Map<string, CsMaintenanceLog[]>();
  for (const e of logData.value ?? []) {
    if (e.visit_id) byVisit.set(e.visit_id, [...(byVisit.get(e.visit_id) ?? []), e]);
    else items.push({ key: e.id, type: typeOfEntry(e), date: entryDate(e), entries: [e], visit: null });
  }
  for (const [id, entries] of byVisit) {
    items.push({ key: id, type: typeOfEntry(entries[0]!), date: entryDate(entries[0]!), entries, visit: visitData.value?.find((v) => v.id === id) ?? null });
  }
  return items;
});
const history = computed(() =>
  historyItems.value
    .filter((it) => historyFilter.value === "all" || it.type === historyFilter.value)
    .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime()),
);
const historyCount = (k: HistoryType) => historyItems.value.filter((it) => it.type === k).length;
const itemTotal = (it: HistoryItem) => it.entries.reduce((sum, e) => sum + (e.cost ?? 0), 0);
const productNameOf = (id: string) => products.value.find((p) => p.id === id)?.name ?? "—";
const canAddRecord = computed(
  () => !!products.value.length && (canDoMaintenance.value || canScheduleMaintenance.value || hasPermission("cs_maintenance", "cancel")),
);
// Correct a logged visit: the people who may record that kind of entry may edit it.
const canEditItem = (it: HistoryItem) => {
  const kind = it.entries[0]!.kind;
  if (kind === "done") return canDoMaintenance.value;
  if (kind === "note") return hasPermission("cs_maintenance", "note");
  if (it.type === "cancelled") return hasPermission("cs_maintenance", "cancel");
  return canScheduleMaintenance.value;
};
const editItem = ref<HistoryItem | null>(null);
const editEntryOpen = ref(false);
function openEditItem(it: HistoryItem) {
  editItem.value = it;
  editEntryOpen.value = true;
}
const recordOpen = ref(false);
function openRecord() {
  recordOpen.value = true;
}
function money(v: number | null) {
  return v === null ? null : `${Number(v).toLocaleString("en-US")} ${t("common.currency")}`;
}

// A slim summary above the products: how many are done, how many are late, and
// the soonest maintenance appointment.
const completedCount = computed(() => products.value.filter((p) => !!stageById(p.stage_id)?.is_final).length);
const overdueCount = computed(() => products.value.filter((p) => isOverdue(p)).length);
const nextMaintenance = computed(() => {
  const times = products.value.filter((p) => !p.maintenance_declined_at && p.next_maintenance_at).map((p) => p.next_maintenance_at!);
  return times.sort()[0] ?? null;
});
const nextMaintenanceLate = computed(() => !!nextMaintenance.value && new Date(nextMaintenance.value).getTime() < Date.now());
</script>

<template>
  <div class="@container">
    <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-16">
      <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
    </div>
    <p v-else-if="!customer" class="py-16 text-center text-sm text-muted">{{ t("cs.profile.notFound") }}</p>

    <div v-else class="mx-auto grid w-full max-w-6xl gap-5 @4xl:grid-cols-[21rem_minmax(0,1fr)] @4xl:items-start">
      <!-- ===== Side: who the customer is ===== -->
      <aside class="space-y-4">
        <section class="kords-card p-5 text-center">
          <KAvatar
            :name="isCompanyCustomer(customer) ? null : customerTitle(customer)"
            kind="contact"
            :icon="isCompanyCustomer(customer) ? 'i-lucide-building-2' : undefined"
            size="3xl"
            class="mx-auto"
          />
          <h2 class="mt-3 text-xl font-semibold text-highlighted">{{ customerTitle(customer) }}</h2>
          <p v-if="customerSubtitle(customer)" class="text-sm text-toned">{{ customerSubtitle(customer) }}</p>
          <div class="mt-2.5 flex flex-wrap items-center justify-center gap-1.5">
            <KBadge :label="t(`crm.leads.type.${isCompanyCustomer(customer) ? 'company' : 'individual'}`)" tone="neutral" />
            <KBadge v-if="areaName(customer.area_id)" :label="areaName(customer.area_id)" icon="i-lucide-map-pin" tone="neutral" outlined />
          </div>
          <p class="mt-2 text-xs text-muted">{{ t("cs.profile.customerSince", { date: customerSince }) }}</p>

          <!-- Quick contact -->
          <div class="mt-4 flex items-center justify-center gap-2">
            <UButton
              v-if="customer.phone"
              :to="`tel:${customer.phone}`"
              icon="i-lucide-phone"
              color="neutral"
              variant="outline"
              class="rounded-full"
              :aria-label="t('crm.deals.callContact')"
              :title="t('crm.deals.callContact')"
            />
            <UButton
              v-if="toWhatsAppLink(customer.phone)"
              :to="toWhatsAppLink(customer.phone)!"
              target="_blank"
              rel="noopener noreferrer"
              icon="i-simple-icons-whatsapp"
              color="neutral"
              variant="outline"
              class="rounded-full"
              :aria-label="t('cs.profile.whatsapp')"
              :title="t('cs.profile.whatsapp')"
            />
            <UButton
              v-if="customer.email"
              :to="`mailto:${customer.email}`"
              icon="i-lucide-mail"
              color="neutral"
              variant="outline"
              class="rounded-full"
              :aria-label="t('common.email')"
              :title="t('common.email')"
            />
            <UButton
              :to="`/cs/print/${customerId}`"
              target="_blank"
              icon="i-lucide-printer"
              color="neutral"
              variant="outline"
              class="rounded-full"
              :aria-label="t('cs.print.printCustomer')"
              :title="t('cs.print.printCustomer')"
            />
          </div>

          <div v-if="canEdit || canAssign || canDelete" class="mt-4 space-y-2 border-t border-default pt-4">
            <UButton v-if="canEdit" icon="i-lucide-pencil" :label="t('cs.customers.edit')" block @click="openEdit" />
            <UButton v-if="canAssign" icon="i-lucide-user-plus" color="neutral" variant="outline" :label="t('cs.customers.assign')" block @click="openAssign" />
            <UButton v-if="canDelete" icon="i-lucide-trash" color="error" variant="ghost" :label="t('cs.customers.delete')" block @click="askDeleteCustomer" />
          </div>
        </section>

        <!-- Contact details -->
        <section class="kords-card p-5">
          <h3 class="mb-3 text-sm font-semibold text-highlighted">{{ t("cs.profile.contactInfo") }}</h3>
          <dl class="space-y-3.5 text-sm">
            <div class="flex items-start gap-3">
              <UIcon name="i-lucide-phone" class="mt-0.5 size-4 shrink-0 text-muted" />
              <div class="min-w-0 flex-1">
                <dt class="text-xs text-muted">{{ t("common.phone") }}</dt>
                <dd class="font-medium text-highlighted"><bdi dir="ltr">{{ customer.phone || "—" }}</bdi></dd>
              </div>
              <div v-if="customer.phone" class="flex shrink-0 items-center">
                <UButton :to="`tel:${customer.phone}`" icon="i-lucide-phone" size="xs" color="neutral" variant="ghost" :aria-label="t('crm.deals.callContact')" :title="t('crm.deals.callContact')" />
                <UButton
                  v-if="toWhatsAppLink(customer.phone)"
                  :to="toWhatsAppLink(customer.phone)!"
                  target="_blank"
                  rel="noopener noreferrer"
                  icon="i-simple-icons-whatsapp"
                  size="xs"
                  color="neutral"
                  variant="ghost"
                  class="text-[#25D366]"
                  :aria-label="t('crm.deals.chatOnWhatsApp')"
                  :title="t('crm.deals.chatOnWhatsApp')"
                />
                <UButton icon="i-lucide-copy" size="xs" color="neutral" variant="ghost" :aria-label="t('cs.profile.copy')" @click="copyText(customer.phone)" />
              </div>
            </div>
            <div v-if="customer.extra_phones?.length" class="flex items-start gap-3">
              <UIcon name="i-lucide-contact" class="mt-0.5 size-4 shrink-0 text-muted" />
              <div class="min-w-0 flex-1">
                <dt class="text-xs text-muted">{{ t("common.extraPhones") }}</dt>
                <dd class="mt-1.5 space-y-2">
                  <div
                    v-for="c in toExtraContacts(customer.extra_phones, customer.extra_phone_names)"
                    :key="c.phone"
                    class="flex items-center gap-2.5 rounded-[10px] border border-default p-2"
                  >
                    <KAvatar :name="c.name || null" kind="contact" size="sm" />
                    <div class="min-w-0 flex-1">
                      <div class="truncate text-sm font-medium text-highlighted">{{ c.name || t("cs.profile.contactNoName") }}</div>
                      <bdi dir="ltr" class="text-xs text-muted">{{ c.phone }}</bdi>
                    </div>
                    <div class="flex shrink-0 items-center">
                      <UButton :to="`tel:${c.phone}`" icon="i-lucide-phone" size="xs" color="neutral" variant="ghost" :aria-label="t('crm.deals.callContact')" />
                      <UButton
                        v-if="toWhatsAppLink(c.phone)"
                        :to="toWhatsAppLink(c.phone)!"
                        target="_blank"
                        rel="noopener noreferrer"
                        icon="i-simple-icons-whatsapp"
                        size="xs"
                        color="neutral"
                        variant="ghost"
                        class="text-[#25D366]"
                        :aria-label="t('crm.deals.chatOnWhatsApp')"
                      />
                      <UButton icon="i-lucide-copy" size="xs" color="neutral" variant="ghost" :aria-label="t('cs.profile.copy')" @click="copyText(c.phone)" />
                    </div>
                  </div>
                </dd>
              </div>
            </div>
            <div class="flex items-start gap-3">
              <UIcon name="i-lucide-mail" class="mt-0.5 size-4 shrink-0 text-muted" />
              <div class="min-w-0 flex-1">
                <dt class="text-xs text-muted">{{ t("common.email") }}</dt>
                <dd class="break-all font-medium text-highlighted">{{ customer.email || "—" }}</dd>
              </div>
              <UButton v-if="customer.email" icon="i-lucide-copy" size="xs" color="neutral" variant="ghost" :aria-label="t('cs.profile.copy')" @click="copyText(customer.email)" />
            </div>
            <div class="flex items-start gap-3">
              <UIcon name="i-lucide-map-pin" class="mt-0.5 size-4 shrink-0 text-muted" />
              <div class="min-w-0 flex-1">
                <dt class="flex items-center justify-between gap-2 text-xs text-muted">
                  {{ t("cs.customers.address") }}
                  <a v-if="mapsLink" :href="mapsLink" target="_blank" rel="noopener noreferrer" class="flex items-center gap-1 text-primary hover:underline">
                    <UIcon name="i-lucide-map" class="size-3.5" />{{ t("cs.profile.openMap") }}
                  </a>
                </dt>
                <dd class="whitespace-pre-line font-medium text-highlighted">{{ customer.address || "—" }}</dd>
              </div>
            </div>
            <div class="flex items-start gap-3">
              <UIcon name="i-lucide-user-round-check" class="mt-0.5 size-4 shrink-0 text-muted" />
              <div class="min-w-0 flex-1">
                <dt class="text-xs text-muted">{{ t("cs.customers.agent") }}</dt>
                <dd class="flex items-center gap-1.5 font-medium text-highlighted">
                  <KAvatar v-if="salesPersonName(customer.cs_agent_id ?? null)" :name="salesPersonName(customer.cs_agent_id ?? null)" kind="user" size="2xs" />
                  {{ salesPersonName(customer.cs_agent_id ?? null) || "—" }}
                </dd>
              </div>
            </div>
          </dl>
          <NuxtLink
            v-if="hasPermission('crm_leads', 'view') && customer.converted_from_lead_id"
            :to="`/crm/leads?id=${customer.converted_from_lead_id}`"
            class="mt-4 flex items-center gap-1.5 border-t border-default pt-3 text-sm text-primary hover:underline"
          >
            <UIcon name="i-lucide-user-plus" class="size-4" />{{ t("cs.profile.fromLead") }}
          </NuxtLink>
        </section>

        <!-- CRM context -->
        <section v-if="canSeeDeals && deals?.length" class="kords-card overflow-hidden">
          <h3 class="px-5 pt-5 pb-2 text-sm font-semibold text-highlighted">{{ t("cs.profile.linkedDeals") }}</h3>
          <ul class="divide-y divide-default">
            <li v-for="d in deals" :key="d.id">
              <NuxtLink :to="`/crm/deals/${d.id}`" class="flex flex-wrap items-center justify-between gap-2 px-5 py-3 text-sm transition-colors hover:bg-elevated">
                <span class="font-medium text-highlighted">{{ d.title || "—" }}</span>
                <span v-if="formatMoney(d.value)" class="font-semibold text-success">{{ formatMoney(d.value) }}</span>
              </NuxtLink>
            </li>
          </ul>
        </section>
      </aside>

      <!-- ===== Main: the products ===== -->
      <section class="min-w-0 space-y-4">
        <UTabs v-if="canSeeDeals" v-model="mainTab" :items="mainTabs" value-key="value" variant="link" :content="false" class="kords-pilltabs" />

        <FilesPanel v-if="canSeeDeals && mainTab === 'files'" :customer-id="customerId" />

        <div v-show="mainTab === 'main'" class="space-y-4">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <div class="flex flex-wrap items-center gap-2">
            <h3 class="text-lg font-semibold text-highlighted">{{ t("cs.profile.products") }}</h3>
            <KBadge :label="String(products.length)" tone="neutral" />
            <KBadge v-if="completedCount" :label="t('cs.profile.completedCount', { count: completedCount })" tone="success" />
            <KBadge v-if="overdueCount" :label="t('cs.profile.overdueCount', { count: overdueCount })" tone="error" icon="i-lucide-triangle-alert" />
            <KBadge
              v-if="nextMaintenance"
              :label="`${t('cs.maintenance.next')}: ${formatDateTime(nextMaintenance)}`"
              :tone="nextMaintenanceLate ? 'error' : 'warning'"
              icon="i-lucide-wrench"
            />
          </div>
          <div v-if="canEdit" class="flex flex-wrap items-center gap-2">
            <UButton icon="i-lucide-file-plus" color="neutral" variant="outline" :label="t('cs.profile.addContract')" @click="openAddContract" />
            <UButton icon="i-lucide-plus" :label="t('cs.profile.addProduct')" @click="openAddProduct(null)" />
          </div>
        </div>

        <div v-if="!products.length && !contracts.length" class="kords-card flex flex-col items-center gap-3 p-10 text-center">
          <UIcon name="i-lucide-package-plus" class="size-8 text-muted" />
          <p class="text-sm text-muted">{{ t("cs.profile.noProducts") }}</p>
          <UButton v-if="canEdit" icon="i-lucide-plus" :label="t('cs.profile.addProduct')" @click="openAddProduct(null)" />
        </div>

        <template v-for="g in groups" :key="g.contract?.id ?? 'none'">
          <!-- The contract this group of products belongs to -->
          <div v-if="g.contract" class="kords-card flex flex-wrap items-center justify-between gap-3 p-4">
            <div class="flex min-w-0 items-center gap-3">
              <span class="flex size-9 shrink-0 items-center justify-center rounded-[10px] bg-primary/10 text-primary">
                <UIcon name="i-lucide-file-signature" class="size-5" />
              </span>
              <div class="min-w-0">
                <div class="flex flex-wrap items-center gap-2">
                  <span class="font-semibold text-highlighted"><bdi dir="ltr">{{ contractTitle(g.contract) }}</bdi></span>
                  <KBadge v-if="g.contract.deal_id" :label="t('cs.profile.fromDeal')" tone="success" icon="i-lucide-handshake" />
                  <KBadge :label="t('cs.profile.contractProducts', { count: g.products.length })" tone="neutral" />
                </div>
                <div class="text-xs text-muted">
                  {{ g.contract.signed_on ? formatDate(g.contract.signed_on) : "—" }}
                  <template v-if="g.contract.notes"> · {{ g.contract.notes }}</template>
                </div>
              </div>
            </div>
            <div class="flex flex-wrap items-center gap-1.5">
              <UButton
                v-if="g.contract.deal_id && canSeeDeals"
                :to="`/crm/deals/${g.contract.deal_id}`"
                icon="i-lucide-external-link"
                size="sm"
                color="neutral"
                variant="ghost"
                :label="t('cs.profile.openDeal')"
              />
              <UButton v-if="canEdit" icon="i-lucide-plus" size="sm" color="neutral" variant="soft" :label="t('cs.profile.addProduct')" @click="openAddProduct(g.contract.id)" />
              <UButton v-if="canEdit" icon="i-lucide-pencil" size="sm" color="neutral" variant="outline" :aria-label="t('cs.profile.editContract')" :title="t('cs.profile.editContract')" @click="openEditContract(g.contract)" />
              <UButton
                v-if="canEdit && !g.contract.deal_id && !g.products.length"
                icon="i-lucide-trash"
                size="sm"
                color="error"
                variant="ghost"
                :aria-label="t('cs.profile.deleteContract')"
                @click="askDeleteContract(g.contract)"
              />
            </div>
          </div>
          <h4 v-else class="pt-2 text-sm font-semibold text-muted">{{ t("cs.profile.productsWithoutContract") }}</h4>

          <ProductCard
            v-for="p in g.products"
            :key="p.id"
            :product="p"
            :dates="dates"
            :items="itemsOf(p.id)"
            :category-name="categoryName(p.category_id)"
            :sales-person-name="salesPersonName(p.sales_person_id)"
          >
            <template #actions>
              <div class="flex shrink-0 items-center gap-1">
                <UButton
                  :to="`/cs/print/${customerId}?product=${p.id}`"
                  target="_blank"
                  icon="i-lucide-printer"
                  size="sm"
                  color="neutral"
                  variant="outline"
                  :aria-label="t('cs.print.menu')"
                  :title="t('cs.print.menu')"
                />
                <template v-if="canEdit">
                  <UButton icon="i-lucide-workflow" size="sm" :label="t('cs.installations.updateProgress')" @click="openStage(p)" />
                  <UDropdownMenu :items="productMenu(p)">
                    <UButton icon="i-lucide-ellipsis-vertical" size="sm" color="neutral" variant="outline" :aria-label="t('cs.profile.moreActions')" />
                  </UDropdownMenu>
                </template>
              </div>
            </template>
            <template #extra>
              <!-- Next maintenance -->
              <div
                v-if="canSchedule(p)"
                class="flex flex-wrap items-center justify-between gap-3 rounded-[10px] border p-3"
                :class="maintenanceLate(p) ? 'border-error/40 bg-error/5' : 'border-default bg-muted'"
              >
                <div class="flex min-w-0 items-start gap-2.5">
                  <UIcon name="i-lucide-wrench" class="mt-0.5 size-4 shrink-0" :class="maintenanceLate(p) ? 'text-error' : 'text-muted'" />
                  <div class="min-w-0 text-sm">
                    <div class="text-xs text-muted">{{ t("cs.maintenance.next") }}</div>
                    <div v-if="p.maintenance_declined_at" class="font-medium text-error">{{ t("cs.maintenance.declinedNote") }}</div>
                    <div v-else-if="p.next_maintenance_at" class="flex flex-wrap items-center gap-2 font-medium" :class="maintenanceLate(p) ? 'text-error' : 'text-highlighted'">
                      {{ formatDateTime(p.next_maintenance_at) }}
                      <KBadge
                        :label="isConfirmed(p) ? t('cs.maintenance.confirmedBadge') : t('cs.maintenance.awaitingConfirmation')"
                        :tone="isConfirmed(p) ? 'success' : 'warning'"
                        :outlined="!isConfirmed(p)"
                        :icon="isConfirmed(p) ? 'i-lucide-phone-call' : 'i-lucide-phone-missed'"
                      />
                    </div>
                    <div v-else class="text-muted">{{ t("cs.maintenance.notScheduled") }}</div>
                    <p v-if="isConfirmed(p) && salesPersonName(p.maintenance_technician_id ?? null)" class="mt-0.5 flex items-center gap-1 text-xs text-muted">
                      <UIcon name="i-lucide-hard-hat" class="size-3.5" />{{ t("cs.maintenance.assignedTo", { name: salesPersonName(p.maintenance_technician_id ?? null) ?? "" }) }}
                    </p>
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
                    v-if="canMaintenance"
                    :to="`/cs/maintenance/${p.id}`"
                    icon="i-lucide-clipboard-list"
                    size="sm"
                    color="neutral"
                    variant="ghost"
                    :label="t('cs.maintenance.record')"
                  />
                  <template v-if="!p.maintenance_declined_at">
                    <UButton v-if="p.next_maintenance_at && !isConfirmed(p) && canScheduleMaintenance" icon="i-lucide-phone-call" size="sm" :label="t('cs.maintenance.confirm')" @click="openConfirm(p)" />
                    <UButton
                      v-if="p.next_maintenance_at && isConfirmed(p) && canDoMaintenance"
                      icon="i-lucide-check"
                      size="sm"
                      color="success"
                      variant="soft"
                      :label="t('cs.maintenance.markDone')"
                      @click="openDone(p)"
                    />
                    <UButton
                      v-if="canScheduleMaintenance"
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
        </template>

        <!-- ===== Maintenance history ===== -->
        <section v-if="canMaintenance" class="space-y-3 pt-2">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div class="flex items-center gap-2">
              <h3 class="text-lg font-semibold text-highlighted">{{ t("cs.profile.maintenanceHistory") }}</h3>
              <KBadge :label="String(historyItems.length)" tone="neutral" />
            </div>
            <UButton v-if="canAddRecord" icon="i-lucide-plus" :label="t('cs.profile.addMaintenanceRecord')" @click="openRecord" />
          </div>

          <div class="flex flex-wrap items-center gap-2">
            <button type="button" class="kords-chip" :class="historyFilter === 'all' && 'kords-chip-on'" @click="historyFilter = 'all'">
              {{ t("cs.profile.allTypes") }}
            </button>
            <button
              v-for="k in (['done', 'scheduled', 'cancelled'] as const)"
              :key="k"
              type="button"
              class="kords-chip"
              :class="historyFilter === k && 'kords-chip-on'"
              @click="historyFilter = k"
            >
              {{ t(`cs.maintenance.stat.${k === 'cancelled' ? 'declined' : k}`) }}
              <span class="kords-chip-count">{{ historyCount(k) }}</span>
            </button>
          </div>

          <p v-if="!history.length" class="kords-card p-8 text-center text-sm text-muted">{{ t("cs.profile.noMaintenance") }}</p>
          <ul v-else class="space-y-2">
            <li v-for="it in history" :key="it.key" class="kords-card p-4 text-sm">
              <div class="flex flex-wrap items-center justify-between gap-x-3 gap-y-1">
                <div class="flex flex-wrap items-center gap-2">
                  <KBadge :label="entryLabel(it.entries[0]!)" :tone="entryTone[it.type]" />
                  <span class="font-medium text-highlighted">
                    {{ it.entries[0]!.kind === "done" && it.entries[0]!.done_on ? formatDate(it.entries[0]!.done_on) : formatDateTime(it.date) }}
                  </span>
                  <span v-if="it.entries.length > 1" class="text-xs text-muted">{{ t("cs.profile.contractProducts", { count: it.entries.length }) }}</span>
                </div>
                <div class="flex items-center gap-2">
                  <span v-if="itemTotal(it) && it.entries.length > 1" class="text-xs font-semibold text-muted">
                    {{ t("cs.profile.visitTotal", { amount: money(itemTotal(it)) ?? "" }) }}
                  </span>
                  <KBadge v-if="it.entries.some((e) => e.edited_at)" :label="t('cs.profile.edited')" tone="neutral" outlined />
                  <UButton v-if="canEditItem(it)" icon="i-lucide-pencil" color="neutral" variant="ghost" size="xs" :aria-label="t('cs.profile.editAction')" @click="openEditItem(it)" />
                </div>
              </div>
              <ul class="mt-2 divide-y divide-default">
                <li v-for="e in it.entries" :key="e.id" class="flex flex-wrap items-start justify-between gap-x-3 gap-y-1 py-2">
                  <div class="min-w-0">
                    <div class="font-medium text-highlighted">{{ productNameOf(e.product_id) }}</div>
                    <p v-if="e.note" class="mt-0.5 whitespace-pre-line text-toned">{{ e.note }}</p>
                    <button v-if="e.signature_path" type="button" class="mt-0.5 flex items-center gap-1 text-xs text-primary" @click="openSignature(e.signature_path)">
                      <UIcon name="i-lucide-pen-line" class="size-3.5" />{{ t("cs.maintenance.viewSignature") }}
                    </button>
                    <p v-if="usedPartsText(e.id)" class="mt-0.5 text-xs text-muted">{{ t("cs.maintenance.usedParts", { list: usedPartsText(e.id) }) }}</p>
                    <p v-if="e.visit_cost !== null && e.visit_cost !== undefined && e.kind === 'done'" class="mt-0.5 text-xs text-muted">{{ t("cs.maintenance.visitCostLine", { cost: money(e.visit_cost) ?? "" }) }}</p>
                  </div>
                  <span v-if="money(e.cost)" class="shrink-0 font-semibold text-highlighted">{{ money(e.cost) }}</span>
                </li>
              </ul>
              <p v-if="it.visit?.note" class="mt-1 rounded-[7px] bg-muted p-2 text-xs text-toned">{{ it.visit.note }}</p>
              <div v-if="salesPersonName(it.entries[0]!.created_by)" class="mt-1 text-xs text-muted">{{ salesPersonName(it.entries[0]!.created_by) }}</div>
            </li>
          </ul>
        </section>
        </div>
      </section>
    </div>
  </div>

  <CsAssignModal v-if="customer" v-model:open="assignOpen" :customer-id="customerId" :current-agent-id="customer.cs_agent_id ?? null" @saved="onAssigned" />
  <CustomerFormModal v-model:open="editOpen" :customer="customer" @saved="onCustomerSaved" />
  <ContractFormModal v-model:open="contractOpen" :customer-id="customerId" :contract="editingContract" @saved="onContractSaved" />
  <ProductFormModal
    v-model:open="productModalOpen"
    :customer-id="customerId"
    :product="editingProduct"
    :contracts="contracts"
    :default-contract-id="defaultContractId"
    @saved="refreshProducts"
  />
  <ProductStageModal v-model:open="stageModalOpen" :product="stageProduct" @saved="refreshProducts" />
  <MaintenanceModal v-model:open="maintenanceOpen" :product="maintenanceProduct" @saved="refreshProducts" />
  <MaintenanceConfirmModal v-model:open="confirmOpen" :product="confirmProduct" @saved="refreshProducts" />
  <MaintenanceDoneModal v-model:open="doneOpen" :products="doneProduct ? [doneProduct] : []" @saved="refreshProducts" />
  <MaintenanceEntryEditModal v-model:open="editEntryOpen" :item="editItem" :product-name="productNameOf" @saved="refreshProducts" />
  <MaintenanceRecordModal v-model:open="recordOpen" :customer-id="customerId" :products="products" @saved="refreshProducts" />

  <UModal v-model:open="deleteCustomerOpen" :title="t('cs.customers.deleteTitle')">
    <template #body>
      <div class="space-y-4">
        <UAlert
          v-if="products.length"
          icon="i-lucide-ban"
          color="warning"
          variant="subtle"
          :title="t('cs.customers.deleteBlockedTitle', { count: products.length })"
          :description="t('cs.customers.deleteBlocked')"
        />
        <p v-else class="text-sm text-muted">{{ t("cs.customers.deleteConfirm", { name: customer ? customerTitle(customer) : "" }) }}</p>
        <div class="flex gap-2">
          <UButton color="neutral" variant="outline" :label="t('common.cancel')" class="flex-1 justify-center" @click="closeDeleteCustomer" />
          <UButton
            v-if="!products.length"
            color="error"
            :label="t('common.delete')"
            :loading="deletingCustomer"
            class="flex-1 justify-center"
            @click="confirmDeleteCustomer"
          />
        </div>
      </div>
    </template>
  </UModal>

  <KDeleteConfirmation
    v-model:open="deleteContractOpen"
    :title="t('cs.profile.contractDeleteTitle')"
    :message="t('cs.profile.contractDeleteConfirm', { name: deleteContractTarget ? contractTitle(deleteContractTarget) : '' })"
    :loading="deletingContract"
    @confirm="confirmDeleteContract"
  />

  <KDeleteConfirmation
    v-model:open="deleteOpen"
    :title="t('cs.profile.deleteProduct')"
    :message="t('cs.profile.deleteConfirm', { name: deleteTarget?.name ?? '' })"
    :loading="deleting"
    @confirm="confirmDelete"
  />
</template>
