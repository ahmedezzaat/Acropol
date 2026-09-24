<script setup lang="ts">
import * as z from "zod";
import type { FormSubmitEvent, TableColumn } from "@nuxt/ui";

definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "crm_deals" },
});

const supabase = useSupabaseClient();
const toast = useToast();
const { hasPermission } = usePermissions();

interface Deal {
  id: string;
  title: string;
  stage: string;
  value: number | null;
  customer_id: string;
  expected_close_date: string | null;
}

interface Customer {
  id: string;
  name: string;
}

const { data: deals, refresh, status } = await useAsyncData<Deal[]>("crm-deals", async () => {
  const { data, error } = await supabase
    .from("deals")
    .select("id, title, stage, value, customer_id, expected_close_date")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data ?? [];
});

const { data: customers } = await useAsyncData<Customer[]>("crm-deals-customers", async () => {
  const { data, error } = await supabase.from("customers").select("id, name").order("name");
  if (error) throw error;
  return data ?? [];
});

const customerOptions = computed(() =>
  (customers.value ?? []).map((c) => ({ label: c.name, value: c.id })),
);

function customerName(id: string) {
  return customers.value?.find((c) => c.id === id)?.name ?? "—";
}

const stageColors: Record<string, "neutral" | "info" | "warning" | "success" | "error"> = {
  open: "info",
  proposal: "warning",
  negotiation: "warning",
  won: "success",
  lost: "error",
};

const columns: TableColumn<Deal>[] = [
  { accessorKey: "title", header: "Title" },
  { id: "customer", header: "Customer" },
  { accessorKey: "stage", header: "Stage" },
  { accessorKey: "value", header: "Value" },
];

const createOpen = ref(false);
const creating = ref(false);
const schema = z.object({
  title: z.string().min(1, "Title is required"),
  customer_id: z.uuid("Customer is required"),
  value: z.number().optional(),
  expected_close_date: z.string().optional(),
});
type Schema = z.output<typeof schema>;
const state = reactive<Partial<Schema>>({ title: "", customer_id: undefined, value: undefined, expected_close_date: "" });

async function onCreate(event: FormSubmitEvent<Schema>) {
  creating.value = true;
  const { error } = await supabase.from("deals").insert({
    title: event.data.title,
    customer_id: event.data.customer_id,
    value: event.data.value ?? null,
    expected_close_date: event.data.expected_close_date || null,
  });
  creating.value = false;

  if (error) {
    toast.add({ title: "Failed to create deal", description: error.message, color: "error" });
    return;
  }

  toast.add({ title: "Deal created", color: "success" });
  createOpen.value = false;
  Object.assign(state, { title: "", customer_id: undefined, value: undefined, expected_close_date: "" });
  refresh();
}

function openDeal(deal: Deal) {
  navigateTo(`/crm/deals/${deal.id}`);
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar title="Deals">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton
            v-if="hasPermission('crm_deals', 'create')"
            icon="i-lucide-plus"
            label="New deal"
            @click="createOpen = true"
          />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <UTable
        :data="deals ?? []"
        :columns="columns"
        :loading="status === 'pending' || status === 'idle'"
        @select="(_e, row) => openDeal(row.original)"
      >
        <template #customer-cell="{ row }">
          {{ customerName(row.original.customer_id) }}
        </template>
        <template #stage-cell="{ row }">
          <UBadge :label="row.original.stage" :color="stageColors[row.original.stage]" variant="subtle" />
        </template>
      </UTable>
    </template>
  </UDashboardPanel>

  <UModal v-model:open="createOpen" title="New deal">
    <template #body>
      <UForm :schema="schema" :state="state" class="space-y-4" @submit="onCreate">
        <UFormField name="title" label="Title">
          <UInput v-model="state.title" class="w-full" />
        </UFormField>
        <UFormField name="customer_id" label="Customer">
          <USelect v-model="state.customer_id" :items="customerOptions" value-key="value" class="w-full" />
        </UFormField>
        <UFormField name="value" label="Value">
          <UInputNumber v-model="state.value" class="w-full" />
        </UFormField>
        <UFormField name="expected_close_date" label="Expected close date">
          <UInput v-model="state.expected_close_date" type="date" class="w-full" />
        </UFormField>
        <UButton type="submit" label="Create deal" :loading="creating" block />
      </UForm>
    </template>
  </UModal>
</template>
