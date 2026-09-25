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
const { t } = useI18n();

interface Lead {
  id: string;
  name: string;
  phone: string | null;
  phone2: string | null;
  email: string | null;
  source: string | null;
  lead_type: string;
  company_name: string | null;
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

const statusKeys = ["new", "contacted", "qualified", "converted", "lost"] as const;
const statusOptions = computed(() =>
  statusKeys.map((s) => ({ label: t(`crm.leads.status.${s}`), value: s })),
);

const leadTypeOptions = computed(() => [
  { label: t("crm.leads.type.individual"), value: "individual" },
  { label: t("crm.leads.type.company"), value: "company" },
]);

const sourceKeys = ["facebook", "instagram", "meta", "google", "website", "event", "referral"] as const;
const sourceOptions = computed(() =>
  sourceKeys.map((s) => ({ label: t(`crm.leads.sourceValues.${s}`), value: s })),
);

const { data: profiles } = await useAsyncData<Profile[]>("crm-lead-profiles", async () => {
  const { data, error } = await supabase.from("profiles").select("id, full_name, email").eq("is_active", true);
  if (error) throw error;
  return data ?? [];
});

const assigneeOptions = computed(() => [
  { label: t("common.unassigned"), value: null },
  ...(profiles.value ?? []).map((p) => ({ label: p.full_name || p.email, value: p.id })),
]);

// Sync from useAsyncData's own `data` (properly hydrated from the SSR
// payload) via watchEffect, rather than only mutating `lead` as a one-off
// side effect inside the handler — that mutation never replays on the
// client when hydrating a fresh/direct page load (only the handler's
// *return value* is transferred through the payload), which left the page
// silently blank on anything but in-app SPA navigation.
const { data: leadPayload, status } = await useAsyncData(`crm-lead-${leadId}`, async () => {
  const { data, error } = await supabase.from("leads").select("*").eq("id", leadId).single();
  if (error) throw error;
  return data;
});
watchEffect(() => {
  if (leadPayload.value) lead.value = leadPayload.value;
});

async function save() {
  if (!lead.value) return;
  saving.value = true;

  const payload: Record<string, unknown> = {
    lead_type: lead.value.lead_type,
    company_name: lead.value.lead_type === "company" ? lead.value.company_name || null : null,
    name: lead.value.name,
    phone: lead.value.phone,
    phone2: lead.value.phone2,
    email: lead.value.email,
    source: lead.value.source,
    status: lead.value.status,
    notes: lead.value.notes,
  };
  if (canAssign.value) payload.assigned_to = lead.value.assigned_to;

  const { error } = await supabase.from("leads").update(payload).eq("id", leadId);
  saving.value = false;

  if (error) {
    toast.add({ title: t("crm.leads.saveFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("crm.leads.leadSaved"), color: "success" });
}

async function convertToCustomer() {
  converting.value = true;
  const { data, error } = await supabase.rpc("crm_convert_lead", { p_lead_id: leadId });
  converting.value = false;

  if (error) {
    toast.add({ title: t("crm.leads.convertFailed"), description: error.message, color: "error" });
    return;
  }

  toast.add({ title: t("crm.leads.convertedSuccess"), color: "success" });
  navigateTo(`/crm/customers/${data}`);
}

async function remove() {
  deleting.value = true;
  const { error } = await supabase.from("leads").delete().eq("id", leadId);
  deleting.value = false;

  if (error) {
    toast.add({ title: t("crm.leads.deleteFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("crm.leads.leadDeleted"), color: "success" });
  navigateTo("/crm/leads");
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="lead?.name ?? t('crm.leads.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton
            v-if="canConvert && lead && !lead.customer_id"
            icon="i-lucide-user-plus"
            :label="t('crm.leads.convertToCustomer')"
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
          :title="t('crm.leads.converted')"
          :description="t('crm.leads.convertedDescription')"
        />

        <UFormField :label="t('crm.leads.leadType')">
          <URadioGroup v-model="lead.lead_type" orientation="horizontal" :items="leadTypeOptions" value-key="value" :disabled="!canEdit" />
        </UFormField>

        <UFormField v-if="lead.lead_type === 'company'" :label="t('crm.leads.companyName')">
          <UInput v-model="lead.company_name" :disabled="!canEdit" class="w-full" />
        </UFormField>

        <UFormField :label="lead.lead_type === 'company' ? t('crm.leads.contactPerson') : t('common.name')">
          <UInput v-model="lead.name" :disabled="!canEdit" class="w-full" />
        </UFormField>
        <UFormField :label="t('common.phone')">
          <UInput v-model="lead.phone" :disabled="!canEdit" class="w-full" />
        </UFormField>
        <UFormField :label="t('crm.leads.phone2')">
          <UInput v-model="lead.phone2" :disabled="!canEdit" class="w-full" />
        </UFormField>
        <UFormField :label="t('common.email')">
          <UInput v-model="lead.email" type="email" :disabled="!canEdit" class="w-full" />
        </UFormField>
        <UFormField :label="t('crm.leads.source')">
          <USelect v-model="lead.source" :items="sourceOptions" value-key="value" :disabled="!canEdit" class="w-full" />
        </UFormField>
        <UFormField :label="t('common.status')">
          <USelect v-model="lead.status" :items="statusOptions" value-key="value" :disabled="!canEdit" class="w-full" />
        </UFormField>
        <UFormField :label="t('crm.leads.assignedTo')">
          <USelect
            v-model="lead.assigned_to"
            :items="assigneeOptions"
            value-key="value"
            :disabled="!canAssign"
            class="w-full"
          />
          <p v-if="!canAssign" class="mt-1 text-xs text-muted">
            {{ t("crm.leads.assignPermissionHint") }}
          </p>
        </UFormField>
        <UFormField :label="t('crm.leads.notes')">
          <UTextarea v-model="lead.notes" :disabled="!canEdit" class="w-full" :rows="4" />
        </UFormField>

        <UButton v-if="canEdit" :label="t('common.save')" :loading="saving" @click="save" />
      </div>
    </template>
  </UDashboardPanel>
</template>
