<script setup lang="ts">
import type { TableColumn } from "@nuxt/ui";

definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "crm_quotes" },
});

const route = useRoute();
const quoteId = route.params.id as string;
const supabase = useSupabaseClient();
const toast = useToast();
const { hasPermission } = usePermissions();
const { t } = useI18n();

interface Quote {
  id: string;
  quote_number: string;
  status: string;
  valid_until: string | null;
  subtotal: number;
  tax: number;
  total: number;
  customer_id: string;
}

interface QuoteItem {
  id: string;
  description: string;
  qty: number;
  unit_price: number;
  line_total: number;
  sort_order: number;
}

interface Customer {
  id: string;
  name: string;
}

const quote = ref<Quote | null>(null);
const items = ref<QuoteItem[]>([]);
const saving = ref(false);
const canEdit = computed(() => hasPermission("crm_quotes", "edit"));
const canDelete = computed(() => hasPermission("crm_quotes", "delete"));

const statusKeys = ["draft", "sent", "accepted", "rejected", "expired"] as const;
const statusOptions = computed(() =>
  statusKeys.map((s) => ({ label: t(`crm.quotes.statusValues.${s}`), value: s })),
);

async function loadQuote() {
  const { data, error } = await supabase.from("quotes").select("*").eq("id", quoteId).single();
  if (error) throw error;
  quote.value = data;
}

async function loadItems() {
  const { data, error } = await supabase
    .from("quote_items")
    .select("*")
    .eq("quote_id", quoteId)
    .order("sort_order");
  if (error) throw error;
  items.value = data ?? [];
}

// See crm/leads/[id].vue for why the initial population goes through
// useAsyncData's own `data` (via watchEffect) instead of only the
// loadQuote()/loadItems() side effects — those two stay as-is for the
// later client-triggered refreshes (after save/add/remove), which aren't
// affected since they run purely client-side.
const { data: quoteInitialPayload, status } = await useAsyncData(`crm-quote-${quoteId}`, async () => {
  const [{ data: q, error: qErr }, { data: i, error: iErr }] = await Promise.all([
    supabase.from("quotes").select("*").eq("id", quoteId).single(),
    supabase.from("quote_items").select("*").eq("quote_id", quoteId).order("sort_order"),
  ]);
  if (qErr) throw qErr;
  if (iErr) throw iErr;
  return { quote: q, items: i ?? [] };
});
watchEffect(() => {
  if (quoteInitialPayload.value) {
    quote.value = quoteInitialPayload.value.quote;
    items.value = quoteInitialPayload.value.items;
  }
});

const { data: customer } = await useAsyncData<Customer | null>(`crm-quote-${quoteId}-customer`, async () => {
  if (!quote.value) return null;
  const { data, error } = await supabase
    .from("customers")
    .select("id, name")
    .eq("id", quote.value.customer_id)
    .single();
  if (error) throw error;
  return data;
});

const columns = computed<TableColumn<QuoteItem>[]>(() => [
  { accessorKey: "description", header: t("crm.quotes.description") },
  { accessorKey: "qty", header: t("crm.quotes.qty") },
  { accessorKey: "unit_price", header: t("crm.quotes.unitPrice") },
  { accessorKey: "line_total", header: t("crm.quotes.lineTotal") },
  { id: "actions" },
]);

async function saveDetails() {
  if (!quote.value) return;
  saving.value = true;
  const { error } = await supabase
    .from("quotes")
    .update({ status: quote.value.status, valid_until: quote.value.valid_until, tax: quote.value.tax })
    .eq("id", quoteId);
  saving.value = false;

  if (error) {
    toast.add({ title: t("crm.quotes.saveFailed"), description: error.message, color: "error" });
    return;
  }
  await loadQuote();
  toast.add({ title: t("crm.quotes.quoteSaved"), color: "success" });
}

async function addItem() {
  const { error } = await supabase.from("quote_items").insert({
    quote_id: quoteId,
    description: t("crm.quotes.newItemDefault"),
    qty: 1,
    unit_price: 0,
    sort_order: items.value.length,
  });
  if (error) {
    toast.add({ title: t("crm.quotes.addItemFailed"), description: error.message, color: "error" });
    return;
  }
  await loadItems();
  await loadQuote();
}

