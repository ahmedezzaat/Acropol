<script setup lang="ts">
import * as z from "zod";
import type { FormSubmitEvent, TableColumn } from "@nuxt/ui";

definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "crm_customers" },
});

const supabase = useSupabaseClient();
const toast = useToast();
const { hasPermission } = usePermissions();
const { t } = useI18n();

interface Customer {
  id: string;
  name: string;
  company: string | null;
  phone: string | null;
  email: string | null;
}

const search = ref("");

const { data: customers, refresh, status } = await useAsyncData<Customer[]>(
  "crm-customers",
  async () => {
    const { data, error } = await supabase
      .from("customers")
      .select("id, name, company, phone, email")
      .order("name");
    if (error) throw error;
    return data ?? [];
  },
);

const filteredCustomers = computed(() =>
  (customers.value ?? []).filter(
    (c) => !search.value || c.name.toLowerCase().includes(search.value.toLowerCase()),
  ),
);

const columns = computed<TableColumn<Customer>[]>(() => [
  { accessorKey: "name", header: t("common.name") },
  { accessorKey: "company", header: t("crm.customers.company") },
  { id: "contact", header: t("crm.leads.contact") },
]);

const createOpen = ref(false);
const creating = ref(false);
const schema = computed(() =>
  z.object({
    name: z.string().min(1, t("validation.required")),
    company: z.string().optional(),
    phone: z.string().optional(),
    email: z.string().optional(),
    address: z.string().optional(),
  }),
);
type Schema = { name: string; company?: string; phone?: string; email?: string; address?: string };
const state = reactive<Partial<Schema>>({ name: "", company: "", phone: "", email: "", address: "" });

async function onCreate(event: FormSubmitEvent<Schema>) {
  creating.value = true;
  const { error } = await supabase.from("customers").insert({
    name: event.data.name,
    company: event.data.company || null,
    phone: event.data.phone || null,
    email: event.data.email || null,
    address: event.data.address || null,
  });
  creating.value = false;

  if (error) {
    toast.add({ title: t("crm.customers.createCustomerFailed"), description: error.message, color: "error" });
    return;
  }

  toast.add({ title: t("crm.customers.customerCreated"), color: "success" });
  createOpen.value = false;
  Object.assign(state, { name: "", company: "", phone: "", email: "", address: "" });
  refresh();
}

function openCustomer(customer: Customer) {
  navigateTo(`/crm/customers/${customer.id}`);
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="t('crm.customers.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton
            v-if="hasPermission('crm_customers', 'create')"
            icon="i-lucide-plus"
            :label="t('crm.customers.newCustomer')"
            @click="createOpen = true"
          />
        </template>
      </UDashboardNavbar>

      <UDashboardToolbar>
        <template #left>
          <UInput v-model="search" icon="i-lucide-search" :placeholder="t('crm.customers.searchPlaceholder')" />
        </template>
      </UDashboardToolbar>
    </template>

    <template #body>
      <UTable
        :data="filteredCustomers"
        :columns="columns"
        :loading="status === 'pending' || status === 'idle'"
        @select="(_e, row) => openCustomer(row.original)"
      >
        <template #contact-cell="{ row }">
          <div class="text-sm">
            <div>{{ row.original.phone }}</div>
            <div class="text-muted">{{ row.original.email }}</div>
          </div>
        </template>
      </UTable>
    </template>
  </UDashboardPanel>

  <UModal v-model:open="createOpen" :title="t('crm.customers.newCustomer')">
    <template #body>
      <UForm :schema="schema" :state="state" class="space-y-4" @submit="onCreate">
        <UFormField name="name" :label="t('common.name')">
          <UInput v-model="state.name" class="w-full" />
        </UFormField>
        <UFormField name="company" :label="t('crm.customers.company')">
          <UInput v-model="state.company" class="w-full" />
        </UFormField>
        <UFormField name="phone" :label="t('common.phone')">
          <UInput v-model="state.phone" class="w-full" />
        </UFormField>
        <UFormField name="email" :label="t('common.email')">
          <UInput v-model="state.email" type="email" class="w-full" />
        </UFormField>
        <UFormField name="address" :label="t('crm.customers.address')">
          <UTextarea v-model="state.address" class="w-full" />
        </UFormField>
        <UButton type="submit" :label="t('crm.customers.createCustomer')" :loading="creating" block />
      </UForm>
    </template>
  </UModal>
</template>
