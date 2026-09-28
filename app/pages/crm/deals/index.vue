<script setup lang="ts">
import * as z from "zod";
import type { FormSubmitEvent, TableColumn } from "@nuxt/ui";

definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "crm_deals" },
});

const supabase = useSupabaseClient();
const user = useSupabaseUser();
const toast = useToast();
const { hasPermission } = usePermissions();
const { t, locale } = useI18n();

interface Pipeline {
  id: string;
  name: string;
  sort_order: number;
}

interface Stage {
  id: string;
  pipeline_id: string;
  name: string;
  sort_order: number;
  is_closed: boolean;
  reason_category: "archive" | "competitor" | null;
  system_key: "new" | "won" | "competitor" | "archive" | "offer_sent" | null;
}

interface Reason {
  id: string;
  pipeline_id: string;
  category: "archive" | "competitor";
  name: string;
}

interface Deal {
  id: string;
  title: string;
  value: number | null;
  customer_id: string | null;
  lead_id: string | null;
  pipeline_id: string;
  stage_id: string;
  assigned_to: string | null;
  created_at: string;
}

interface Customer {
  id: string;
  name: string;
}

interface LeadOption {
  id: string;
  name: string;
  phone: string | null;
  lead_type: "individual" | "company";
  company_name: string | null;
  customer_id: string | null;
}

interface Profile {
  id: string;
  full_name: string | null;
  email: string;
  team_id: string | null;
}

interface Team {
  id: string;
  leader_id: string;
}

const { data: pipelines } = await useAsyncData<Pipeline[]>("crm-deals-pipelines", async () => {
  const { data, error } = await supabase.from("pipelines").select("id, name, sort_order").order("sort_order");
  if (error) throw error;
  return data ?? [];
});

const { data: allStages } = await useAsyncData<Stage[]>("crm-deals-stages", async () => {
  const { data, error } = await supabase
    .from("pipeline_stages")
    .select("id, pipeline_id, name, sort_order, is_closed, reason_category, system_key")
    .order("sort_order");
  if (error) throw error;
  return data ?? [];
});

const { data: allReasons } = await useAsyncData<Reason[]>("crm-deals-reasons", async () => {
  const { data, error } = await supabase
    .from("pipeline_stage_reasons")
    .select("id, pipeline_id, category, name")
    .order("sort_order");
  if (error) throw error;
  return data ?? [];
});

const { data: deals, refresh, status } = await useAsyncData<Deal[]>("crm-deals", async () => {
  const { data, error } = await supabase
    .from("deals")
    .select("id, title, value, customer_id, lead_id, pipeline_id, stage_id, assigned_to, created_at")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data ?? [];
});

const { data: customers, refresh: refreshCustomers } = await useAsyncData<Customer[]>("crm-deals-customers", async () => {
  const { data, error } = await supabase.from("customers").select("id, name").order("name");
  if (error) throw error;
  return data ?? [];
});

const { data: leadsList, refresh: refreshLeads } = await useAsyncData<LeadOption[]>(
  "crm-deals-leads",
  async () => {
    const { data, error } = await supabase
      .from("leads")
      .select("id, name, phone, lead_type, company_name, customer_id")
      .order("created_at", { ascending: false });
    if (error) throw error;
    return data ?? [];
  },
);

const { data: profiles } = await useAsyncData<Profile[]>("crm-deals-profiles", async () => {
  const { data, error } = await supabase
    .from("profiles")
    .select("id, full_name, email, team_id")
    .eq("is_active", true);
  if (error) throw error;
  return data ?? [];
});

// teams is openly readable by any authenticated user (see 0029), so this
// is enough to resolve "do I lead a team, and which one" client-side.
const { data: teams } = await useAsyncData<Team[]>("crm-deals-teams", async () => {
  const { data, error } = await supabase.from("teams").select("id, leader_id");
  if (error) throw error;
  return data ?? [];
});

