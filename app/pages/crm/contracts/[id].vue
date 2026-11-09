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
  customer_id: string; deal_id: string | null; created_by: string | null; created_at: string;
  customer: { id: string; name: string; company: string | null; phone: string | null; extra_phones: string[] | null; extra_phone_names: string[] | null; email: string | null; address: string | null } | null;
  deal: { id: string; title: string; value: number | null; assigned_to: string | null; stage: { name: string; system_key: string | null } | null } | null;
}

const { data: contract, status, refresh: refreshContract } = await useAsyncData<ContractFull | null>(`crm-contract-${contractId}`, async () => {
  const { data, error } = await supabase
    .from("contracts")
    .select("id, code, signed_on, value, notes, file_name, file_path, customer_id, deal_id, created_by, created_at, customer:customers(id, name, company, phone, extra_phones, extra_phone_names, email, address), deal:deals(id, title, value, assigned_to, stage:pipeline_stages(name, system_key))")
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
const agents = computed(() => [...new Set((products.value ?? []).map((p) => personName(p.sales_person_id)).filter((x): x is string => !!x))]);

const money = (v: number | null) => (v === null || v === undefined ? "—" : formatReportMoney(v, t("common.currency")));
const warrantyColor = { in_warranty: "success", out_of_warranty: "neutral" } as const;
const paymentColor = { paid: "success", unpaid: "error" } as const;
// editing a contract needs the CRM edit permission on contracts
const canEdit = computed(() => hasPermission("crm_customers", "edit"));
const editOpen = ref(false);
// the deals already used by this customer's other contracts
const { data: takenDealIds, refresh: refreshTaken } = await useAsyncData<string[]>(`crm-contract-${contractId}-taken`, async () => {
  if (!contract.value) return [];
  const { data } = await supabase.from("contracts").select("deal_id").eq("customer_id", contract.value.customer_id).neq("id", contractId).not("deal_id", "is", null);
  return (data ?? []).map((c) => c.deal_id as string);
});
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
            <UButton v-if="canEdit" icon="i-lucide-pencil" :label="t('crm.contracts.edit')" @click="editOpen = true" />
            <UButton v-if="contract.file_path" icon="i-lucide-download" color="neutral" variant="outline" :label="contract.file_name || t('crm.contracts.file')" @click="downloadFile" />
            <UButton v-if="contract.customer?.phone" :to="`tel:${contract.customer.phone}`" icon="i-lucide-phone" color="neutral" variant="outline" :label="t('crm.deals.callContact')" />
            <UButton v-if="contract.customer && waLink(contract.customer.phone)" :to="waLink(contract.customer.phone)!" icon="i-simple-icons-whatsapp" color="neutral" variant="outline" :label="t('cs.profile.whatsapp')" />
          </div>
        </section>

        <div class="grid items-start gap-5 lg:grid-cols-[22rem_minmax(0,1fr)]">
          <!-- ===== Who and what it belongs to ===== -->
          <UPageCard :title="t('crm.contracts.dataTitle')">
            <dl class="space-y-4 text-sm">
              <div>
                <dt class="text-xs text-muted">{{ t("crm.contracts.customer") }}</dt>
                <dd><NuxtLink :to="`/crm/customers/${contract.customer_id}`" class="font-medium text-primary hover:underline">{{ customerName }}</NuxtLink></dd>
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
              <div>
                <dt class="text-xs text-muted">{{ t("crm.contracts.agent") }}</dt>
                <dd>{{ agents.join("، ") || "—" }}</dd>
              </div>
              <div>
                <dt class="text-xs text-muted">{{ t("crm.contracts.deal") }}</dt>
                <dd>
                  <NuxtLink v-if="contract.deal" :to="`/crm/deals/${contract.deal.id}`" class="text-primary hover:underline">{{ contract.deal.title }}</NuxtLink>
                  <UBadge v-if="contract.deal?.stage" :label="contract.deal.stage.name" color="neutral" variant="subtle" size="sm" class="cds-tag ms-2" />
                  <span v-else-if="!contract.deal" class="text-muted">—</span>
                </dd>
              </div>
              <div>
                <dt class="text-xs text-muted">{{ t("crm.customers.enteredBy") }}</dt>
                <dd>{{ personName(contract.created_by) || "—" }} <span class="block text-xs text-muted">{{ formatDMYTime(contract.created_at, locale) }}</span></dd>
              </div>
              <div v-if="contract.notes">
                <dt class="text-xs text-muted">{{ t("crm.customers.notes") }}</dt>
                <dd class="whitespace-pre-line">{{ contract.notes }}</dd>
              </div>
            </dl>
          </UPageCard>

          <div class="min-w-0 space-y-5">
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

            <!-- ===== Files of the deal this contract came from ===== -->
            <FilesPanel v-if="canSeeFiles && contract.deal_id" :deal-id="contract.deal_id" />
          </div>
        </div>
      </div>
    </template>
  </UDashboardPanel>

  <CrmContractEditModal v-if="contract && canEdit" v-model:open="editOpen" :contract="contract" :taken-deal-ids="takenDealIds ?? []" @saved="onEdited" />
</template>
