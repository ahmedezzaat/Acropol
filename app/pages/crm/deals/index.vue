<script setup lang="ts">
import * as z from "zod";
import type { FormSubmitEvent, TableColumn } from "@nuxt/ui";
import { getPaginationRowModel } from "@tanstack/vue-table";

definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "crm_deals" },
});

useHead({ htmlAttrs: { class: "carbon" } });

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
  max_stay_days: number | null;
  max_stay_hours: number | null;
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
  stage_reason_id: string | null;
}

interface Customer {
  id: string;
  name: string;
  phone: string | null;
}

interface LeadOption {
  id: string;
  name: string;
  phone: string | null;
  phone2: string | null;
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
    .select("id, pipeline_id, name, sort_order, is_closed, reason_category, system_key, max_stay_days, max_stay_hours")
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

interface ProductCategory {
  id: string;
  name: string;
}

const { data: productCategories } = await useAsyncData<ProductCategory[]>("crm-deals-product-categories", async () => {
  const { data, error } = await supabase.from("product_categories").select("id, name").order("sort_order");
  if (error) throw error;
  return data ?? [];
});
const categoryItems = computed(() => (productCategories.value ?? []).map((c) => ({ label: c.name, value: c.id })));

const { data: deals, refresh, status } = await useAsyncData<Deal[]>("crm-deals", async () => {
  const { data, error } = await supabase
    .from("deals")
    .select("id, title, value, customer_id, lead_id, pipeline_id, stage_id, assigned_to, created_at, stage_reason_id")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data ?? [];
});

const { data: customers, refresh: refreshCustomers } = await useAsyncData<Customer[]>("crm-deals-customers", async () => {
  const { data, error } = await supabase.from("customers").select("id, name, phone").order("name");
  if (error) throw error;
  return data ?? [];
});

// Latest note per deal, for the Kanban card and list view — fetched newest
// first so the first row seen per deal_id is already its latest note.
const { data: noteActivities } = await useAsyncData<{ deal_id: string; content: string | null }[]>(
  "crm-deals-last-notes",
  async () => {
    const { data, error } = await supabase
      .from("deal_activities")
      .select("deal_id, content, created_at")
      .eq("type", "note")
      .order("created_at", { ascending: false });
    if (error) throw error;
    return data ?? [];
  },
);
const lastNoteByDeal = computed(() => {
  const map = new Map<string, string>();
  for (const a of noteActivities.value ?? []) {
    if (!map.has(a.deal_id) && a.content) map.set(a.deal_id, a.content);
  }
  return map;
});
function lastNote(dealId: string) {
  return lastNoteByDeal.value.get(dealId) ?? null;
}

// Time a deal has spent in its current stage — the most recent
// stage_changed activity's timestamp is exactly when it entered whatever
// stage it's on now; a deal that's never moved falls back to its creation
// date.
const { data: stageChangeActivities } = await useAsyncData<{ deal_id: string; created_at: string }[]>(
  "crm-deals-stage-changes",
  async () => {
    const { data, error } = await supabase
      .from("deal_activities")
      .select("deal_id, created_at")
      .eq("type", "stage_changed")
      .order("created_at", { ascending: false });
    if (error) throw error;
    return data ?? [];
  },
);
const stageEnteredAtByDeal = computed(() => {
  const map = new Map<string, string>();
  for (const a of stageChangeActivities.value ?? []) {
    if (!map.has(a.deal_id)) map.set(a.deal_id, a.created_at);
  }
  return map;
});
function stageEnteredAt(deal: Deal) {
  return stageEnteredAtByDeal.value.get(deal.id) ?? deal.created_at;
}
// Capped at 14 days for the bar fill — past that it's just "very stale" and
// the exact ratio stops being useful; the label still shows the real count.
const STAGE_AGE_CAP_DAYS = 14;
function stageAgeDays(deal: Deal) {
  // Clamp negative — clock skew between this client and the server can put
  // a just-created deal's timestamp a hair in the "future".
  return Math.max(0, Date.now() - new Date(stageEnteredAt(deal)).getTime()) / 86400000;
}
function stageAgeLabel(deal: Deal) {
  const days = stageAgeDays(deal);
  if (days < 1) {
    const hours = Math.max(1, Math.round(days * 24));
    return t("crm.deals.stageAgeHours", { count: hours });
  }
  return t("crm.deals.stageAgeDays", { count: Math.round(days) });
}
function stageAgeTextClass(deal: Deal) {
  return { success: "text-success", warning: "text-warning", error: "text-error" }[stageAgeColor(deal)];
}
function stageAgeRatio(deal: Deal) {
  return Math.min(stageAgeDays(deal) / STAGE_AGE_CAP_DAYS, 1) * 100;
}
function stageAgeColor(deal: Deal): "success" | "warning" | "error" {
  // Past the stage's configured limit always reads as an error, whatever
  // the raw age — the bar, the label and the alert icon should agree.
  if (isStageOverdue(deal)) return "error";
  const days = stageAgeDays(deal);
  if (days < 3) return "success";
  if (days < 7) return "warning";
  return "error";
}
// null means the stage has no configured limit — nothing to flag against.
function stageStayLimitDays(deal: Deal) {
  const stage = allStages.value?.find((s) => s.id === deal.stage_id);
  if (!stage || (stage.max_stay_days == null && stage.max_stay_hours == null)) return null;
  return (stage.max_stay_days ?? 0) + (stage.max_stay_hours ?? 0) / 24;
}
function isStageOverdue(deal: Deal) {
  const limit = stageStayLimitDays(deal);
  return limit !== null && stageAgeDays(deal) > limit;
}

const { data: leadsList, refresh: refreshLeads } = await useAsyncData<LeadOption[]>(
  "crm-deals-leads",
  async () => {
    const { data, error } = await supabase
      .from("leads")
      .select("id, name, phone, phone2, lead_type, company_name, customer_id")
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
function dealContactPhone(deal: Deal) {
  if (deal.customer_id) return customers.value?.find((c) => c.id === deal.customer_id)?.phone ?? null;
  return leadsList.value?.find((l) => l.id === deal.lead_id)?.phone ?? null;
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

// Sentinel for the "Unassigned" choice — null already means "no filter".
const UNASSIGNED = "__unassigned__";
const assigneeFilterOptions = computed(() => [
  { label: t("common.all"), value: null },
  { label: t("common.unassigned"), value: UNASSIGNED },
  ...filterableProfiles.value.map((p) => ({ label: p.full_name || p.email, value: p.id })),
]);
// Defaults to the logged-in user, but user.value can still be hydrating
// when this ref is created (Supabase's session fetch is async even after
// route middleware has already let the page through) — so set it
// reactively the first time it's available, rather than only once at setup.
// A notification can open this page pre-filtered to unassigned deals
// (?assignee=unassigned, optionally &pipeline=<id>&stage=<id>) so a manager can
// reassign them straight away.
const route = useRoute();
const openedAsUnassigned = route.query.assignee === "unassigned";
const assigneeFilter = ref<string | null>(openedAsUnassigned ? UNASSIGNED : null);
const assigneeFilterInitialized = ref(openedAsUnassigned);
watchEffect(() => {
  if (!assigneeFilterInitialized.value && currentUserId.value) {
    assigneeFilter.value = currentUserId.value;
    assigneeFilterInitialized.value = true;
  }
});

const activePipelineId = ref<string | null>(null);
watchEffect(() => {
  if (!activePipelineId.value && pipelines.value?.length) {
    const requested = typeof route.query.pipeline === "string" ? route.query.pipeline : null;
    activePipelineId.value = pipelines.value.find((p) => p.id === requested)?.id ?? pipelines.value[0].id;
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
const stageFilter = ref<string | null>(typeof route.query.stage === "string" ? route.query.stage : null);
const stageFilterOptions = computed(() => [
  { label: t("common.all"), value: null },
  ...activeStages.value.map((s) => ({ label: s.name, value: s.id })),
]);
watch(activePipelineId, (_next, previous) => {
  // The first assignment (null -> initial pipeline) must keep a stage that
  // arrived via the URL; only a real pipeline switch clears it.
  if (previous !== null) stageFilter.value = null;
});
const dateFrom = ref("");
const dateTo = ref("");
const dealSearch = ref("");

// The kanban board only renders columns for the stage(s) actually picked —
// narrowing to one stage means seeing just that one column.
const visibleStages = computed(() =>
  stageFilter.value ? activeStages.value.filter((s) => s.id === stageFilter.value) : activeStages.value,
);

function matchesFilters(deal: Deal) {
  if (assigneeFilter.value === UNASSIGNED) {
    if (deal.assigned_to !== null) return false;
  } else if (assigneeFilter.value !== null && deal.assigned_to !== assigneeFilter.value) return false;
  if (stageFilter.value !== null && deal.stage_id !== stageFilter.value) return false;
  if (dateFrom.value && deal.created_at < dateFrom.value) return false;
  if (dateTo.value && deal.created_at.slice(0, 10) > dateTo.value) return false;
  if (dealSearch.value) {
    const q = dealSearch.value.toLowerCase();
    const matchesName = dealContactName(deal).toLowerCase().includes(q);
    const matchesPhone = phoneMatches(dealContactPhone(deal), dealSearch.value);
    if (!matchesName && !matchesPhone) return false;
  }
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
// Only archive/competitor stages carry a reason — nothing to show otherwise.
function dealReasonName(deal: Deal) {
  const stage = allStages.value?.find((s) => s.id === deal.stage_id);
  if (!stage?.reason_category || !deal.stage_reason_id) return null;
  return allReasons.value?.find((r) => r.id === deal.stage_reason_id)?.name ?? null;
}
function formatDate(value: string) {
  return new Date(value).toLocaleDateString(locale.value === "ar" ? "ar" : "en", { dateStyle: "medium" });
}
function formatCurrency(value: number | null) {
  if (!value) return null;
  // Always Western digits with thousands separators — matches how dates
  // and every other number in this app render regardless of locale; only
  // the currency label itself follows the language.
  const amount = value.toLocaleString("en-US", { maximumFractionDigits: 0 });
  return `${amount} ${t("common.currency")}`;
}
// Drives both the Kanban column's accent bar and the list view's stage
// badge color — closed-won reads as success, closed-lost/archived as
// error/neutral, anything still open stays primary.
function stageAccentColor(stage: Stage | undefined): "success" | "error" | "neutral" | "primary" {
  if (!stage) return "neutral";
  if (stage.system_key === "won") return "success";
  if (stage.system_key === "competitor" || stage.reason_category === "competitor") return "error";
  if (stage.system_key === "archive" || stage.reason_category === "archive") return "neutral";
  return "primary";
}
function stageTotalValue(stageId: string) {
  return dealsForStage(stageId).reduce((sum, d) => sum + (d.value ?? 0), 0);
}
function sortIcon(column: { getIsSorted: () => false | "asc" | "desc" }) {
  const dir = column.getIsSorted();
  if (dir === "asc") return "i-lucide-arrow-up";
  if (dir === "desc") return "i-lucide-arrow-down";
  return "i-lucide-arrow-up-down";
}
function stageAccentBorderClass(stage: Stage) {
  return {
    success: "border-t-success",
    error: "border-t-error",
    primary: "border-t-primary",
    neutral: "border-t-default",
  }[stageAccentColor(stage)];
}
// The "Customer is interested in" title is a "، "-joined list of product
// categories (see onCreate) — split it back out for chip display. Legacy
// free-text titles (pre-dating that field) just render as a single chip.
function dealCategories(deal: Deal) {
  return deal.title ? deal.title.split(/[،,]\s*/).filter(Boolean) : [];
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
const sorting = ref([{ id: "created", desc: true }]);
const pagination = ref({ pageIndex: 0, pageSize: 20 });
// Any filter changing the row set should land the user back on page 1
// instead of possibly showing an empty out-of-range page.
watch([assigneeFilter, stageFilter, dateFrom, dateTo, dealSearch, activePipelineId], () => {
  pagination.value.pageIndex = 0;
});

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
  {
    id: "stageAge",
    accessorFn: (row) => stageAgeDays(row),
    header: t("crm.deals.timeInStage"),
  },
  { id: "reason", header: t("crm.deals.reason") },
  { accessorKey: "title", header: t("crm.deals.dealTitle") },
  { accessorKey: "value", header: t("crm.deals.value") },
  { id: "assigned", header: t("crm.deals.assignedTo") },
  { accessorKey: "created_at", id: "created", header: t("crm.deals.createdOn") },
  { id: "lastNote", header: t("crm.deals.lastNote") },
]);

// --- Reassign from the list table — single row (inline select opens this
// same modal, pre-filled) or bulk (select several rows, then one picker for
// all of them). Every reassignment also requires picking the deal's stage
// (kept at its current stage by default for a single deal, forced to an
// explicit choice for bulk since selected deals can span different
// stages) and a history-visibility choice — "hide" stamps
// history_hidden_before so everything up to now drops out of the timeline
// for anyone without crm_deals view_all (RLS-enforced, not just hidden in
// the UI), while view_all always sees the full history regardless. RLS/the
// deals assignment trigger enforce crm_deals:assign server-side regardless,
// but this UI is only offered when the user actually holds it.
const reassigning = ref(false);
const reassignOpen = ref(false);
const reassignDealIds = ref<string[]>([]);
const reassignTarget = ref<string | null>(null);
const reassignStageId = ref<string | null>(null);
const reassignReasonId = ref<string | null>(null);
const reassignHideHistory = ref(false);

const reassignStage = computed(() => allStages.value?.find((s) => s.id === reassignStageId.value));
const reassignReasonOptions = computed(() =>
  (allReasons.value ?? [])
    .filter((r) => r.pipeline_id === activePipelineId.value && r.category === reassignStage.value?.reason_category)
    .map((r) => ({ label: r.name, value: r.id })),
);
const reassignValid = computed(
  () => !!reassignStageId.value && (!reassignStage.value?.reason_category || !!reassignReasonId.value),
);

function openReassign(dealIds: string[], prefillAssignee?: string | null) {
  reassignDealIds.value = dealIds;
  reassignTarget.value = prefillAssignee ?? null;
  // A single deal defaults to staying on its current stage (still an
  // explicit, changeable choice); bulk has no single sensible default
  // since the selected deals can already be on different stages.
  reassignStageId.value =
    dealIds.length === 1 ? (deals.value?.find((d) => d.id === dealIds[0])?.stage_id ?? null) : null;
  reassignReasonId.value = null;
  reassignHideHistory.value = false;
  reassignOpen.value = true;
}
function openBulkReassign() {
  const rows = table.value?.tableApi?.getFilteredSelectedRowModel().rows ?? [];
  openReassign(rows.map((r: any) => r.original.id as string));
}

async function confirmReassign() {
  if (!reassignValid.value || !reassignDealIds.value.length) return;
  reassigning.value = true;

  const updates: Record<string, unknown> = {
    assigned_to: reassignTarget.value,
    stage_id: reassignStageId.value,
    stage_reason_id: reassignStage.value?.reason_category ? reassignReasonId.value : null,
  };
  if (reassignHideHistory.value) updates.history_hidden_before = new Date().toISOString();

  let error: { message: string } | null = null;
  if (reassignStage.value?.system_key === "won") {
    // Each deal's customer has to be resolved individually (different
    // leads), so this one case can't be a single batch update.
    for (const dealId of reassignDealIds.value) {
      const deal = deals.value?.find((d) => d.id === dealId);
      if (deal?.customer_id) {
        ({ error } = await supabase.from("deals").update(updates).eq("id", dealId));
      } else {
        const { customerId, error: resolveError } = await resolveWonCustomerId(supabase, deal?.lead_id ?? null);
        if (resolveError || !customerId) {
          error = { message: resolveError ?? "conversion failed" };
        } else {
          ({ error } = await supabase.from("deals").update({ ...updates, customer_id: customerId }).eq("id", dealId));
        }
      }
      if (error) break;
    }
  } else {
    ({ error } = await supabase.from("deals").update(updates).in("id", reassignDealIds.value));
  }

  reassigning.value = false;
  if (error) {
    toast.add({ title: t("crm.deals.reassignFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("crm.deals.reassigned"), color: "success" });
  reassignOpen.value = false;
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
const sourceKeys = ["external_client", "facebook", "instagram", "meta", "google", "website", "event", "referral", "whatsapp", "api"] as const;
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
      category_ids: z.array(z.uuid()).min(1, t("validation.required")),
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
  category_ids: string[];
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
    category_ids: [],
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

// Catch the common case of a rep (re-)entering a lead someone already has,
// by matching on phone regardless of formatting (local "0...", "+20...",
// with/without spaces). Only checks leads this user can already see (same
// own/team/view_all scoping as everywhere else), not a global lookup.
const duplicateNewLead = computed(() => {
  if (state.lead_mode !== "new") return null;
  const candidates = [phoneDigits(state.lead_phone), phoneDigits(state.lead_phone2)].filter(
    (d): d is string => !!d,
  );
  if (!candidates.length) return null;
  return (
    leadsList.value?.find((l) => {
      const existing = [phoneDigits(l.phone), phoneDigits(l.phone2)].filter((d): d is string => !!d);
      return existing.some((e) => candidates.includes(e));
    }) ?? null
  );
});

async function onCreate(event: FormSubmitEvent<Schema>) {
  if (duplicateNewLead.value) return;
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

  const categoryNames = (productCategories.value ?? [])
    .filter((c) => event.data.category_ids.includes(c.id))
    .map((c) => c.name);

  const payload: Record<string, unknown> = {
    title: categoryNames.join("، "),
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

// --- Mobile filter sheet ---
const filtersOpen = ref(false);
const activeFilterCount = computed(
  () => [assigneeFilter.value !== null, !!stageFilter.value, !!dateFrom.value, !!dateTo.value].filter(Boolean).length,
);
function clearFilters() {
  stageFilter.value = null;
  dateFrom.value = "";
  dateTo.value = "";
  dealSearch.value = "";
}

// The list view collapses to cards below md (a 9-column table is unusable on
// a phone); they share the table's pagination state.
const pagedListDeals = computed(() =>
  listDeals.value.slice(
    pagination.value.pageIndex * pagination.value.pageSize,
    (pagination.value.pageIndex + 1) * pagination.value.pageSize,
  ),
);

function openDeal(deal: Deal) {
  navigateTo(`/crm/deals/${deal.id}`, { open: { target: "_blank" } });
}
</script>

<template>
  <!-- In Kanban mode the panel is exactly one screen tall, so the board gets a
  definite height and every stage column scrolls on its own (the panel's
  default is only a minimum height, which lets the page grow instead). -->
  <UDashboardPanel :ui="{ root: viewMode === 'kanban' ? 'h-svh' : '' }">
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

      <!-- Mobile-first toolbar: pipeline tabs scroll sideways, search + a
      Filters button + view toggle share one row; the individual filters live
      in a bottom sheet until there is room (lg) to show them inline. -->
      <div class="w-full space-y-3 border-b border-default px-4 py-3 sm:px-6">
        <div class="-mx-4 overflow-x-auto overflow-y-hidden px-4 [scrollbar-width:none] sm:mx-0 sm:px-0 [&::-webkit-scrollbar]:hidden">
          <UTabs v-model="activePipelineId" :items="pipelineTabs" value-key="value" variant="link" :content="false" class="w-max min-w-full" />
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <UInput
            v-model="dealSearch"
            icon="i-lucide-search"
            :placeholder="t('crm.deals.searchPlaceholder')"
            class="min-w-0 flex-1 basis-40 lg:max-w-56 lg:flex-none"
          />
          <UChip :show="activeFilterCount > 0" :text="String(activeFilterCount)" size="2xl" class="lg:hidden">
            <UButton
              icon="i-lucide-sliders-horizontal"
              color="neutral"
              variant="outline"
              :aria-label="t('crm.deals.filters')"
              @click="filtersOpen = true"
            />
          </UChip>
          <div class="hidden flex-wrap items-center gap-2 lg:flex">
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
            <UButton
              v-if="stageFilter || dateFrom || dateTo || dealSearch"
              icon="i-lucide-x"
              color="neutral"
              variant="ghost"
              size="sm"
              :label="t('crm.deals.clearFilters')"
              @click="clearFilters"
            />
            <USeparator orientation="vertical" class="h-6" />
          </div>
          <UButtonGroup class="ms-auto lg:ms-0">
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
      </div>
    </template>

    <template #body>
      <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>

      <div
        v-else-if="viewMode === 'kanban'"
        class="-mx-4 flex min-h-0 flex-1 snap-x snap-mandatory gap-3 overflow-x-auto overflow-y-hidden px-4 pb-2 sm:mx-0 sm:snap-none sm:gap-4 sm:px-0"
      >
        <div
          v-for="stage in visibleStages"
          :key="stage.id"
          class="flex min-h-0 w-[85vw] shrink-0 snap-center flex-col border border-t-4 border-default bg-muted sm:w-72 sm:snap-align-none"
          :class="stageAccentBorderClass(stage)"
        >
          <div class="shrink-0 border-b border-default bg-[inherit] p-3">
            <div class="flex items-center justify-between gap-2">
              <span class="truncate font-medium text-highlighted">{{ stage.name }}</span>
              <UBadge :label="String(dealsForStage(stage.id).length)" color="neutral" variant="subtle" class="cds-tag" />
            </div>
            <div v-if="stageTotalValue(stage.id)" class="mt-0.5 text-xs text-muted">
              {{ formatCurrency(stageTotalValue(stage.id)) }}
            </div>
          </div>
          <!-- Only the cards scroll; the stage header above stays put. -->
          <div class="min-h-0 flex-1 space-y-2 overflow-y-auto overscroll-contain p-2">
            <div
              v-for="deal in dealsForStage(stage.id)"
              :key="deal.id"
              class="group relative cursor-pointer overflow-hidden border border-default bg-default p-3 pb-4 text-sm transition-colors hover:border-primary hover:bg-elevated"
              :class="isStageOverdue(deal) && 'border-s-4 border-s-error'"
              @click="openDeal(deal)"
            >
              <div class="flex items-start justify-between gap-2">
                <span class="truncate text-[15px] font-semibold text-highlighted">{{ dealContactName(deal) }}</span>
                <span v-if="deal.value" class="shrink-0 font-semibold text-success">
                  {{ formatCurrency(deal.value) }}
                </span>
              </div>
              <div class="mt-1 flex items-center justify-between gap-2 text-xs">
                <div v-if="dealCategories(deal).length" class="flex min-w-0 items-center gap-1.5 text-muted">
                  <UIcon name="i-lucide-tag" class="size-3 shrink-0" />
                  <span class="truncate">{{ dealCategories(deal).join(" · ") }}</span>
                </div>
                <span
                  class="ms-auto flex shrink-0 items-center gap-1"
                  :class="stageAgeTextClass(deal)"
                  :title="isStageOverdue(deal) ? t('crm.deals.stageOverdue') : undefined"
                >
                  <UIcon :name="isStageOverdue(deal) ? 'i-lucide-triangle-alert' : 'i-lucide-clock'" class="size-3.5" />
                  {{ stageAgeLabel(deal) }}
                </span>
              </div>
              <p v-if="lastNote(deal.id)" class="mt-2 line-clamp-2 border-s-2 border-default ps-2 text-xs text-toned">
                {{ lastNote(deal.id) }}
              </p>
              <div class="mt-3 flex items-center justify-between gap-2 text-xs">
                <div class="flex min-w-0 items-center gap-1.5 text-muted">
                  <UAvatar
                    :text="deal.assigned_to ? assigneeInitial(deal.assigned_to) : undefined"
                    :icon="deal.assigned_to ? undefined : 'i-lucide-user-round'"
                    size="2xs"
                  />
                  <span class="truncate">{{ profileLabel(deal.assigned_to) }}</span>
                </div>
                <div class="flex shrink-0 items-center gap-2">
                  <UBadge
                    v-if="dealReasonName(deal)"
                    :label="dealReasonName(deal)!"
                    size="sm"
                    variant="subtle"
                    :color="stageAccentColor(stage)"
                    class="cds-tag"
                  />
                  <a
                    v-if="toWhatsAppLink(dealContactPhone(deal))"
                    :href="toWhatsAppLink(dealContactPhone(deal))!"
                    target="_blank"
                    rel="noopener noreferrer"
                    :aria-label="t('crm.deals.chatOnWhatsApp')"
                    class="text-[#25D366] transition-opacity hover:opacity-80 md:opacity-0 md:group-hover:opacity-100"
                    @click.stop
                  >
                    <UIcon name="i-simple-icons-whatsapp" class="size-4" />
                  </a>
                </div>
              </div>
              <UProgress
                :model-value="stageAgeDays(deal)"
                :max="STAGE_AGE_CAP_DAYS"
                :color="stageAgeColor(deal)"
                size="xs"
                class="absolute inset-x-0 bottom-0"
              />
            </div>
            <div
              v-if="dealsForStage(stage.id).length === 0"
              class="flex flex-col items-center gap-1 border border-dashed border-default py-6 text-center text-xs text-muted"
            >
              <UIcon name="i-lucide-inbox" class="size-5" />
              {{ t("crm.deals.noDealsInStage") }}
            </div>
          </div>
        </div>
      </div>

      <template v-else>
        <div class="space-y-2 md:hidden">
          <div
            v-for="deal in pagedListDeals"
            :key="deal.id"
            class="relative cursor-pointer overflow-hidden border border-default bg-default p-3 pb-4 text-sm active:bg-elevated"
            :class="isStageOverdue(deal) && 'border-s-4 border-s-error'"
            @click="openDeal(deal)"
          >
            <div class="flex items-start justify-between gap-2">
              <span class="truncate text-[15px] font-semibold text-highlighted">{{ dealContactName(deal) }}</span>
              <span v-if="deal.value" class="shrink-0 font-semibold text-success">{{ formatCurrency(deal.value) }}</span>
            </div>
            <div class="mt-1.5 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs">
              <UBadge
                :label="stageName(deal.stage_id)"
                :color="stageAccentColor(allStages?.find((s) => s.id === deal.stage_id))"
                variant="subtle"
                size="sm"
                class="cds-tag"
              />
              <span class="flex items-center gap-1" :class="stageAgeTextClass(deal)">
                <UIcon :name="isStageOverdue(deal) ? 'i-lucide-triangle-alert' : 'i-lucide-clock'" class="size-3.5" />
                {{ stageAgeLabel(deal) }}
              </span>
              <span v-if="dealReasonName(deal)" class="text-muted">· {{ dealReasonName(deal) }}</span>
            </div>
            <div v-if="dealCategories(deal).length" class="mt-1.5 flex items-center gap-1.5 text-xs text-muted">
              <UIcon name="i-lucide-tag" class="size-3 shrink-0" />
              <span class="truncate">{{ dealCategories(deal).join(" · ") }}</span>
            </div>
            <p v-if="lastNote(deal.id)" class="mt-2 line-clamp-2 border-s-2 border-default ps-2 text-xs text-toned">
              {{ lastNote(deal.id) }}
            </p>
            <div class="mt-3 flex items-center justify-between gap-2 text-xs">
              <div class="flex min-w-0 items-center gap-1.5 text-muted">
                <UAvatar
                  :text="deal.assigned_to ? assigneeInitial(deal.assigned_to) : undefined"
                  :icon="deal.assigned_to ? undefined : 'i-lucide-user-round'"
                  size="2xs"
                />
                <span class="truncate">{{ profileLabel(deal.assigned_to) }}</span>
              </div>
              <a
                v-if="toWhatsAppLink(dealContactPhone(deal))"
                :href="toWhatsAppLink(dealContactPhone(deal))!"
                target="_blank"
                rel="noopener noreferrer"
                :aria-label="t('crm.deals.chatOnWhatsApp')"
                class="flex size-9 shrink-0 items-center justify-center text-[#25D366]"
                @click.stop
              >
                <UIcon name="i-simple-icons-whatsapp" class="size-5" />
              </a>
            </div>
            <UProgress
              :model-value="stageAgeDays(deal)"
              :max="STAGE_AGE_CAP_DAYS"
              :color="stageAgeColor(deal)"
              size="xs"
              class="absolute inset-x-0 bottom-0"
            />
          </div>
          <p v-if="!pagedListDeals.length" class="py-10 text-center text-sm text-muted">
            {{ t("crm.deals.noDealsInStage") }}
          </p>
        </div>

        <div v-if="canAssign && selectedCount > 0" class="mb-3 hidden items-center gap-3 md:flex">
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
          class="hidden md:block"
          v-model:row-selection="rowSelection"
          v-model:sorting="sorting"
          v-model:pagination="pagination"
          :data="listDeals"
          :columns="listColumns"
          :pagination-options="{ getPaginationRowModel: getPaginationRowModel() }"
          :ui="{ root: '[&_tbody_tr]:cursor-pointer' }"
          @select="(_e, row) => openDeal(row.original)"
        >
          <template #stage-cell="{ row }">
            <UBadge
              :label="stageName(row.original.stage_id)"
              :color="stageAccentColor(allStages?.find((s) => s.id === row.original.stage_id))"
              variant="subtle"
              class="cds-tag"
            />
          </template>
          <template #reason-cell="{ row }">
            {{ dealReasonName(row.original) ?? "—" }}
          </template>
          <template #contact-cell="{ row }">
            <div class="flex items-center gap-1.5">
              <span>{{ dealContactName(row.original) }}</span>
              <a
                v-if="toWhatsAppLink(dealContactPhone(row.original))"
                :href="toWhatsAppLink(dealContactPhone(row.original))!"
                target="_blank"
                rel="noopener noreferrer"
                :aria-label="t('crm.deals.chatOnWhatsApp')"
                class="text-[#25D366] hover:opacity-80"
                @click.stop
              >
                <UIcon name="i-simple-icons-whatsapp" class="size-4" />
              </a>
            </div>
          </template>
          <template #value-header="{ column }">
            <UButton
              :label="t('crm.deals.value')"
              color="neutral"
              variant="ghost"
              size="xs"
              :trailing-icon="sortIcon(column)"
              class="-mx-2.5"
              @click="column.toggleSorting(column.getIsSorted() === 'asc')"
            />
          </template>
          <template #value-cell="{ row }">
            <span class="font-medium text-highlighted">{{ formatCurrency(row.original.value) ?? "—" }}</span>
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
              @update:model-value="(value: string | null) => openReassign([row.original.id], value)"
            />
            <div v-else class="flex items-center gap-1.5">
              <UAvatar v-if="row.original.assigned_to" :text="assigneeInitial(row.original.assigned_to)" size="3xs" />
              <span>{{ profileLabel(row.original.assigned_to) }}</span>
            </div>
          </template>
          <template #created-header="{ column }">
            <UButton
              :label="t('crm.deals.createdOn')"
              color="neutral"
              variant="ghost"
              size="xs"
              :trailing-icon="sortIcon(column)"
              class="-mx-2.5"
              @click="column.toggleSorting(column.getIsSorted() === 'asc')"
            />
          </template>
          <template #created-cell="{ row }">
            {{ formatDate(row.original.created_at) }}
          </template>
          <template #stageAge-header="{ column }">
            <UButton
              :label="t('crm.deals.timeInStage')"
              color="neutral"
              variant="ghost"
              size="xs"
              :trailing-icon="sortIcon(column)"
              class="-mx-2.5"
              @click="column.toggleSorting(column.getIsSorted() === 'asc')"
            />
          </template>
          <template #stageAge-cell="{ row }">
            <div class="w-28">
              <UProgress
                :model-value="stageAgeDays(row.original)"
                :max="STAGE_AGE_CAP_DAYS"
                :color="stageAgeColor(row.original)"
                size="xs"
              />
              <span class="mt-0.5 flex items-center gap-1 text-xs text-muted">
                {{ stageAgeLabel(row.original) }}
                <UIcon
                  v-if="isStageOverdue(row.original)"
                  name="i-lucide-triangle-alert"
                  :title="t('crm.deals.stageOverdue')"
                  class="size-3.5 text-error"
                />
              </span>
            </div>
          </template>
          <template #lastNote-cell="{ row }">
            <span class="line-clamp-2 max-w-64 text-muted">{{ lastNote(row.original.id) ?? "—" }}</span>
          </template>
        </UTable>
        <div class="flex flex-wrap items-center justify-between gap-2 border-t border-default pt-3">
          <span class="text-sm text-muted">
            {{ t("crm.deals.totalRows", { count: listDeals.length }) }}
          </span>
          <UPagination
            :page="pagination.pageIndex + 1"
            :items-per-page="pagination.pageSize"
            :total="listDeals.length"
            :sibling-count="1"
            @update:page="(p: number) => (pagination.pageIndex = p - 1)"
          />
        </div>
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
            <div class="flex items-center gap-1">
              <PhoneInput v-model="state.lead_phone" class="flex-1" />
              <UButton
                v-if="!showPhone2"
                icon="i-lucide-plus"
                size="xs"
                color="neutral"
                variant="ghost"
                :aria-label="t('crm.leads.phone2')"
                @click="showPhone2 = true"
              />
            </div>
          </UFormField>
          <UFormField v-if="showPhone2" name="lead_phone2" :label="t('crm.leads.phone2')">
            <PhoneInput v-model="state.lead_phone2" class="w-full" />
          </UFormField>
          <UAlert
            v-if="duplicateNewLead"
            color="warning"
            variant="subtle"
            icon="i-lucide-triangle-alert"
            :title="t('crm.leads.duplicatePhone')"
          >
            <template #description>
              <ULink
                :to="`/crm/leads/${duplicateNewLead.id}`"
                class="inline-flex items-center gap-1 font-medium text-primary"
              >
                {{ duplicateNewLead.name }}
                <UIcon name="i-lucide-arrow-left" class="size-3" />
              </ULink>
            </template>
          </UAlert>
          <UFormField name="lead_email" :label="t('common.email')">
            <UInput v-model="state.lead_email" type="email" class="w-full" />
          </UFormField>
          <UFormField name="lead_source" :label="t('crm.leads.source')">
            <USelect v-model="state.lead_source" :items="sourceOptions" value-key="value" class="w-full" />
          </UFormField>
        </template>

        <USeparator />

        <UFormField name="category_ids" :label="t('crm.deals.dealTitle')">
          <USelectMenu
            v-model="state.category_ids"
            :items="categoryItems"
            value-key="value"
            multiple
            :placeholder="t('crm.deals.selectCategories')"
            class="w-full"
          >
            <template #default>
              <div v-if="state.category_ids?.length" class="flex flex-wrap gap-1 py-0.5">
                <UBadge v-for="id in state.category_ids" :key="id" color="neutral" variant="subtle" class="gap-1">
                  {{ categoryItems.find((c) => c.value === id)?.label }}
                  <UIcon
                    name="i-lucide-x"
                    class="size-3 cursor-pointer"
                    @click.stop="state.category_ids = state.category_ids?.filter((v) => v !== id)"
                  />
                </UBadge>
              </div>
              <span v-else class="text-muted">{{ t("crm.deals.selectCategories") }}</span>
            </template>
          </USelectMenu>
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
        <UButton
          type="submit"
          :label="t('crm.deals.createDeal')"
          :loading="creating"
          :disabled="!!duplicateNewLead"
          block
        />
      </UForm>
    </template>
  </UModal>

  <UModal v-model:open="reassignOpen" :title="t('crm.deals.bulkReassignTitle', { count: reassignDealIds.length })">
    <template #body>
      <div class="space-y-4">
        <UFormField :label="t('crm.deals.assignedTo')">
          <USelect v-model="reassignTarget" :items="assigneeOptions" value-key="value" class="w-full" />
        </UFormField>
        <UFormField :label="t('crm.deals.stage')" required>
          <USelect
            v-model="reassignStageId"
            :items="activeStages.map((s) => ({ label: s.name, value: s.id }))"
            value-key="value"
            class="w-full"
          />
        </UFormField>
        <UFormField v-if="reassignStage?.reason_category" :label="t('crm.deals.reason')" required>
          <USelect v-model="reassignReasonId" :items="reassignReasonOptions" value-key="value" class="w-full" />
        </UFormField>
        <UFormField :label="t('crm.deals.historyVisibility')">
          <URadioGroup
            v-model="reassignHideHistory"
            :items="[
              { label: t('crm.deals.keepHistoryVisible'), value: false },
              { label: t('crm.deals.hideHistory'), value: true },
            ]"
            value-key="value"
          />
          <p class="mt-1 text-xs text-muted">{{ t("crm.deals.historyVisibilityHint") }}</p>
        </UFormField>
        <UButton
          :label="t('crm.deals.bulkReassign')"
          :loading="reassigning"
          :disabled="!reassignValid"
          block
          @click="confirmReassign"
        />
      </div>
    </template>
  </UModal>

  <USlideover v-model:open="filtersOpen" side="bottom" :title="t('crm.deals.filters')">
    <template #body>
      <div class="space-y-4 pb-[env(safe-area-inset-bottom)]">
        <UFormField :label="t('crm.deals.assignedTo')">
          <USelectMenu
            v-model="assigneeFilter"
            :items="assigneeFilterOptions"
            value-key="value"
            icon="i-lucide-user"
            searchable
            class="w-full"
          />
        </UFormField>
        <UFormField :label="t('crm.deals.stage')">
          <USelectMenu
            v-model="stageFilter"
            :items="stageFilterOptions"
            value-key="value"
            icon="i-lucide-git-branch"
            class="w-full"
          />
        </UFormField>
        <div class="grid grid-cols-2 gap-3">
          <UFormField :label="t('crm.deals.createdFrom')">
            <UInput v-model="dateFrom" type="date" class="w-full" />
          </UFormField>
          <UFormField :label="t('crm.deals.createdTo')">
            <UInput v-model="dateTo" type="date" class="w-full" />
          </UFormField>
        </div>
        <div class="flex gap-2">
          <UButton
            color="neutral"
            variant="outline"
            :label="t('crm.deals.clearFilters')"
            class="flex-1 justify-center"
            @click="clearFilters"
          />
          <UButton :label="t('common.done')" class="flex-1 justify-center" @click="filtersOpen = false" />
        </div>
      </div>
    </template>
  </USlideover>
</template>