function customerName(id: string) {
  return customers.value?.find((c) => c.id === id)?.name ?? "—";
}
// Pre-Won a deal has no customer yet — fall back to its lead's name so the
// board still shows who the deal is with.
function dealContactName(deal: Deal) {
  if (deal.customer_id) return customerName(deal.customer_id);
  const lead = leadsList.value?.find((l) => l.id === deal.lead_id);
  if (!lead) return "—";
  return lead.lead_type === "company" && lead.company_name ? lead.company_name : lead.name;
}
const leadOptions = computed(() =>
  (leadsList.value ?? []).map((l) => ({
    label:
      l.lead_type === "company" && l.company_name
        ? `${l.company_name} — ${l.name}`
        : `${l.name}${l.phone ? " · " + l.phone : ""}`,
    value: l.id,
  })),
);
const assigneeOptions = computed(() => [
  { label: t("common.unassigned"), value: null },
  ...(profiles.value ?? []).map((p) => ({ label: p.full_name || p.email, value: p.id })),
]);
function assigneeInitial(id: string | null) {
  const p = profiles.value?.find((p) => p.id === id);
  const label = p?.full_name || p?.email || "";
  return label.charAt(0).toUpperCase();
}

// --- Filter by assignee ---
// useSupabaseUser() returns the decoded JWT claims here, not a full auth
// User object — the id is under `sub`, same as server-side
// serverSupabaseUser() (see server/utils/requireAdmin.ts).
const currentUserId = computed(() => user.value?.sub as string | undefined);

// Who shows up in the picker mirrors the same three-tier visibility used
// everywhere else: view_all sees everyone, a team leader sees their team
// (plus themselves), anyone else only ever sees their own deals anyway (via
// RLS) so they only ever have themselves to pick from.
const myTeam = computed(() => teams.value?.find((tm) => tm.leader_id === currentUserId.value));
const canViewAllDeals = computed(() => hasPermission("crm_deals", "view_all"));

const filterableProfiles = computed(() => {
  if (canViewAllDeals.value) return profiles.value ?? [];
  if (myTeam.value) {
    return (profiles.value ?? []).filter(
      (p) => p.id === currentUserId.value || p.team_id === myTeam.value!.id,
    );
  }
  return (profiles.value ?? []).filter((p) => p.id === currentUserId.value);
});

const assigneeFilterOptions = computed(() => [
  { label: t("common.all"), value: null },
  ...filterableProfiles.value.map((p) => ({ label: p.full_name || p.email, value: p.id })),
]);
// Defaults to the logged-in user, but user.value can still be hydrating
// when this ref is created (Supabase's session fetch is async even after
// route middleware has already let the page through) — so set it
// reactively the first time it's available, rather than only once at setup.
const assigneeFilter = ref<string | null>(null);
const assigneeFilterInitialized = ref(false);
watchEffect(() => {
  if (!assigneeFilterInitialized.value && currentUserId.value) {
    assigneeFilter.value = currentUserId.value;
    assigneeFilterInitialized.value = true;
  }
});

const activePipelineId = ref<string | null>(null);
watchEffect(() => {
  if (!activePipelineId.value && pipelines.value?.length) {
    activePipelineId.value = pipelines.value[0].id;
  }
});

const pipelineTabs = computed(() =>
  (pipelines.value ?? []).map((p) => ({ label: p.name, value: p.id })),
);

const activeStages = computed(() =>
  (allStages.value ?? []).filter((s) => s.pipeline_id === activePipelineId.value),
);

// --- Filter by stage and creation date — shared by both the kanban board
// and the list view below, alongside the existing assignee filter.
const stageFilter = ref<string | null>(null);
const stageFilterOptions = computed(() => [
  { label: t("common.all"), value: null },
  ...activeStages.value.map((s) => ({ label: s.name, value: s.id })),
]);
watch(activePipelineId, () => {
  stageFilter.value = null;
});
const dateFrom = ref("");
const dateTo = ref("");

// The kanban board only renders columns for the stage(s) actually picked —
// narrowing to one stage means seeing just that one column.
const visibleStages = computed(() =>
  stageFilter.value ? activeStages.value.filter((s) => s.id === stageFilter.value) : activeStages.value,
);

function matchesFilters(deal: Deal) {
  if (assigneeFilter.value !== null && deal.assigned_to !== assigneeFilter.value) return false;
  if (stageFilter.value !== null && deal.stage_id !== stageFilter.value) return false;
  if (dateFrom.value && deal.created_at < dateFrom.value) return false;
  if (dateTo.value && deal.created_at.slice(0, 10) > dateTo.value) return false;
  return true;
}

