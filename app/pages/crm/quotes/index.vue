<script setup lang="ts">
import type { TableColumn } from "@nuxt/ui";

definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "crm_quotes" },
});

const supabase = useSupabaseClient();

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

const columns: TableColumn<Quote>[] = [
  { accessorKey: "quote_number", header: "Quote #" },
  { id: "customer", header: "Customer" },
  { accessorKey: "status", header: "Status" },
  { accessorKey: "total", header: "Total" },
];

function openQuote(quote: Quote) {
  navigateTo(`/crm/quotes/${quote.id}`);
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar title="Quotes">
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
          <UBadge :label="row.original.status" :color="statusColors[row.original.status]" variant="subtle" />
        </template>
      </UTable>
    </template>
  </UDashboardPanel>
</template>
