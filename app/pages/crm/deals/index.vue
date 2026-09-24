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
const { t } = useI18n();

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

const columns = computed<TableColumn<Deal>[]>(() => [
  { accessorKey: "title", header: t("crm.deals.dealTitle") },
  { id: "customer", header: t("crm.deals.customer") },
  { accessorKey: "stage", header: t("crm.deals.stage") },
  { accessorKey: "value", header: t("crm.deals.value") },
]);

const createOpen = ref(false);
const creating = ref(false);
const schema = computed(() =>
  z.object({
    title: z.string().min(1, t("validation.required")),
    customer_id: z.uuid(t("validation.required")),
    value: z.number().optional(),
    expected_close_date: z.string().optional(),
  }),
);
type Schema = { title: string; customer_id: string; value?: number; expected_close_date?: string };
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
    toast.add({ title: t("crm.deals.createDealFailed"), description: error.message, color: "error" });
    return;
  }

  toast.add({ title: t("crm.deals.dealCreated"), color: "success" });
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
      <UDashboardNavbar :title="t('crm.deals.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton
            v-if="hasPermission('crm_deals', 'create')"
            icon="i-lucide-plus"
            :label="t('crm.deals.newDeal')"
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
          <UBadge :label="t(`crm.deals.stageValues.${row.original.stage}`)" :color="stageColors[row.original.stage]" variant="subtle" />
        </template>
      </UTable>
    </template>
  </UDashboardPanel>

  <UModal v-model:open="createOpen" :title="t('crm.deals.newDeal')">
    <template #body>
      <UForm :schema="schema" :state="state" class="space-y-4" @submit="onCreate">
        <UFormField name="title" :label="t('crm.deals.dealTitle')">
          <UInput v-model="state.title" class="w-full" />
        </UFormField>
        <UFormField name="customer_id" :label="t('crm.deals.customer')">
          <USelect v-model="state.customer_id" :items="customerOptions" value-key="value" class="w-full" />
        </UFormField>
        <UFormField name="value" :label="t('crm.deals.value')">
          <UInputNumber v-model="state.value" class="w-full" />
        </UFormField>
        <UFormField name="expected_close_date" :label="t('crm.deals.expectedCloseDate')">
          <UInput v-model="state.expected_close_date" type="date" class="w-full" />
        </UFormField>
        <UButton type="submit" :label="t('crm.deals.createDeal')" :loading="creating" block />
      </UForm>
    </template>
  </UModal>
</template>