function dealsForStage(stageId: string) {
  return (deals.value ?? []).filter((d) => d.stage_id === stageId && matchesFilters(d));
}

// --- List view — the same pipeline + filters as the kanban board, just
// flattened into a sortable table instead of stage columns.
const viewMode = ref<"kanban" | "list">("kanban");
const listDeals = computed(() =>
  (deals.value ?? []).filter((d) => d.pipeline_id === activePipelineId.value && matchesFilters(d)),
);
function stageName(stageId: string) {
  return allStages.value?.find((s) => s.id === stageId)?.name ?? "—";
}
function formatDate(value: string) {
  return new Date(value).toLocaleDateString(locale.value === "ar" ? "ar" : "en", { dateStyle: "medium" });
}
function profileLabel(id: string | null) {
  if (!id) return t("common.unassigned");
  const p = profiles.value?.find((p) => p.id === id);
  return p?.full_name || p?.email || "?";
}

const UCheckbox = resolveComponent("UCheckbox");
const table = useTemplateRef<any>("dealsTable");
const rowSelection = ref<Record<string, boolean>>({});
const selectedCount = computed<number>(() => table.value?.tableApi?.getFilteredSelectedRowModel().rows.length ?? 0);

const listColumns = computed<TableColumn<Deal>[]>(() => [
  ...(canAssign.value
    ? [
        {
          id: "select",
          header: ({ table }: { table: any }) =>
            h(UCheckbox, {
              modelValue: table.getIsSomePageRowsSelected() ? "indeterminate" : table.getIsAllPageRowsSelected(),
              "onUpdate:modelValue": (value: boolean | "indeterminate") =>
                table.toggleAllPageRowsSelected(!!value),
              "aria-label": t("common.selectAll"),
            }),
          cell: ({ row }: { row: any }) =>
            h(UCheckbox, {
              modelValue: row.getIsSelected(),
              "onUpdate:modelValue": (value: boolean | "indeterminate") => row.toggleSelected(!!value),
              "aria-label": t("common.selectRow"),
              onClick: (e: Event) => e.stopPropagation(),
            }),
        },
      ]
    : []),
  { id: "contact", header: t("crm.deals.contactTitle") },
  { id: "stage", header: t("crm.deals.stage") },
  { accessorKey: "title", header: t("crm.deals.dealTitle") },
  { id: "assigned", header: t("crm.deals.assignedTo") },
  { id: "created", header: t("crm.deals.createdOn") },
]);

