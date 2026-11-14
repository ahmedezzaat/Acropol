<script setup lang="ts">
// One contract: everything entered on it (the customer, the deal, the agent, the value, the notes, the file) and
// the products it covers with their warranty, payment and maintenance details. The customer's other contracts are
// not here: they are on the contracts list and on the customer's page.
definePageMeta({ layout: "dashboard", crmPermission: { module: "crm_customers" } });
useHead({ htmlAttrs: { class: "carbon kords" } });

const route = useRoute();
const contractId = route.params.id as string;
const supabase = useSupabaseClient();
const toast = useToast();
const { t, locale } = useI18n();
const { waLink } = useWaLink();
const { formatDate } = useCs();
const { hasAnyModulePermission, hasPermission } = usePermissions();

interface ContractFull {
  id: string; code: string; signed_on: string | null; value: number | null; notes: string | null; file_name: string | null; file_path: string | null;
  customer_id: string; deal_id: string | null; created_by: string | null; created_at: string; sales_person_id: string | null;
  customer: { id: string; name: string; company: string | null; phone: string | null; extra_phones: string[] | null; extra_phone_names: string[] | null; email: string | null; address: string | null; area_id: string | null; cs_pending: boolean; notes: string | null; category_id: string | null } | null;
  deal: { id: string; title: string; value: number | null; assigned_to: string | null; stage: { name: string; system_key: string | null } | null } | null;
}

const { data: contract, status, refresh: refreshContract } = await useAsyncData<ContractFull | null>(`crm-contract-${contractId}`, async () => {
  const { data, error } = await supabase
    .from("contracts")
    .select("id, code, signed_on, value, notes, file_name, file_path, customer_id, deal_id, created_by, created_at, sales_person_id, customer:customers(id, name, company, phone, extra_phones, extra_phone_names, email, address, area_id, cs_pending, notes, category_id), deal:deals(id, title, value, assigned_to, stage:pipeline_stages(name, system_key))")
    .eq("id", contractId)
    .maybeSingle();
  if (error) throw error;
  return data as unknown as ContractFull | null;
});

const { data: people } = await useAsyncData<Record<string, string>>(`crm-contract-${contractId}-people`, async () => {
  const { data } = await supabase.from("profiles").select("id, full_name, email");
  return Object.fromEntries((data ?? []).map((p) => [p.id as string, (p.full_name as string) || (p.email as string)]));
});
const { data: categories } = await useAsyncData<Record<string, string>>(`crm-contract-${contractId}-cats`, async () => {
  const { data } = await supabase.from("product_categories").select("id, name");
  return Object.fromEntries((data ?? []).map((c) => [c.id as string, c.name as string]));
});
const personName = (id: string | null) => (id ? (people.value?.[id] ?? null) : null);

// the products of this contract (by its id, or by its code on older records)
const { data: products } = await useAsyncData<CsProduct[]>(`crm-contract-${contractId}-products`, async () => {
  if (!contract.value) return [];
  const { data } = await supabase.from("customer_products").select("*").eq("customer_id", contract.value.customer_id).order("created_at", { ascending: false });
  return ((data ?? []) as CsProduct[]).filter((p) => (p.contract_id ? p.contract_id === contractId : !!p.contract_code && p.contract_code === contract.value!.code));
});
// the contract is named after what the customer bought
const contractTitle = computed(() => {
  const names = (products.value ?? []).filter((p) => p.name?.trim()).map((p) => (p.quantity > 1 ? `${p.name.trim()} × ${p.quantity}` : p.name.trim()));
  return names.join("، ") || contract.value?.deal?.title || (contract.value ? `#${contract.value.code}` : "");
});
// the contract's own sales person, else the ones recorded on its products, else its deal's agent
const agentIds = computed(() => {
  if (contract.value?.sales_person_id) return [contract.value.sales_person_id];
  const ids = [...new Set((products.value ?? []).map((p) => p.sales_person_id).filter((x): x is string => !!x))];
  return ids.length ? ids : contract.value?.deal?.assigned_to ? [contract.value.deal.assigned_to] : [];
});
const agents = computed(() => agentIds.value.map((id) => personName(id)).filter((x): x is string => !!x));

