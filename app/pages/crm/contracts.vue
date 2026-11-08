<script setup lang="ts">
// Contracts (العقود): the contracts generated when deals are won, newest first. Each opens its customer
// or its deal. (Customers themselves are managed in Customer Service.)
definePageMeta({ layout: "dashboard", crmPermission: { module: "crm_customers" } });
useHead({ htmlAttrs: { class: "carbon kords" } });

const supabase = useSupabaseClient();
const { t } = useI18n();

interface ContractRow {
  id: string;
  code: string | null;
  signed_on: string | null;
  notes: string | null;
  created_at: string;
  customer_id: string;
  deal_id: string | null;
  customer: { id: string; name: string; company: string | null; phone: string | null; extra_phones: string[] | null; extra_phone_names: string[] | null } | null;
  deal: { id: string; title: string } | null;
}

const { data: contracts, status } = await useAsyncData<ContractRow[]>("crm-contracts", async () =>
  fetchAll<ContractRow>((from, to) =>
    supabase
      .from("contracts")
      .select("id, code, signed_on, notes, created_at, customer_id, deal_id, customer:customers(id, name, company, phone, extra_phones, extra_phone_names), deal:deals(id, title)")
      .order("created_at", { ascending: false })
      .order("id")
      .range(from, to) as never,
  ),
);

// ---- Search and order
const search = ref("");
type SortMode = "created" | "signed";
const sortMode = ref<SortMode>("created");
const sortItems = computed(() => [
  { label: t("crm.contracts.sortCreated"), value: "created" },
  { label: t("crm.contracts.sortSigned"), value: "signed" },
]);
const time = (v: string | null) => (v ? new Date(v).getTime() : 0);
const rows = computed(() => {
  const q = search.value.trim().toLowerCase();
  const list = (contracts.value ?? []).filter((c) => {
    if (!q) return true;
    const cu = c.customer;
    return (
      (c.code ?? "").toLowerCase().includes(q) ||
      `${cu?.name ?? ""} ${cu?.company ?? ""} ${c.deal?.title ?? ""} ${c.notes ?? ""}`.toLowerCase().includes(q) ||
      anyPhoneMatches([cu?.phone, ...(cu?.extra_phones ?? [])], search.value) ||
      extraNamesMatch(cu?.extra_phone_names, search.value)
    );
  });
  // newest first, by when the contract was generated (or by its signing date)
  return [...list].sort((a, b) => (sortMode.value === "signed" ? time(b.signed_on) - time(a.signed_on) : time(b.created_at) - time(a.created_at)));
});

const pagination = reactive({ page: 1, size: 50 });
watch([search, sortMode], () => (pagination.page = 1));
const pageCount = computed(() => Math.max(1, Math.ceil(rows.value.length / pagination.size)));
const paged = computed(() => rows.value.slice((pagination.page - 1) * pagination.size, pagination.page * pagination.size));
const customerTitle = (c: ContractRow) => c.customer?.company || c.customer?.name || "—";
</script>

<template>
  <UDashboardPanel :ui="{ body: 'kords-canvas' }">
    <template #header>
      <KPageHeader :title="t('crm.contracts.title')" :count="contracts?.length ?? 0" />
      <div class="kords-filterbar flex flex-wrap items-center gap-2 border-b border-default px-4 py-3 sm:px-6">
        <UInput v-model="search" icon="i-lucide-search" :placeholder="t('crm.contracts.search')" class="min-w-0 flex-1 basis-60 lg:max-w-96 lg:flex-none" />
        <USelect v-model="sortMode" :items="sortItems" value-key="value" icon="i-lucide-arrow-down-wide-narrow" class="w-48" />
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
          <NuxtLink v-for="c in paged" :key="c.id" :to="`/crm/customers/${c.customer_id}`" class="kords-kcard block border border-default bg-default p-3">
            <div class="flex items-start justify-between gap-2">
              <span class="font-semibold text-highlighted" dir="ltr">{{ c.code || "—" }}</span>
              <span class="shrink-0 text-xs text-muted">{{ formatDMY(c.created_at) }}</span>
            </div>
            <p class="mt-1 truncate text-sm text-toned">{{ customerTitle(c) }}</p>
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
                <th class="px-4 py-3 text-start font-medium">{{ t("crm.contracts.deal") }}</th>
                <th class="px-4 py-3 text-start font-medium">{{ t("crm.contracts.signedOn") }}</th>
                <th class="px-4 py-3 text-start font-medium">{{ t("crm.contracts.generatedOn") }}</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-default">
              <tr v-for="c in paged" :key="c.id" class="hover:bg-elevated">
                <td class="px-4 py-3 font-medium text-highlighted"><bdi dir="ltr">{{ c.code || "—" }}</bdi></td>
                <td class="px-4 py-3">
                  <NuxtLink :to="`/crm/customers/${c.customer_id}`" class="font-medium text-highlighted hover:text-primary">{{ customerTitle(c) }}</NuxtLink>
                  <div v-if="c.customer?.phone" class="text-xs text-muted" dir="ltr">{{ c.customer.phone }}</div>
                </td>
                <td class="px-4 py-3">
                  <NuxtLink v-if="c.deal" :to="`/crm/deals/${c.deal.id}`" class="text-primary hover:underline">{{ c.deal.title }}</NuxtLink>
                  <span v-else class="text-muted">—</span>
                </td>
                <td class="whitespace-nowrap px-4 py-3">{{ c.signed_on ? formatDMY(c.signed_on) : "—" }}</td>
                <td class="whitespace-nowrap px-4 py-3 text-muted">{{ formatDMYTime(c.created_at) }}</td>
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
</template>