async function saveItem(item: QuoteItem) {
  const { error } = await supabase
    .from("quote_items")
    .update({ description: item.description, qty: item.qty, unit_price: item.unit_price })
    .eq("id", item.id);
  if (error) {
    toast.add({ title: t("crm.quotes.itemSaveFailed"), description: error.message, color: "error" });
    return;
  }
  // line_total is a generated column recomputed server-side — reload items
  // (not just the quote) so the row reflects it, not just the parent totals.
  await Promise.all([loadItems(), loadQuote()]);
}

async function removeItem(item: QuoteItem) {
  const { error } = await supabase.from("quote_items").delete().eq("id", item.id);
  if (error) {
    toast.add({ title: t("crm.quotes.removeItemFailed"), description: error.message, color: "error" });
    return;
  }
  await loadItems();
  await loadQuote();
}

async function removeQuote() {
  const { error } = await supabase.from("quotes").delete().eq("id", quoteId);
  if (error) {
    toast.add({ title: t("crm.quotes.deleteFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("crm.quotes.quoteDeleted"), color: "success" });
  navigateTo("/crm/quotes");
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="quote?.quote_number ?? t('crm.quotes.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton v-if="canDelete" icon="i-lucide-trash" color="error" variant="soft" @click="removeQuote" />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>

      <div v-else-if="quote" class="max-w-3xl space-y-8">
        <UPageCard :title="t('crm.quotes.detailsTitle')">
          <div class="space-y-4">
            <UFormField :label="t('crm.quotes.customer')">
              <ULink :to="`/crm/customers/${quote.customer_id}`" class="text-primary">
                {{ customer?.name }}
              </ULink>
            </UFormField>
            <UFormField :label="t('common.status')">
              <USelect v-model="quote.status" :items="statusOptions" value-key="value" :disabled="!canEdit" class="w-full" />
            </UFormField>
            <UFormField :label="t('crm.quotes.validUntil')">
              <UInput v-model="quote.valid_until" type="date" :disabled="!canEdit" class="w-full" />
            </UFormField>
            <UFormField :label="t('crm.quotes.tax')">
              <UInputNumber v-model="quote.tax" :disabled="!canEdit" class="w-full" />
            </UFormField>
            <UButton v-if="canEdit" :label="t('common.save')" :loading="saving" @click="saveDetails" />
          </div>
        </UPageCard>

        <UPageCard :title="t('crm.quotes.lineItemsTitle')">
          <UTable :data="items" :columns="columns">
            <template #description-cell="{ row }">
              <UInput
                v-model="row.original.description"
                :disabled="!canEdit"
                @blur="saveItem(row.original)"
              />
            </template>
            <template #qty-cell="{ row }">
              <UInputNumber
                v-model="row.original.qty"
                :disabled="!canEdit"
                class="w-24"
                @blur="saveItem(row.original)"
              />
            </template>
            <template #unit_price-cell="{ row }">
              <UInputNumber
                v-model="row.original.unit_price"
                :disabled="!canEdit"
                class="w-28"
                @blur="saveItem(row.original)"
              />
            </template>
            <template #line_total-cell="{ row }">
              {{ row.original.line_total }}
            </template>
            <template #actions-cell="{ row }">
              <UButton
                v-if="canEdit"
                icon="i-lucide-trash"
                color="error"
                variant="ghost"
                size="sm"
                @click="removeItem(row.original)"
              />
            </template>
          </UTable>

          <UButton v-if="canEdit" icon="i-lucide-plus" :label="t('crm.quotes.addItem')" variant="soft" class="mt-4" @click="addItem" />

          <div class="mt-6 space-y-1 text-end text-sm">
            <div>{{ t("crm.quotes.subtotal") }}: {{ quote.subtotal }}</div>
            <div>{{ t("crm.quotes.tax") }}: {{ quote.tax }}</div>
            <div class="font-semibold text-highlighted">{{ t("crm.quotes.total") }}: {{ quote.total }}</div>
          </div>
        </UPageCard>
      </div>
    </template>
  </UDashboardPanel>
</template>