const money = (v: number | null) => (v === null || v === undefined ? "—" : formatReportMoney(v, t("common.currency")));
const warrantyColor = { in_warranty: "success", out_of_warranty: "neutral" } as const;
const paymentColor = { paid: "success", unpaid: "error" } as const;
// editing a contract needs the CRM edit permission on contracts
const canEdit = computed(() => hasPermission("crm_customers", "edit"));
const editOpen = ref(false);
const customerEditOpen = ref(false);
const { loadCategories, categoryName } = useCustomerCategories();
await loadCategories();
// a customer made from this contract is pending until someone sends it to Customer Service
const pushOpen = ref(false);
const canPushToCs = computed(() => hasPermission("crm_customers", "push_to_cs"));
// the deals already used by this customer's other contracts
const { data: takenDealIds, refresh: refreshTaken } = await useAsyncData<string[]>(`crm-contract-${contractId}-taken`, async () => {
  if (!contract.value) return [];
  const { data } = await supabase.from("contracts").select("deal_id").eq("customer_id", contract.value.customer_id).neq("id", contractId).not("deal_id", "is", null);
  return (data ?? []).map((c) => c.deal_id as string);
});
async function onCustomerEdited() {
  await refreshContract();
}
async function onEdited() {
  await Promise.all([refreshContract(), refreshTaken(), refreshNuxtData(`crm-contract-${contractId}-products`)]);
}
const canSeeFiles = computed(() => hasAnyModulePermission("crm_deals"));

async function downloadFile() {
  if (!contract.value?.file_path) return;
  const { data, error } = await supabase.storage.from("contract-files").createSignedUrl(contract.value.file_path, 60, { download: contract.value.file_name ?? true });
  if (error || !data) {
    toast.add({ title: t("crm.contracts.fileFailed"), description: error?.message, color: "error" });
    return;
  }
  const a = document.createElement("a");
  a.href = data.signedUrl;
  a.click();
}

// ---- the contract file: upload it here (it replaces the contract's file), and show the contract uploaded on the deal
const fileInput = ref<HTMLInputElement | null>(null);
const uploading = ref(false);
const MAX_FILE = 25 * 1024 * 1024;
async function onPickFile(e: Event) {
  const input = e.target as HTMLInputElement;
  const f = input.files?.[0];
  input.value = "";
  if (!f || !contract.value) return;
  if (f.size > MAX_FILE) {
    toast.add({ title: t("crm.contracts.fileTooBig"), color: "error" });
    return;
  }
  uploading.value = true;
  const previous = contract.value.file_path;
  const path = `${contract.value.id}/${Date.now()}-${f.name}`;
  const { error: upError } = await supabase.storage.from("contract-files").upload(path, f);
  if (upError) {
    uploading.value = false;
    toast.add({ title: t("crm.contracts.fileFailed"), description: upError.message, color: "error" });
    return;
  }
  const { error } = await supabase.rpc("crm_update_contract", { p_contract_id: contract.value.id, p_patch: { file_path: path, file_name: f.name } as never });
  if (error) {
    await supabase.storage.from("contract-files").remove([path]);
    uploading.value = false;
    toast.add({ title: t("crm.contracts.editFailed"), description: error.message, color: "error" });
    return;
  }
  // the replaced file is not needed any more
  if (previous) await supabase.storage.from("contract-files").remove([previous]);
  uploading.value = false;
  toast.add({ title: t("crm.contracts.edited"), color: "success" });
  await refreshContract();
}
interface DealFile { id: string; file_name: string; storage_path: string; created_at: string }
const { data: dealContractFiles } = await useAsyncData<DealFile[]>(`crm-contract-${contractId}-dealfiles`, async () => {
  const dealId = contract.value?.deal_id;
  if (!dealId || !canSeeFiles.value) return [];
  const { data } = await supabase.from("deal_attachments").select("id, file_name, storage_path, created_at").eq("deal_id", dealId).eq("kind", "contract").order("created_at", { ascending: false });
  return (data ?? []) as DealFile[];
});
// a file already kept on the contract itself is not listed twice
const dealFilesShown = computed(() => (dealContractFiles.value ?? []).filter((f) => f.file_name !== contract.value?.file_name));
async function openDealFile(f: DealFile) {
  const { data, error } = await supabase.storage.from("deal-attachments").createSignedUrl(f.storage_path, 60, { download: f.file_name });
  if (error || !data) {
    toast.add({ title: t("crm.contracts.fileFailed"), description: error?.message, color: "error" });
    return;
  }
  const a = document.createElement("a");
  a.href = data.signedUrl;
  a.click();
}

