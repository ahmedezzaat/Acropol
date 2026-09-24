<script setup lang="ts">
definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "crm_leads" },
});

const route = useRoute();
const leadId = route.params.id as string;
const supabase = useSupabaseClient();
const toast = useToast();
const { hasPermission } = usePermissions();

interface Lead {
  id: string;
  name: string;
  phone: string | null;
  email: string | null;
  source: string | null;
  status: string;
  notes: string | null;
  assigned_to: string | null;
  customer_id: string | null;
}

interface Profile {
  id: string;
  full_name: string | null;
  email: string;
}

const lead = ref<Lead | null>(null);
const saving = ref(false);
const converting = ref(false);
const deleting = ref(false);

const canEdit = computed(() => hasPermission("crm_leads", "edit"));
const canAssign = computed(() => hasPermission("crm_leads", "assign"));
const canConvert = computed(() => hasPermission("crm_customers", "create"));
const canDelete = computed(() => hasPermission("crm_leads", "delete"));

const statusOptions = ["new", "contacted", "qualified", "converted", "lost"];

const { data: profiles } = await useAsyncData<Profile[]>("crm-lead-profiles", async () => {
  const { data, error } = await supabase.from("profiles").select("id, full_name, email").eq("is_active", true);
  if (error) throw error;
  return data ?? [];
});

const assigneeOptions = computed(() => [
  { label: "Unassigned", value: null },
  ...(profiles.value ?? []).map((p) => ({ label: p.full_name || p.email, value: p.id })),
]);

const { status } = await useAsyncData(`crm-lead-${leadId}`, async () => {
  const { data, error } = await supabase.from("leads").select("*").eq("id", leadId).single();
  if (error) throw error;
  lead.value = data;
  return true;
});

async function save() {
  if (!lead.value) return;
  saving.value = true;

  const payload: Record<string, unknown> = {
    name: lead.value.name,
    phone: lead.value.phone,
    email: lead.value.email,
    source: lead.value.source,
    status: lead.value.status,
    notes: lead.value.notes,
  };
  if (canAssign.value) payload.assigned_to = lead.value.assigned_to;

  const { error } = await supabase.from("leads").update(payload).eq("id", leadId);
  saving.value = false;

  if (error) {
    toast.add({ title: "Failed to save", description: error.message, color: "error" });
    return;
  }
  toast.add({ title: "Lead saved", color: "success" });
}

async function convertToCustomer() {
  converting.value = true;
  const { data, error } = await supabase.rpc("crm_convert_lead", { p_lead_id: leadId });
  converting.value = false;

  if (error) {
    toast.add({ title: "Failed to convert lead", description: error.message, color: "error" });
    return;
  }

  toast.add({ title: "Converted to customer", color: "success" });
  navigateTo(`/crm/customers/${data}`);
}

async function remove() {
  deleting.value = true;
  const { error } = await supabase.from("leads").delete().eq("id", leadId);
  deleting.value = false;

  if (error) {
    toast.add({ title: "Failed to delete lead", description: error.message, color: "error" });
    return;
  }
  toast.add({ title: "Lead deleted", color: "success" });
  navigateTo("/crm/leads");
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="lead?.name ?? 'Lead'">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton
            v-if="canConvert && lead && !lead.customer_id"
            icon="i-lucide-user-plus"
            label="Convert to customer"
            color="primary"
            variant="soft"
            :loading="converting"
            @click="convertToCustomer"
          />
          <UButton
            v-if="canDelete"
            icon="i-lucide-trash"
            color="error"
            variant="soft"
            :loading="deleting"
            @click="remove"
          />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>

      <div v-else-if="lead" class="max-w-xl space-y-4">
        <UAlert
          v-if="lead.customer_id"
          icon="i-lucide-check-circle"
          color="success"
          variant="subtle"
          title="Converted"
          description="This lead has been converted to a customer."
        />

        <UFormField label="Name">
          <UInput v-model="lead.name" :disabled="!canEdit" class="w-full" />
        </UFormField>
        <UFormField label="Phone">
          <UInput v-model="lead.phone" :disabled="!canEdit" class="w-full" />
        </UFormField>
        <UFormField label="Email">
          <UInput v-model="lead.email" type="email" :disabled="!canEdit" class="w-full" />
        </UFormField>
        <UFormField label="Source">
          <UInput v-model="lead.source" :disabled="!canEdit" class="w-full" />
        </UFormField>
        <UFormField label="Status">
          <USelect v-model="lead.status" :items="statusOptions" :disabled="!canEdit" class="w-full" />
        </UFormField>
        <UFormField label="Assigned to">
          <USelect
            v-model="lead.assigned_to"
            :items="assigneeOptions"
            value-key="value"
            :disabled="!canAssign"
            class="w-full"
          />
          <p v-if="!canAssign" class="mt-1 text-xs text-muted">
            You don't have permission to (re)assign leads.
          </p>
        </UFormField>
        <UFormField label="Notes">
          <UTextarea v-model="lead.notes" :disabled="!canEdit" class="w-full" :rows="4" />
        </UFormField>

        <UButton v-if="canEdit" label="Save" :loading="saving" @click="save" />
      </div>
    </template>
  </UDashboardPanel>
</template>
