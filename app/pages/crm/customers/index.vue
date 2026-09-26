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
  assigned_to: string | null;
}

interface Profile {
  id: string;
  full_name: string | null;
  email: string;
}

const search = ref("");
const canAssign = computed(() => hasPermission("crm_customers", "assign"));

const { data: customers, refresh, status } = await useAsyncData<Customer[]>(
  "crm-customers",
  async () => {
    const { data, error } = await supabase
      .from("customers")
      .select("id, name, company, phone, email, assigned_to")
      .order("name");
    if (error) throw error;
    return data ?? [];
  },
);

const { data: profiles } = await useAsyncData<Profile[]>("crm-customers-profiles", async () => {
  const { data, error } = await supabase.from("profiles").select("id, full_name, email").eq("is_active", true);
  if (error) throw error;
  return data ?? [];
});

function profileLabel(id: string | null) {
  if (!id) return t("common.unassigned");
  const p = profiles.value?.find((p) => p.id === id);
  return p?.full_name || p?.email || "?";
}
const assigneeOptions = computed(() => [
  { label: t("common.unassigned"), value: null },
  ...(profiles.value ?? []).map((p) => ({ label: p.full_name || p.email, value: p.id })),
]);

const filteredCustomers = computed(() =>
  (customers.value ?? []).filter(
    (c) => !search.value || c.name.toLowerCase().includes(search.value.toLowerCase()),
  ),
);

const columns = computed<TableColumn<Customer>[]>(() => [
  { accessorKey: "name", header: t("common.name") },
  { accessorKey: "company", header: t("crm.customers.company") },
  { id: "contact", header: t("crm.leads.contact") },
  { id: "assigned", header: t("crm.customers.assignedTo") },
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
    assigned_to: z.uuid().nullable().optional(),
  }),
);
type Schema = {
  name: string;
  company?: string;
  phone?: string;
  email?: string;
  address?: string;
  assigned_to?: string | null;
};
const state = reactive<Partial<Schema>>({
  name: "",
  company: "",
  phone: "",
  email: "",
  address: "",
  assigned_to: null,
});

async function onCreate(event: FormSubmitEvent<Schema>) {
  creating.value = true;
  const payload: Record<string, unknown> = {
    name: event.data.name,
    company: event.data.company || null,
    phone: event.data.phone || null,
    email: event.data.email || null,
    address: event.data.address || null,
  };
  if (canAssign.value) payload.assigned_to = event.data.assigned_to || null;

  const { error } = await supabase.from("customers").insert(payload);
  creating.value = false;

  if (error) {
    toast.add({ title: t("crm.customers.createCustomerFailed"), description: error.message, color: "error" });
    return;
  }

  toast.add({ title: t("crm.customers.customerCreated"), color: "success" });
  createOpen.value = false;
  Object.assign(state, { name: "", company: "", phone: "", email: "", address: "", assigned_to: null });
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
        <template #assigned-cell="{ row }">
          {{ profileLabel(row.original.assigned_to) }}
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
        <UFormField v-if="canAssign" name="assigned_to" :label="t('crm.customers.assignedTo')">
          <USelect v-model="state.assigned_to" :items="assigneeOptions" value-key="value" class="w-full" />
        </UFormField>
        <p v-else class="text-xs text-muted">{{ t("crm.customers.assignCreateHint") }}</p>
        <UButton type="submit" :label="t('crm.customers.createCustomer')" :loading="creating" block />
      </UForm>
    </template>
  </UModal>
</template>