const customerName = computed(() => {
  const c = contract.value?.customer;
  return c ? [c.company, c.name].filter(Boolean).join(" · ") : "—";
});
const extraPhones = computed(() => (contract.value?.customer?.extra_phones ?? []).map((phone, i) => ({ phone, name: contract.value?.customer?.extra_phone_names?.[i] ?? "" })));
</script>

<template>
  <UDashboardPanel :ui="{ body: 'kords-canvas !p-3 sm:!p-6' }">
    <template #header>
      <UDashboardNavbar :title="contract ? contractTitle : t('crm.contracts.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton to="/crm/contracts" icon="i-lucide-arrow-right" color="neutral" variant="ghost" :label="t('crm.customers.backToContracts')" />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-16"><UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" /></div>
      <p v-else-if="!contract" class="kords-card mx-auto max-w-xl p-8 text-center text-sm text-muted">{{ t("crm.contracts.notFound") }}</p>

      <div v-else class="mx-auto w-full max-w-6xl space-y-5">
        <!-- ===== This contract ===== -->
        <section class="kords-card kords-card-dark p-4 sm:p-5">
          <div class="flex flex-wrap items-center justify-between gap-4">
            <div class="min-w-0">
              <p class="flex items-center gap-2 text-sm text-toned"><UIcon name="i-lucide-file-signature" class="size-4" />{{ t("crm.contracts.contractWord") }} <bdi dir="ltr">#{{ contract.code }}</bdi></p>
              <h2 class="text-xl font-semibold text-highlighted sm:text-2xl">{{ contractTitle }}</h2>
              <p class="mt-1 text-sm text-toned">{{ t("crm.contracts.signedOn") }}: {{ contract.signed_on ? formatDate(contract.signed_on) : "—" }}</p>
            </div>
            <div class="text-end">
              <p class="text-xs text-toned">{{ t("crm.contracts.value") }}</p>
              <p class="text-2xl font-semibold text-success">{{ money(contract.value) }}</p>
            </div>
          </div>
          <div class="mt-4 flex flex-wrap items-center gap-2">
            <UButton v-if="contract.file_path" icon="i-lucide-download" color="neutral" variant="outline" :label="contract.file_name || t('crm.contracts.file')" @click="downloadFile" />
            <UButton v-if="contract.deal_id && canSeeFiles" :to="`/crm/deals/${contract.deal_id}`" icon="i-lucide-handshake" color="neutral" variant="outline" :label="t('crm.contracts.openDeal')" />
            <UButton v-if="contract.customer?.phone" :to="`tel:${contract.customer.phone}`" icon="i-lucide-phone" color="neutral" variant="outline" :label="t('crm.deals.callContact')" />
            <UButton v-if="contract.customer && waLink(contract.customer.phone)" :to="waLink(contract.customer.phone)!" icon="i-simple-icons-whatsapp" color="neutral" variant="outline" :label="t('cs.profile.whatsapp')" />
          </div>
        </section>

        <div class="grid items-start gap-5 lg:grid-cols-[22rem_minmax(0,1fr)]">
          <!-- ===== Who and what it belongs to ===== -->
          <UPageCard :title="t('crm.contracts.customerCard')">
            <div v-if="contract.customer?.cs_pending" class="mb-4 space-y-2 rounded-[10px] bg-warning/10 p-3 text-sm">
              <p class="flex items-center gap-1.5 font-medium text-warning"><UIcon name="i-lucide-clock" class="size-4" />{{ t("crm.contracts.csPending") }}</p>
              <p class="text-xs text-toned">{{ t("crm.contracts.csPendingHint") }}</p>
              <UButton v-if="canPushToCs" size="sm" icon="i-lucide-send" :label="t('crm.contracts.createCustomerAndSend')" block @click="pushOpen = true" />
            </div>
            <dl class="space-y-4 text-sm">
              <div>
                <dt class="text-xs text-muted">{{ t("crm.contracts.customer") }}</dt>
                <dd class="flex items-center justify-between gap-2">
                  <NuxtLink :to="`/crm/customers/${contract.customer_id}`" class="font-medium text-primary hover:underline">{{ customerName }}</NuxtLink>
                  <UButton v-if="canEdit && contract.customer" icon="i-lucide-pencil" size="xs" color="neutral" variant="outline" :label="t('crm.contracts.editCustomer')" @click="customerEditOpen = true" />
                </dd>
              </div>
              <div v-if="categoryName(contract.customer?.category_id)">
                <dt class="text-xs text-muted">{{ t("crm.leads.category") }}</dt>
                <dd>{{ categoryName(contract.customer?.category_id) }}</dd>
              </div>
              <div v-if="contract.customer?.phone">
                <dt class="text-xs text-muted">{{ t("common.phone") }}</dt>
                <dd dir="ltr" class="text-start">{{ contract.customer.phone }}</dd>
              </div>
              <div v-if="extraPhones.length">
                <dt class="text-xs text-muted">{{ t("common.extraPhones") }}</dt>
                <dd v-for="e in extraPhones" :key="e.phone" class="flex items-center gap-2"><bdi dir="ltr">{{ e.phone }}</bdi><span v-if="e.name" class="text-muted">· {{ e.name }}</span></dd>
              </div>
              <div v-if="contract.customer?.email">
                <dt class="text-xs text-muted">{{ t("common.email") }}</dt>
                <dd dir="ltr" class="text-start">{{ contract.customer.email }}</dd>
              </div>
              <div v-if="contract.customer?.address">
                <dt class="text-xs text-muted">{{ t("crm.customers.address") }}</dt>
                <dd class="whitespace-pre-line">{{ contract.customer.address }}</dd>
              </div>
              <div v-if="contract.customer?.notes">
                <dt class="text-xs text-muted">{{ t("crm.customers.notes") }}</dt>
                <dd class="whitespace-pre-line">{{ contract.customer.notes }}</dd>
              </div>
            </dl>
          </UPageCard>

          <div class="min-w-0 space-y-5">
            <!-- ===== The contract: every field entered on it ===== -->
            <section class="space-y-3">
              <div class="flex flex-wrap items-center justify-between gap-2">
                <h3 class="flex items-center gap-2 text-sm font-semibold text-highlighted"><UIcon name="i-lucide-file-signature" class="size-4 text-muted" />{{ t("crm.contracts.contractSection") }}</h3>
                <UButton v-if="canEdit" size="sm" icon="i-lucide-pencil" :label="t('crm.contracts.edit')" @click="editOpen = true" />
              </div>
              <article class="kords-card p-4">
                <dl class="grid gap-x-6 gap-y-4 text-sm sm:grid-cols-2">
                  <div><dt class="text-xs text-muted">{{ t("crm.contracts.code") }}</dt><dd><bdi dir="ltr">#{{ contract.code }}</bdi></dd></div>
                  <div><dt class="text-xs text-muted">{{ t("crm.contracts.signedOn") }}</dt><dd>{{ contract.signed_on ? formatDate(contract.signed_on) : "—" }}</dd></div>
                  <div><dt class="text-xs text-muted">{{ t("crm.contracts.value") }}</dt><dd class="font-semibold text-success">{{ money(contract.value) }}</dd></div>
                  <div><dt class="text-xs text-muted">{{ t("crm.contracts.agent") }}</dt><dd>{{ agents.join("، ") || "—" }}</dd></div>
                  <div>
                    <dt class="text-xs text-muted">{{ t("crm.contracts.deal") }}</dt>
                    <dd>
                      <NuxtLink v-if="contract.deal" :to="`/crm/deals/${contract.deal.id}`" class="text-primary hover:underline">{{ contract.deal.title }}</NuxtLink>
                      <UBadge v-if="contract.deal?.stage" :label="contract.deal.stage.name" color="neutral" variant="subtle" size="sm" class="cds-tag ms-2" />
                      <span v-else-if="!contract.deal" class="text-muted">—</span>
                    </dd>
                  </div>
                  <div class="sm:col-span-2">
                    <dt class="text-xs text-muted">{{ t("crm.contracts.file") }}</dt>
                    <dd class="flex flex-wrap items-center gap-2">
                      <button v-if="contract.file_path" type="button" class="inline-flex items-center gap-1.5 text-primary hover:underline" @click="downloadFile"><UIcon name="i-lucide-paperclip" class="size-4" /><bdi>{{ contract.file_name || t("crm.contracts.file") }}</bdi></button>
                      <span v-else class="text-muted">—</span>
                      <template v-if="canEdit">
                        <UButton size="xs" color="neutral" variant="outline" icon="i-lucide-upload" :label="contract.file_path ? t('crm.contracts.replaceFileBtn') : t('crm.contracts.uploadFile')" :loading="uploading" @click="fileInput?.click()" />
                        <input ref="fileInput" type="file" class="hidden" @change="onPickFile" />
                      </template>
                    </dd>
                    <ul v-if="dealFilesShown.length" class="mt-2 space-y-1.5">
                      <li v-for="f in dealFilesShown" :key="f.id" class="flex flex-wrap items-center gap-2 rounded-[10px] bg-muted px-3 py-2">
                        <UIcon name="i-lucide-file-signature" class="size-4 shrink-0 text-primary" />
                        <button type="button" class="min-w-0 flex-1 truncate text-start hover:underline" @click="openDealFile(f)"><bdi>{{ f.file_name }}</bdi></button>
                        <UBadge :label="t('crm.contracts.fromDeal')" color="neutral" variant="subtle" size="sm" class="cds-tag" />
                        <UButton icon="i-lucide-download" size="xs" color="neutral" variant="ghost" :aria-label="t('files.open')" @click="openDealFile(f)" />
                      </li>
                    </ul>
                  </div>
                  <div><dt class="text-xs text-muted">{{ t("crm.customers.enteredBy") }}</dt><dd>{{ personName(contract.created_by) || "—" }} <span class="block text-xs text-muted">{{ formatDMYTime(contract.created_at, locale) }}</span></dd></div>
                  <div class="sm:col-span-2"><dt class="text-xs text-muted">{{ t("crm.customers.notes") }}</dt><dd class="whitespace-pre-line">{{ contract.notes || "—" }}</dd></div>
                </dl>
              </article>
            </section>

            <!-- ===== Products on this contract ===== -->
            <section class="space-y-3">
              <h3 class="flex items-center gap-2 text-sm font-semibold text-highlighted">
                {{ t("crm.contracts.products") }}
                <UBadge :label="String(products?.length ?? 0)" color="neutral" variant="subtle" size="sm" class="cds-tag" />
              </h3>
              <p v-if="!products?.length" class="kords-card p-4 text-sm text-muted">{{ t("crm.customers.noContractProducts") }}</p>
              <article v-for="p in products" :key="p.id" class="kords-card p-4">
                <div class="flex flex-wrap items-start justify-between gap-2">
                  <p class="font-medium text-highlighted">{{ p.name }}<span v-if="p.quantity > 1" class="ms-1 text-xs font-normal text-muted">× {{ p.quantity }}</span></p>
                  <span class="flex flex-wrap items-center gap-1.5">
                    <UBadge v-if="p.warranty_status" :label="t(`cs.profile.warranty.${p.warranty_status}`)" icon="i-lucide-shield" :color="warrantyColor[p.warranty_status as keyof typeof warrantyColor] ?? 'neutral'" variant="subtle" size="sm" class="cds-tag" />
                    <UBadge v-if="p.payment_status" :label="t(`cs.profile.payment.${p.payment_status}`)" icon="i-lucide-banknote" :color="paymentColor[p.payment_status as keyof typeof paymentColor] ?? 'neutral'" variant="subtle" size="sm" class="cds-tag" />
                  </span>
                </div>
                <dl class="mt-3 grid gap-x-6 gap-y-2 text-sm sm:grid-cols-2">
                  <div v-if="p.category_id && categories?.[p.category_id]"><dt class="text-xs text-muted">{{ t("crm.customers.category") }}</dt><dd>{{ categories[p.category_id] }}</dd></div>
                  <div><dt class="text-xs text-muted">{{ t("crm.contracts.agent") }}</dt><dd>{{ personName(p.sales_person_id) || "—" }}</dd></div>
                  <div v-if="p.operation_date"><dt class="text-xs text-muted">{{ t("crm.customers.operationDate") }}</dt><dd>{{ formatDate(p.operation_date) }}</dd></div>
                  <div v-if="p.last_maintenance_on"><dt class="text-xs text-muted">{{ t("crm.contracts.lastMaintenance") }}</dt><dd>{{ formatDate(p.last_maintenance_on) }}</dd></div>
                  <div v-if="p.next_maintenance_at"><dt class="text-xs text-muted">{{ t("crm.customers.nextMaintenance") }}</dt><dd>{{ formatDate(p.next_maintenance_at) }}</dd></div>
                  <div v-if="p.warranty_details" class="sm:col-span-2"><dt class="text-xs text-muted">{{ t("crm.customers.warrantyDetails") }}</dt><dd class="whitespace-pre-line">{{ p.warranty_details }}</dd></div>
                  <div v-if="p.next_maintenance_note" class="sm:col-span-2"><dt class="text-xs text-muted">{{ t("crm.contracts.nextMaintenanceNote") }}</dt><dd class="whitespace-pre-line">{{ p.next_maintenance_note }}</dd></div>
                  <div v-if="p.notes" class="sm:col-span-2"><dt class="text-xs text-muted">{{ t("crm.customers.notes") }}</dt><dd class="whitespace-pre-line">{{ p.notes }}</dd></div>
                </dl>
              </article>
            </section>

          </div>
        </div>
      </div>
    </template>
  </UDashboardPanel>

  <PushToCsModal v-if="contract?.customer?.cs_pending && canPushToCs" v-model:open="pushOpen" :customer-id="contract.customer_id" :customer-name="customerName" @pushed="refreshContract" />
  <CrmCustomerEditModal v-if="contract?.customer && canEdit" v-model:open="customerEditOpen" :customer="contract.customer" @saved="onCustomerEdited" />
  <CrmContractEditModal v-if="contract && canEdit" v-model:open="editOpen" :contract="{ ...contract, sales_person_id: agentIds.length === 1 ? agentIds[0]! : null }" :taken-deal-ids="takenDealIds ?? []" @saved="onEdited" />
</template>
