<script setup lang="ts">
import type { TableColumn } from "@nuxt/ui";

definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "crm_quotes" },
});

const supabase = useSupabaseClient();
const { t } = useI18n();

interface Quote {
  id: string;
  quote_number: string;
  status: string;
  total: number;
  customer_id: string;
}

interface Customer {
  id: string;
  name: string;
}

const { data: quotes, status } = await useAsyncData<Quote[]>("crm-quotes", async () => {
  const { data, error } = await supabase
    .from("quotes")
    .select("id, quote_number, status, total, customer_id")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data ?? [];
});

const { data: customers } = await useAsyncData<Customer[]>("crm-quotes-customers", async () => {
  const { data, error } = await supabase.from("customers").select("id, name");
  if (error) throw error;
  return data ?? [];
});

function customerName(id: string) {
  return customers.value?.find((c) => c.id === id)?.name ?? "—";
}

const statusColors: Record<string, "neutral" | "info" | "warning" | "success" | "error"> = {
  draft: "neutral",
  sent: "info",
  accepted: "success",
  rejected: "error",
  expired: "warning",
};

const columns = computed<TableColumn<Quote>[]>(() => [
  { accessorKey: "quote_number", header: t("crm.quotes.quoteNumber") },
  { id: "customer", header: t("crm.quotes.customer") },
  { accessorKey: "status", header: t("common.status") },
  { accessorKey: "total", header: t("crm.quotes.total") },
]);

function openQuote(quote: Quote) {
  navigateTo(`/crm/quotes/${quote.id}`);
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="t('crm.quotes.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <UTable
        :data="quotes ?? []"
        :columns="columns"
        :loading="status === 'pending' || status === 'idle'"
        @select="(_e, row) => openQuote(row.original)"
      >
        <template #customer-cell="{ row }">
          {{ customerName(row.original.customer_id) }}
        </template>
        <template #status-cell="{ row }">
          <UBadge :label="t(`crm.quotes.statusValues.${row.original.status}`)" :color="statusColors[row.original.status]" variant="subtle" />
        </template>
      </UTable>
    </template>
  </UDashboardPanel>
</template>
