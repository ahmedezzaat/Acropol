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

const statusOptions = ["draft", "sent", "accepted", "rejected", "expired"];

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

const { status } = await useAsyncData(`crm-quote-${quoteId}`, async () => {
  await loadQuote();
  await loadItems();
  return true;
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

const columns: TableColumn<QuoteItem>[] = [
  { accessorKey: "description", header: "Description" },
  { accessorKey: "qty", header: "Qty" },
  { accessorKey: "unit_price", header: "Unit price" },
  { accessorKey: "line_total", header: "Line total" },
  { id: "actions" },
];

async function saveDetails() {
  if (!quote.value) return;
  saving.value = true;
  const { error } = await supabase
    .from("quotes")
    .update({ status: quote.value.status, valid_until: quote.value.valid_until, tax: quote.value.tax })
    .eq("id", quoteId);
  saving.value = false;

  if (error) {
    toast.add({ title: "Failed to save", description: error.message, color: "error" });
    return;
  }
  await loadQuote();
  toast.add({ title: "Quote saved", color: "success" });
}

async function addItem() {
  const { error } = await supabase.from("quote_items").insert({
    quote_id: quoteId,
    description: "New item",
    qty: 1,
    unit_price: 0,
    sort_order: items.value.length,
  });
  if (error) {
    toast.add({ title: "Failed to add item", description: error.message, color: "error" });
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
    toast.add({ title: "Failed to save item", description: error.message, color: "error" });
    return;
  }
  // line_total is a generated column recomputed server-side — reload items
  // (not just the quote) so the row reflects it, not just the parent totals.
  await Promise.all([loadItems(), loadQuote()]);
}

async function removeItem(item: QuoteItem) {
  const { error } = await supabase.from("quote_items").delete().eq("id", item.id);
  if (error) {
    toast.add({ title: "Failed to remove item", description: error.message, color: "error" });
    return;
  }
  await loadItems();
  await loadQuote();
}

async function removeQuote() {
  const { error } = await supabase.from("quotes").delete().eq("id", quoteId);
  if (error) {
    toast.add({ title: "Failed to delete quote", description: error.message, color: "error" });
    return;
  }
  toast.add({ title: "Quote deleted", color: "success" });
  navigateTo("/crm/quotes");
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="quote?.quote_number ?? 'Quote'">
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
        <UPageCard title="Details">
          <div class="space-y-4">
            <UFormField label="Customer">
              <ULink :to="`/crm/customers/${quote.customer_id}`" class="text-primary">
                {{ customer?.name }}
              </ULink>
            </UFormField>
            <UFormField label="Status">
              <USelect v-model="quote.status" :items="statusOptions" :disabled="!canEdit" class="w-full" />
            </UFormField>
            <UFormField label="Valid until">
              <UInput v-model="quote.valid_until" type="date" :disabled="!canEdit" class="w-full" />
            </UFormField>
            <UFormField label="Tax">
              <UInputNumber v-model="quote.tax" :disabled="!canEdit" class="w-full" />
            </UFormField>
            <UButton v-if="canEdit" label="Save" :loading="saving" @click="saveDetails" />
          </div>
        </UPageCard>

        <UPageCard title="Line items">
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

          <UButton v-if="canEdit" icon="i-lucide-plus" label="Add item" variant="soft" class="mt-4" @click="addItem" />

          <div class="mt-6 space-y-1 text-right text-sm">
            <div>Subtotal: {{ quote.subtotal }}</div>
            <div>Tax: {{ quote.tax }}</div>
            <div class="font-semibold text-highlighted">Total: {{ quote.total }}</div>
          </div>
        </UPageCard>
      </div>
    </template>
  </UDashboardPanel>
</template>
