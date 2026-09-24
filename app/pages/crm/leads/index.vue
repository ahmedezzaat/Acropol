<script setup lang="ts">
import * as z from "zod";
import type { FormSubmitEvent, TableColumn } from "@nuxt/ui";

definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "crm_leads" },
});

const supabase = useSupabaseClient();
const toast = useToast();
const { hasPermission } = usePermissions();

interface Lead {
  id: string;
  name: string;
  phone: string | null;
  email: string | null;
  status: string;
  assigned_to: string | null;
  created_at: string;
}

interface Profile {
  id: string;
  full_name: string | null;
  email: string;
}

const search = ref("");
const statusFilter = ref("all");

const { data: leads, refresh, status: leadsStatus } = await useAsyncData<Lead[]>(
  "crm-leads",
  async () => {
    const { data, error } = await supabase
      .from("leads")
      .select("id, name, phone, email, status, assigned_to, created_at")
      .order("created_at", { ascending: false });
    if (error) throw error;
    return data ?? [];
  },
);

const { data: profiles } = await useAsyncData<Profile[]>("crm-leads-profiles", async () => {
  const { data, error } = await supabase.from("profiles").select("id, full_name, email").eq("is_active", true);
  if (error) throw error;
  return data ?? [];
});

function profileLabel(id: string | null) {
  if (!id) return "Unassigned";
  const p = profiles.value?.find((p) => p.id === id);
  return p?.full_name || p?.email || "Unknown";
}

const statusOptions = ["all", "new", "contacted", "qualified", "converted", "lost"];
const statusColors: Record<string, "neutral" | "info" | "warning" | "success" | "error"> = {
  new: "info",
  contacted: "warning",
  qualified: "warning",
  converted: "success",
  lost: "error",
};

const filteredLeads = computed(() => {
  return (leads.value ?? []).filter((lead) => {
    const matchesSearch =
      !search.value ||
      lead.name.toLowerCase().includes(search.value.toLowerCase()) ||
      (lead.email ?? "").toLowerCase().includes(search.value.toLowerCase());
    const matchesStatus = statusFilter.value === "all" || lead.status === statusFilter.value;
    return matchesSearch && matchesStatus;
  });
});

const columns: TableColumn<Lead>[] = [
  { accessorKey: "name", header: "Name" },
  { id: "contact", header: "Contact" },
  { accessorKey: "status", header: "Status" },
  { id: "assigned", header: "Assigned to" },
];

// --- Create lead ---
const createOpen = ref(false);
const creating = ref(false);
const canAssign = computed(() => hasPermission("crm_leads", "assign"));

const schema = z.object({
  name: z.string().min(1, "Name is required"),
  phone: z.string().optional(),
  email: z.string().optional(),
  source: z.string().optional(),
});
type Schema = z.output<typeof schema>;
const state = reactive<Partial<Schema>>({ name: "", phone: "", email: "", source: "" });

async function onCreate(event: FormSubmitEvent<Schema>) {
  creating.value = true;
  const { error } = await supabase.from("leads").insert({
    name: event.data.name,
    phone: event.data.phone || null,
    email: event.data.email || null,
    source: event.data.source || null,
  });
  creating.value = false;

  if (error) {
    toast.add({ title: "Failed to create lead", description: error.message, color: "error" });
    return;
  }

  toast.add({ title: "Lead created", color: "success" });
  createOpen.value = false;
  state.name = "";
  state.phone = "";
  state.email = "";
  state.source = "";
  refresh();
}

function openLead(lead: Lead) {
  navigateTo(`/crm/leads/${lead.id}`);
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar title="Leads">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton
            v-if="hasPermission('crm_leads', 'create')"
            icon="i-lucide-plus"
            label="New lead"
            @click="createOpen = true"
          />
        </template>
      </UDashboardNavbar>

      <UDashboardToolbar>
        <template #left>
          <UInput v-model="search" icon="i-lucide-search" placeholder="Search leads..." />
        </template>
        <template #right>
          <USelect v-model="statusFilter" :items="statusOptions" />
        </template>
      </UDashboardToolbar>
    </template>

    <template #body>
      <UTable
        :data="filteredLeads"
        :columns="columns"
        :loading="leadsStatus === 'pending' || leadsStatus === 'idle'"
        @select="(_e, row) => openLead(row.original)"
      >
        <template #contact-cell="{ row }">
          <div class="text-sm">
            <div>{{ row.original.phone }}</div>
            <div class="text-muted">{{ row.original.email }}</div>
          </div>
        </template>
        <template #status-cell="{ row }">
          <UBadge :label="row.original.status" :color="statusColors[row.original.status]" variant="subtle" />
        </template>
        <template #assigned-cell="{ row }">
          {{ profileLabel(row.original.assigned_to) }}
        </template>
      </UTable>
    </template>
  </UDashboardPanel>

  <UModal v-model:open="createOpen" title="New lead">
    <template #body>
      <UForm :schema="schema" :state="state" class="space-y-4" @submit="onCreate">
        <UFormField name="name" label="Name">
          <UInput v-model="state.name" class="w-full" />
        </UFormField>
        <UFormField name="phone" label="Phone">
          <UInput v-model="state.phone" class="w-full" />
        </UFormField>
        <UFormField name="email" label="Email">
          <UInput v-model="state.email" type="email" class="w-full" />
        </UFormField>
        <UFormField name="source" label="Source">
          <UInput v-model="state.source" placeholder="e.g. website, referral" class="w-full" />
        </UFormField>
        <p v-if="!canAssign" class="text-xs text-muted">
          New leads are unassigned by default. You don't have permission to assign leads.
        </p>
        <UButton type="submit" label="Create lead" :loading="creating" block />
      </UForm>
    </template>
  </UModal>
</template>