// --- Reassign from the list table — single row (inline select) or bulk
// (select several rows, then one picker for all of them). RLS/the deals
// assignment trigger enforce crm_deals:assign server-side regardless, but
// this UI is only offered when the user actually holds it.
const reassigning = ref(false);
async function reassignDeal(dealId: string, assignedTo: string | null) {
  reassigning.value = true;
  const { error } = await supabase.from("deals").update({ assigned_to: assignedTo }).eq("id", dealId);
  reassigning.value = false;
  if (error) {
    toast.add({ title: t("crm.deals.reassignFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("crm.deals.reassigned"), color: "success" });
  refresh();
}

const bulkReassignOpen = ref(false);
const bulkReassignTarget = ref<string | null>(null);
function openBulkReassign() {
  bulkReassignTarget.value = null;
  bulkReassignOpen.value = true;
}
async function confirmBulkReassign() {
  const rows = table.value?.tableApi?.getFilteredSelectedRowModel().rows ?? [];
  const ids = rows.map((r: any) => r.original.id as string);
  if (!ids.length) return;
  reassigning.value = true;
  const { error } = await supabase.from("deals").update({ assigned_to: bulkReassignTarget.value }).in("id", ids);
  reassigning.value = false;
  if (error) {
    toast.add({ title: t("crm.deals.reassignFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("crm.deals.reassigned"), color: "success" });
  bulkReassignOpen.value = false;
  rowSelection.value = {};
  refresh();
}

// --- Create deal ---
// A deal is always created from a lead — either an existing one or a brand
// new one filled in right here — so a rep never has to leave this modal to
// go create a lead/customer first. Behind the scenes the lead is converted
// to a customer (crm_convert_lead), same as the standalone "convert" button
// on the lead page, just folded into one step.
const createOpen = ref(false);
const creating = ref(false);
const showPhone2 = ref(false);
const canAssign = computed(() => hasPermission("crm_deals", "assign"));
const canCreateLead = computed(() => hasPermission("crm_leads", "create"));

const leadTypeOptions = computed(() => [
  { label: t("crm.leads.type.individual"), value: "individual" },
  { label: t("crm.leads.type.company"), value: "company" },
]);
const sourceKeys = ["facebook", "instagram", "meta", "google", "website", "event", "referral"] as const;
const sourceOptions = computed(() => sourceKeys.map((s) => ({ label: t(`crm.leads.sourceValues.${s}`), value: s })));
const leadModeOptions = computed(() => {
  const opts = [{ label: t("crm.deals.existingLead"), value: "existing" as const }];
  if (canCreateLead.value) opts.push({ label: t("crm.leads.newLead"), value: "new" as const });
  return opts;
});

const schema = computed(() =>
  z
    .object({
      lead_mode: z.enum(["existing", "new"]),
      existing_lead_id: z.uuid().optional(),
      lead_type: z.enum(["individual", "company"]).optional(),
      company_name: z.string().optional(),
      lead_name: z.string().optional(),
      lead_phone: z.string().optional(),
      lead_phone2: z.string().optional(),
      lead_email: z.string().optional(),
      lead_source: z.enum(sourceKeys).optional(),
      lead_notes: z.string().optional(),
      title: z.string().min(1, t("validation.required")),
      pipeline_id: z.uuid(t("validation.required")),
      stage_id: z.uuid(t("validation.required")),
      stage_reason_id: z.uuid().nullable().optional(),
      assigned_to: z.uuid().nullable().optional(),
    })
    .superRefine((data, ctx) => {
      const stage = allStages.value?.find((s) => s.id === data.stage_id);
      if (stage?.reason_category && !data.stage_reason_id) {
        ctx.addIssue({ message: t("validation.required"), path: ["stage_reason_id"] });
      }
      if (data.lead_mode === "existing" && !data.existing_lead_id) {
        ctx.addIssue({ message: t("validation.required"), path: ["existing_lead_id"] });
      }
      if (data.lead_mode === "new") {
        if (!data.lead_name?.trim()) ctx.addIssue({ message: t("validation.required"), path: ["lead_name"] });
        if (!data.lead_phone?.trim()) ctx.addIssue({ message: t("validation.required"), path: ["lead_phone"] });
        if (!data.lead_source) ctx.addIssue({ message: t("validation.required"), path: ["lead_source"] });
        if (data.lead_type === "company" && !data.company_name?.trim()) {
          ctx.addIssue({ message: t("validation.required"), path: ["company_name"] });
        }
      }
    }),
);
type Schema = {
  lead_mode: "existing" | "new";
  existing_lead_id?: string;
  lead_type?: "individual" | "company";
  company_name?: string;
  lead_name?: string;
  lead_phone?: string;
  lead_phone2?: string;
  lead_email?: string;
  lead_source?: (typeof sourceKeys)[number];
  lead_notes?: string;
  title: string;
  pipeline_id: string;
  stage_id: string;
  stage_reason_id?: string | null;
  assigned_to?: string | null;
};

function blankState(): Partial<Schema> {
  return {
    lead_mode: leadOptions.value.length ? "existing" : "new",
    existing_lead_id: undefined,
    lead_type: "individual",
    company_name: "",
    lead_name: "",
    lead_phone: "",
    lead_phone2: "",
    lead_email: "",
    lead_source: undefined,
    lead_notes: "",
    title: "",
    pipeline_id: undefined,
    stage_id: undefined,
    stage_reason_id: null,
    assigned_to: null,
  };
}
const state = reactive<Partial<Schema>>(blankState());

const createPipelineStages = computed(() =>
  (allStages.value ?? []).filter((s) => s.pipeline_id === state.pipeline_id),
);
const createStage = computed(() => allStages.value?.find((s) => s.id === state.stage_id));
const createReasonOptions = computed(() =>
  (allReasons.value ?? [])
    .filter((r) => r.pipeline_id === state.pipeline_id && r.category === createStage.value?.reason_category)
    .map((r) => ({ label: r.name, value: r.id })),
);

function openCreate() {
  Object.assign(state, blankState());
  state.pipeline_id = activePipelineId.value ?? undefined;
  const firstStage = createPipelineStages.value[0];
  state.stage_id = firstStage?.id;
  showPhone2.value = false;
  createOpen.value = true;
}

watch(
  () => state.pipeline_id,
  () => {
    const firstStage = createPipelineStages.value[0];
    state.stage_id = firstStage?.id;
    state.stage_reason_id = null;
  },
);
watch(
  () => state.stage_id,
  () => {
    state.stage_reason_id = null;
  },
);

async function onCreate(event: FormSubmitEvent<Schema>) {
  creating.value = true;

  let leadId: string;
  // A lead only becomes a customer once its deal is actually Won — not at
  // deal-creation time (quotes and the rest of the pipeline run fine
  // against a lead alone). Reuse an already-converted lead's customer if
  // it has one either way.
  let customerId: string | null = null;

  if (event.data.lead_mode === "existing") {
    leadId = event.data.existing_lead_id!;
    const existingLead = leadsList.value?.find((l) => l.id === leadId);
    customerId = existingLead?.customer_id ?? null;
  } else {
    const leadPayload: Record<string, unknown> = {
      lead_type: event.data.lead_type,
      company_name: event.data.lead_type === "company" ? event.data.company_name || null : null,
      name: event.data.lead_name,
      phone: event.data.lead_phone?.trim(),
      phone2: trimOrNull(event.data.lead_phone2),
      email: event.data.lead_email || null,
      source: event.data.lead_source,
      notes: event.data.lead_notes || null,
    };
    if (canAssign.value) leadPayload.assigned_to = event.data.assigned_to || null;

    const { data: newLead, error: leadError } = await supabase
      .from("leads")
      .insert(leadPayload)
      .select("id")
      .single();
    if (leadError) {
      creating.value = false;
      toast.add({ title: t("crm.leads.createLeadFailed"), description: leadError.message, color: "error" });
      return;
    }
    leadId = newLead.id;
  }

  // A deal can also be created directly into the Won stage — convert right
  // away in that one case, same as a later stage-change into Won would.
  const selectedStage = allStages.value?.find((s) => s.id === event.data.stage_id);
  if (selectedStage?.system_key === "won" && !customerId) {
    const { customerId: resolved, error } = await resolveWonCustomerId(supabase, leadId);
    if (error || !resolved) {
      creating.value = false;
      const description = error === "no_lead" ? t("crm.deals.noLeadForConversion") : error;
      toast.add({ title: t("crm.deals.createDealFailed"), description: description ?? undefined, color: "error" });
      return;
    }
    customerId = resolved;
  }

  const payload: Record<string, unknown> = {
    title: event.data.title,
    customer_id: customerId,
    lead_id: leadId,
    pipeline_id: event.data.pipeline_id,
    stage_id: event.data.stage_id,
    stage_reason_id: event.data.stage_reason_id || null,
  };
  if (canAssign.value) payload.assigned_to = event.data.assigned_to || null;

  const { error } = await supabase.from("deals").insert(payload);
  creating.value = false;

  if (error) {
    toast.add({ title: t("crm.deals.createDealFailed"), description: error.message, color: "error" });
    return;
  }

  toast.add({ title: t("crm.deals.dealCreated"), color: "success" });
  createOpen.value = false;
  Object.assign(state, blankState());
  refresh();
  refreshLeads();
  refreshCustomers();
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
            @click="openCreate"
          />
        </template>
      </UDashboardNavbar>

      <UDashboardToolbar>
        <template #left>
          <UTabs v-model="activePipelineId" :items="pipelineTabs" value-key="value" />
        </template>
        <template #right>
          <div class="flex flex-wrap items-center gap-2">
            <USelectMenu
              v-model="assigneeFilter"
              :items="assigneeFilterOptions"
              value-key="value"
              :icon="'i-lucide-user'"
              :placeholder="t('crm.deals.assignedTo')"
              searchable
              class="w-48"
            />
            <USelectMenu
              v-model="stageFilter"
              :items="stageFilterOptions"
              value-key="value"
              :icon="'i-lucide-git-branch'"
              :placeholder="t('crm.deals.stage')"
              class="w-44"
            />
            <UInput v-model="dateFrom" type="date" :placeholder="t('crm.deals.createdFrom')" class="w-40" />
            <UInput v-model="dateTo" type="date" :placeholder="t('crm.deals.createdTo')" class="w-40" />
            <UButtonGroup>
              <UButton
                icon="i-lucide-kanban"
                :color="viewMode === 'kanban' ? 'primary' : 'neutral'"
                :variant="viewMode === 'kanban' ? 'solid' : 'outline'"
                :aria-label="t('crm.deals.kanbanView')"
                @click="viewMode = 'kanban'"
              />
              <UButton
                icon="i-lucide-list"
                :color="viewMode === 'list' ? 'primary' : 'neutral'"
                :variant="viewMode === 'list' ? 'solid' : 'outline'"
                :aria-label="t('crm.deals.listView')"
                @click="viewMode = 'list'"
              />
            </UButtonGroup>
          </div>
        </template>
      </UDashboardToolbar>
    </template>

    <template #body>
      <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>

      <div v-else-if="viewMode === 'kanban'" class="flex gap-4 overflow-x-auto pb-4">
        <div
          v-for="stage in visibleStages"
          :key="stage.id"
          class="w-64 shrink-0 rounded-lg border border-default"
          :class="stage.is_closed ? 'bg-elevated' : 'bg-default'"
        >
          <div class="flex items-center justify-between border-b border-default p-3">
            <span class="font-medium text-highlighted">{{ stage.name }}</span>
            <UBadge :label="String(dealsForStage(stage.id).length)" color="neutral" variant="subtle" />
          </div>
          <div class="space-y-2 p-2">
            <div
              v-for="deal in dealsForStage(stage.id)"
              :key="deal.id"
              class="cursor-pointer rounded-md border border-default bg-default p-2 text-sm hover:border-primary"
              @click="openDeal(deal)"
            >
              <div class="font-medium text-highlighted">{{ dealContactName(deal) }}</div>
              <div class="text-muted">{{ deal.title }}</div>
              <div v-if="deal.assigned_to" class="mt-1 flex items-center gap-1.5 text-xs text-muted">
                <UAvatar :text="assigneeInitial(deal.assigned_to)" size="2xs" />
                <span>{{ profileLabel(deal.assigned_to) }}</span>
              </div>
              <div v-if="deal.value" class="text-muted">{{ deal.value }}</div>
            </div>
            <div v-if="dealsForStage(stage.id).length === 0" class="py-4 text-center text-xs text-muted">
              {{ t("crm.deals.noDealsInStage") }}
            </div>
          </div>
        </div>
      </div>

      <template v-else>
        <div v-if="canAssign && selectedCount > 0" class="mb-3 flex items-center gap-3">
          <span class="text-sm text-muted">{{ t("crm.deals.selectedCount", { count: selectedCount }) }}</span>
          <UButton
            icon="i-lucide-user-check"
            size="sm"
            variant="soft"
            :label="t('crm.deals.bulkReassign')"
            @click="openBulkReassign"
          />
        </div>
        <UTable
          ref="dealsTable"
          v-model:row-selection="rowSelection"
          :data="listDeals"
          :columns="listColumns"
          @select="(_e, row) => openDeal(row.original)"
        >
          <template #stage-cell="{ row }">
            {{ stageName(row.original.stage_id) }}
          </template>
          <template #contact-cell="{ row }">
            {{ dealContactName(row.original) }}
          </template>
          <template #assigned-cell="{ row }">
            <USelect
              v-if="canAssign"
              :model-value="row.original.assigned_to"
              :items="assigneeOptions"
              value-key="value"
              size="xs"
              class="w-40"
              @click.stop
              @update:model-value="(value: string | null) => reassignDeal(row.original.id, value)"
            />
            <span v-else>{{ profileLabel(row.original.assigned_to) }}</span>
          </template>
          <template #created-cell="{ row }">
            {{ formatDate(row.original.created_at) }}
          </template>
        </UTable>
      </template>
    </template>
  </UDashboardPanel>

  <UModal v-model:open="createOpen" :title="t('crm.deals.newDeal')">
    <template #body>
      <UForm :schema="schema" :state="state" class="space-y-4" @submit="onCreate">
        <UFormField name="lead_mode" :label="t('crm.deals.leadSourceLabel')">
          <URadioGroup
            v-model="state.lead_mode"
            orientation="horizontal"
            :items="leadModeOptions"
            value-key="value"
          />
        </UFormField>

        <template v-if="state.lead_mode === 'existing'">
          <UFormField name="existing_lead_id" :label="t('crm.deals.selectLead')">
            <USelectMenu
              v-model="state.existing_lead_id"
              :items="leadOptions"
              value-key="value"
              searchable
              class="w-full"
            />
          </UFormField>
        </template>

        <template v-else>
          <UFormField name="lead_type" :label="t('crm.leads.leadType')">
            <URadioGroup v-model="state.lead_type" orientation="horizontal" :items="leadTypeOptions" value-key="value" />
          </UFormField>
          <UFormField v-if="state.lead_type === 'company'" name="company_name" :label="t('crm.leads.companyName')">
            <UInput v-model="state.company_name" class="w-full" />
          </UFormField>
          <UFormField
            name="lead_name"
            :label="state.lead_type === 'company' ? t('crm.leads.contactPerson') : t('common.name')"
          >
            <UInput v-model="state.lead_name" class="w-full" />
          </UFormField>
          <UFormField name="lead_phone" :label="t('common.phone')">
            <UInput v-model="state.lead_phone" class="w-full">
              <template v-if="!showPhone2" #trailing>
                <UButton
                  icon="i-lucide-plus"
                  size="xs"
                  color="neutral"
                  variant="ghost"
                  :aria-label="t('crm.leads.phone2')"
                  @click="showPhone2 = true"
                />
              </template>
            </UInput>
          </UFormField>
          <UFormField v-if="showPhone2" name="lead_phone2" :label="t('crm.leads.phone2')">
            <UInput v-model="state.lead_phone2" class="w-full" />
          </UFormField>
          <UFormField name="lead_email" :label="t('common.email')">
            <UInput v-model="state.lead_email" type="email" class="w-full" />
          </UFormField>
          <UFormField name="lead_source" :label="t('crm.leads.source')">
            <USelect v-model="state.lead_source" :items="sourceOptions" value-key="value" class="w-full" />
          </UFormField>
        </template>

        <USeparator />

        <UFormField name="title" :label="t('crm.deals.dealTitle')">
          <UInput v-model="state.title" class="w-full" />
        </UFormField>
        <UFormField name="pipeline_id" :label="t('crm.deals.pipeline')">
          <USelect v-model="state.pipeline_id" :items="pipelineTabs" value-key="value" class="w-full" />
        </UFormField>
        <UFormField name="stage_id" :label="t('crm.deals.stage')">
          <USelect
            v-model="state.stage_id"
            :items="createPipelineStages.map((s) => ({ label: s.name, value: s.id }))"
            value-key="value"
            class="w-full"
          />
        </UFormField>
        <UFormField v-if="createStage?.reason_category" name="stage_reason_id" :label="t('crm.deals.reason')">
          <USelect v-model="state.stage_reason_id" :items="createReasonOptions" value-key="value" class="w-full" />
        </UFormField>
        <UFormField v-if="canAssign" name="assigned_to" :label="t('crm.deals.assignedTo')">
          <USelect v-model="state.assigned_to" :items="assigneeOptions" value-key="value" class="w-full" />
        </UFormField>
        <p v-else class="text-xs text-muted">{{ t("crm.deals.assignCreateHint") }}</p>
        <UFormField v-if="state.lead_mode === 'new'" name="lead_notes" :label="t('crm.leads.notes')">
          <UTextarea v-model="state.lead_notes" class="w-full" :rows="2" />
        </UFormField>
        <UButton type="submit" :label="t('crm.deals.createDeal')" :loading="creating" block />
      </UForm>
    </template>
  </UModal>

  <UModal v-model:open="bulkReassignOpen" :title="t('crm.deals.bulkReassignTitle', { count: selectedCount })">
    <template #body>
      <div class="space-y-3">
        <USelect
          v-model="bulkReassignTarget"
          :items="assigneeOptions"
          value-key="value"
          class="w-full"
        />
        <UButton
          :label="t('crm.deals.bulkReassign')"
          :loading="reassigning"
          block
          @click="confirmBulkReassign"
        />
      </div>
    </template>
  </UModal>
</template>
