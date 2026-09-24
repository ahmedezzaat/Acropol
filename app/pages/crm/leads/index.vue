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
const { t } = useI18n();

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
  if (!id) return t("common.unassigned");
  const p = profiles.value?.find((p) => p.id === id);
  return p?.full_name || p?.email || "?";
}

const statusKeys = ["new", "contacted", "qualified", "converted", "lost"] as const;
const statusOptions = computed(() => [
  { label: t("common.all"), value: "all" },
  ...statusKeys.map((s) => ({ label: t(`crm.leads.status.${s}`), value: s })),
]);
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

const columns = computed<TableColumn<Lead>[]>(() => [
  { accessorKey: "name", header: t("common.name") },
  { id: "contact", header: t("crm.leads.contact") },
  { accessorKey: "status", header: t("common.status") },
  { id: "assigned", header: t("crm.leads.assignedTo") },
]);

// --- Create lead ---
const createOpen = ref(false);
const creating = ref(false);
const canAssign = computed(() => hasPermission("crm_leads", "assign"));

const leadTypeOptions = computed(() => [
  { label: t("crm.leads.type.individual"), value: "individual" },
  { label: t("crm.leads.type.company"), value: "company" },
]);

const sourceKeys = ["facebook", "instagram", "meta", "google", "website", "event", "referral"] as const;
const sourceOptions = computed(() =>
  sourceKeys.map((s) => ({ label: t(`crm.leads.sourceValues.${s}`), value: s })),
);

const assigneeOptions = computed(() => [
  { label: t("common.unassigned"), value: null },
  ...(profiles.value ?? []).map((p) => ({ label: p.full_name || p.email, value: p.id })),
]);

const schema = computed(() =>
  z
    .object({
      lead_type: z.enum(["individual", "company"]),
      company_name: z.string().optional(),
      name: z.string().min(1, t("validation.required")),
      phone: z.string().min(1, t("validation.required")),
      phone2: z.string().optional(),
      email: z.string().optional(),
      source: z.enum(sourceKeys, t("validation.required")),
      notes: z.string().optional(),
      assigned_to: z.uuid().nullable().optional(),
    })
    .superRefine((data, ctx) => {
      if (data.lead_type === "company" && !data.company_name?.trim()) {
        ctx.addIssue({ message: t("validation.required"), path: ["company_name"] });
      }
    }),
);
type Schema = {
  lead_type: "individual" | "company";
  company_name?: string;
  name: string;
  phone: string;
  phone2?: string;
  email?: string;
  source: (typeof sourceKeys)[number];
  notes?: string;
  assigned_to?: string | null;
};
const state = reactive<Partial<Schema>>({
  lead_type: "individual",
  company_name: "",
  name: "",
  phone: "",
  phone2: "",
  email: "",
  source: undefined,
  notes: "",
  assigned_to: null,
});

function resetCreateState() {
  state.lead_type = "individual";
  state.company_name = "";
  state.name = "";
  state.phone = "";
  state.phone2 = "";
  state.email = "";
  state.source = undefined;
  state.notes = "";
  state.assigned_to = null;
}

async function onCreate(event: FormSubmitEvent<Schema>) {
  creating.value = true;
  const payload: Record<string, unknown> = {
    lead_type: event.data.lead_type,
    company_name: event.data.lead_type === "company" ? event.data.company_name || null : null,
    name: event.data.name,
    phone: event.data.phone,
    phone2: event.data.phone2 || null,
    email: event.data.email || null,
    source: event.data.source,
    notes: event.data.notes || null,
  };
  if (canAssign.value) payload.assigned_to = event.data.assigned_to || null;

  const { error } = await supabase.from("leads").insert(payload);
  creating.value = false;

  if (error) {
    toast.add({ title: t("crm.leads.createLeadFailed"), description: error.message, color: "error" });
    return;
  }

  toast.add({ title: t("crm.leads.leadCreated"), color: "success" });
  createOpen.value = false;
  resetCreateState();
  refresh();
}

function openLead(lead: Lead) {
  navigateTo(`/crm/leads/${lead.id}`);
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="t('crm.leads.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton
            v-if="hasPermission('crm_leads', 'create')"
            icon="i-lucide-plus"
            :label="t('crm.leads.newLead')"
            @click="createOpen = true"
          />
        </template>
      </UDashboardNavbar>

      <UDashboardToolbar>
        <template #left>
          <UInput v-model="search" icon="i-lucide-search" :placeholder="t('crm.leads.searchPlaceholder')" />
        </template>
        <template #right>
          <USelect v-model="statusFilter" :items="statusOptions" value-key="value" />
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
          <UBadge
            :label="t(`crm.leads.status.${row.original.status}`)"
            :color="statusColors[row.original.status]"
            variant="subtle"
          />
        </template>
        <template #assigned-cell="{ row }">
          {{ profileLabel(row.original.assigned_to) }}
        </template>
      </UTable>
    </template>
  </UDashboardPanel>

  <UModal v-model:open="createOpen" :title="t('crm.leads.newLead')">
    <template #body>
      <UForm :schema="schema" :state="state" class="space-y-4" @submit="onCreate">
        <UFormField name="lead_type" :label="t('crm.leads.leadType')">
          <URadioGroup v-model="state.lead_type" orientation="horizontal" :items="leadTypeOptions" value-key="value" />
        </UFormField>

        <UFormField v-if="state.lead_type === 'company'" name="company_name" :label="t('crm.leads.companyName')">
          <UInput v-model="state.company_name" class="w-full" />
        </UFormField>

        <UFormField name="name" :label="state.lead_type === 'company' ? t('crm.leads.contactPerson') : t('common.name')">
          <UInput v-model="state.name" class="w-full" />
        </UFormField>

        <UFormField name="phone" :label="t('common.phone')">
          <UInput v-model="state.phone" class="w-full" />
        </UFormField>
        <UFormField name="phone2" :label="t('crm.leads.phone2')">
          <UInput v-model="state.phone2" class="w-full" />
        </UFormField>
        <UFormField name="email" :label="t('common.email')">
          <UInput v-model="state.email" type="email" class="w-full" />
        </UFormField>
        <UFormField name="source" :label="t('crm.leads.source')">
          <USelect v-model="state.source" :items="sourceOptions" value-key="value" class="w-full" />
        </UFormField>

        <UFormField v-if="canAssign" name="assigned_to" :label="t('crm.leads.assignedTo')">
          <USelect v-model="state.assigned_to" :items="assigneeOptions" value-key="value" class="w-full" />
        </UFormField>
        <p v-else class="text-xs text-muted">
          {{ t("crm.leads.assignHint") }}
        </p>

        <UFormField name="notes" :label="t('crm.leads.notes')">
          <UTextarea v-model="state.notes" class="w-full" :rows="3" />
        </UFormField>

        <UButton type="submit" :label="t('crm.leads.createLead')" :loading="creating" block />
      </UForm>
    </template>
  </UModal>
</template>
