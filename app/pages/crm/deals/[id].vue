<script setup lang="ts">
import type { TimelineItem } from "@nuxt/ui";
import { CalendarDate, Time, getLocalTimeZone, today } from "@internationalized/date";

definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "crm_deals" },
});

const route = useRoute();
const dealId = route.params.id as string;
// The Kords design system look (app/assets/css/kords.css).
useHead({ htmlAttrs: { class: "kords" } });

const supabase = useSupabaseClient();
const toast = useToast();
const { hasPermission, hasAnyModulePermission } = usePermissions();
// A user who sees only their own leads doesn't see where a lead came from, so
// every lead is worked the same way. Seeing all leads is what unlocks the source.
const canSeeSource = computed(() => hasPermission("crm_leads", "view_all"));
const { t, te, locale } = useI18n();
const { areaName, loadAreas } = useCs();
useAsyncData("crm-deal-areas", async () => {
  await loadAreas();
  return true;
});

interface Deal {
  id: string;
  title: string;
  pipeline_id: string;
  stage_id: string;
  stage_reason_id: string | null;
  value: number | null;
  expected_close_date: string | null;
  customer_id: string | null;
  lead_id: string | null;
  assigned_to: string | null;
  created_at: string;
}

interface Customer {
  id: string;
  name: string;
  company: string | null;
  phone: string | null;
  email: string | null;
}

interface LeadContact {
  id: string;
  name: string;
  company_name: string | null;
  lead_type: "individual" | "company";
  phone: string | null;
  phone2: string | null;
  email: string | null;
  source: string | null;
  notes: string | null;
  created_at: string;
  area_id: string | null;
}

interface Quote {
  id: string;
  quote_number: string;
  status: string;
  total: number;
}

interface DealAttachment {
  id: string;
  file_name: string;
  storage_path: string;
  uploaded_by: string | null;
  created_at: string;
  kind: string | null;
}

interface Pipeline {
  id: string;
  name: string;
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
  sub_pipeline_id: string | null;
}

interface Reason {
  id: string;
  pipeline_id: string;
  category: "archive" | "competitor";
  name: string;
}

interface Profile {
  id: string;
  full_name: string | null;
  email: string;
}

interface Activity {
  id: string;
  deal_id: string;
  type: "note" | "call" | "meeting" | "site_visit" | "stage_changed" | "assigned" | "created";
  content: string | null;
  scheduled_at: string | null;
  completed_at: string | null;
  metadata: Record<string, unknown>;
  created_by: string | null;
  created_at: string;
}

const deal = ref<Deal | null>(null);
const saving = ref(false);
const deleting = ref(false);
const canEdit = computed(() => hasPermission("crm_deals", "edit"));
const canDelete = computed(() => hasPermission("crm_deals", "delete"));
const canAssign = computed(() => hasPermission("crm_deals", "assign"));

// --- Field trips (مأمورية) and inspections (معاينة) on this deal ---
const canSeeVisits = computed(() => hasAnyModulePermission("crm_visits"));
const canRequestVisit = computed(() => hasPermission("crm_visits", "create"));
const visitModalOpen = ref(false);
function openVisitModal() {
  visitModalOpen.value = true;
}
const { statusColors: visitStatusColors, statusLabel: visitStatusLabel, kindLabel: visitKindLabel, kindIcon: visitKindIcon, formatDate: visitFormatDate, timeRange: visitTimeRange, loadTypes: loadVisitTypes } = useVisits();
const { data: dealVisits, refresh: refreshVisits } = await useAsyncData<Visit[]>(`crm-deal-${dealId}-visits`, async () => {
  if (!canSeeVisits.value) return [];
  await loadVisitTypes();
  const { data, error } = await supabase
    .from("field_visits")
    .select("*")
    .eq("deal_id", dealId)
    .order("visit_date", { ascending: false });
  if (error) throw error;
  return (data ?? []) as Visit[];
});
// Notes written along the way on those visits (the reason it was rejected, what was found when done...).
const { data: visitEventNotes } = await useAsyncData<{ visit_id: string; action: string; note: string }[]>(
  `crm-deal-${dealId}-visit-notes`,
  async () => {
    const ids = (dealVisits.value ?? []).map((v) => v.id);
    if (!ids.length) return [];
    const { data, error } = await supabase.from("field_visit_events").select("visit_id, action, note, created_at").in("visit_id", ids).order("created_at");
    if (error) return [];
    return (data ?? []).filter((e) => e.note?.trim()) as { visit_id: string; action: string; note: string }[];
  },
);
const visitNotesOf = (visitId: string) => (visitEventNotes.value ?? []).filter((e) => e.visit_id === visitId);
const canCreateQuote = computed(() => hasPermission("crm_quotes", "create"));
const canEditLead = computed(() => hasPermission("crm_leads", "edit"));

const { data: pipelines } = await useAsyncData<Pipeline[]>("crm-deal-pipelines", async () => {
  const { data, error } = await supabase.from("pipelines").select("id, name").order("sort_order");
  if (error) throw error;
  return data ?? [];
});
const { data: allStages } = await useAsyncData<Stage[]>("crm-deal-stages", async () => {
  const { data, error } = await supabase
    .from("pipeline_stages")
    .select("id, pipeline_id, name, sort_order, is_closed, reason_category, system_key, max_stay_days, max_stay_hours, sub_pipeline_id")
    .order("sort_order");
  if (error) throw error;
  return data ?? [];
});
const { data: allReasons } = await useAsyncData<Reason[]>("crm-deal-reasons", async () => {
  const { data, error } = await supabase
    .from("pipeline_stage_reasons")
    .select("id, pipeline_id, category, name")
    .order("sort_order");
  if (error) throw error;
  return data ?? [];
});
const { data: profiles } = await useAsyncData<Profile[]>("crm-deal-profiles", async () => {
  const { data, error } = await supabase.from("profiles").select("id, full_name, email").eq("is_active", true);
  if (error) throw error;
  return data ?? [];
});

function profileLabel(id: string | null | undefined) {
  if (!id) return t("common.unassigned");
  const p = profiles.value?.find((p) => p.id === id);
  return p?.full_name || p?.email || "?";
}
const assigneeOptions = computed(() => [
  { label: t("common.unassigned"), value: null },
  ...(profiles.value ?? []).map((p) => ({ label: p.full_name || p.email, value: p.id })),
]);

const pipelineOptions = computed(() => (pipelines.value ?? []).map((p) => ({ label: p.name, value: p.id })));
const pipelineStages = computed(() =>
  (allStages.value ?? [])
    .filter((s) => s.pipeline_id === deal.value?.pipeline_id)
    .sort((a, b) => a.sort_order - b.sort_order),
);
const currentStage = computed(() => allStages.value?.find((s) => s.id === deal.value?.stage_id));

// ---- Hand the deal to a sub-workflow (e.g. the technical office): when the deal's
// stage is set up to, a button sends it to that workflow's board.
interface WorkItemInfo {
  id: string;
  work_pipeline_id: string;
  stage_id: string;
  created_by: string | null;
}
const { data: workInfo, refresh: refreshWorkInfo } = await useAsyncData(`crm-deal-${dealId}-work`, async () => {
  const [pipelines, stages, items] = await Promise.all([
    supabase.from("work_pipelines").select("id, name").order("sort_order"),
    supabase.from("work_pipeline_stages").select("id, work_pipeline_id, name, sort_order").order("sort_order"),
    supabase.from("work_items").select("id, work_pipeline_id, stage_id, created_by").eq("deal_id", dealId),
  ]);
  return {
    pipelines: (pipelines.data ?? []) as { id: string; name: string }[],
    stages: (stages.data ?? []) as { id: string; work_pipeline_id: string; name: string; sort_order: number }[],
    items: (items.data ?? []) as WorkItemInfo[],
  };
});
// The sub-workflow of the deal's stage — or, once the deal has moved on, the one it was already sent to.
const stageSubPipeline = computed(() => workInfo.value?.pipelines.find((p) => p.id === currentStage.value?.sub_pipeline_id) ?? null);
const subPipeline = computed(() => stageSubPipeline.value ?? workInfo.value?.pipelines.find((p) => workInfo.value?.items.some((i) => i.work_pipeline_id === p.id)) ?? null);
const subItem = computed(() => (subPipeline.value ? workInfo.value?.items.find((i) => i.work_pipeline_id === subPipeline.value!.id) ?? null : null));
// every stage of the workflow, in order, to show where the deal is now
const subStages = computed(() => (subPipeline.value ? (workInfo.value?.stages.filter((s) => s.work_pipeline_id === subPipeline.value!.id) ?? []) : []));
const subStageIndex = computed(() => subStages.value.findIndex((s) => s.id === subItem.value?.stage_id));
// the stage can change on the board: look again when this tab is shown again
onMounted(() => {
  const refresh = () => document.visibilityState === "visible" && refreshWorkInfo();
  document.addEventListener("visibilitychange", refresh);
  window.addEventListener("focus", refresh);
  onBeforeUnmount(() => {
    document.removeEventListener("visibilitychange", refresh);
    window.removeEventListener("focus", refresh);
  });
});
const subItemStage = computed(() => workInfo.value?.stages.find((s) => s.id === subItem.value?.stage_id)?.name ?? "");
const canSendToWork = computed(() => canEdit.value);
// withdrawing: who works the boards, or whoever sent the request
const me = useSupabaseUser();
const canWithdraw = computed(() => hasPermission("crm_work", "edit") || (canEdit.value && !!subItem.value?.created_by && subItem.value.created_by === me.value?.sub));
// a new request can only be sent from the stage that leads to the workflow
const canSendNew = computed(() => canEdit.value && !!stageSubPipeline.value);
// the board is opened with its own permission, or "see every board"
// Pushing the customer to Customer Service is offered once the deal is won.
const canPushToCs = computed(() => currentStage.value?.system_key === "won" && !!deal.value?.customer_id && hasPermission("crm_customers", "push_to_cs"));
const pushOpen = ref(false);
const canOpenBoard = computed(() => !!subPipeline.value && (hasPermission("crm_work", "view") || hasPermission("crm_work", subPipeline.value.id)));
const sendingToWork = ref(false);
// sending asks what is wanted and by when; both are required
const sendOpen = ref(false);
const sendNote = ref("");
// the deadline is picked from a few choices, counted from now
const DEADLINES = [
  { value: "24h", label: "crm.work.deadlineOptions.h24", hours: 24 },
  { value: "2d", label: "crm.work.deadlineOptions.d2", hours: 48 },
  { value: "3d", label: "crm.work.deadlineOptions.d3", hours: 72 },
  { value: "1w", label: "crm.work.deadlineOptions.w1", hours: 168 },
];
const deadlineItems = computed(() => DEADLINES.map((d) => ({ value: d.value, label: t(d.label) })));
const sendDeadline = ref<string | null>(null);
const sendFiles = ref<File[]>([]);
// what the request is about: the product category
const sendCategory = ref<string | null>(null);
const { data: sendCategories } = await useAsyncData<{ id: string; name: string }[]>("crm-deal-send-categories", async () => {
  const { data } = await supabase.from("product_categories").select("id, name").order("sort_order");
  return data ?? [];
});
const sendCategoryItems = computed(() => (sendCategories.value ?? []).map((c) => ({ label: c.name, value: c.id })));
function setDeadline(v: unknown) {
  sendDeadline.value = typeof v === "string" && v ? v : null;
}
const sendValid = computed(() => !!sendNote.value.trim() && !!sendDeadline.value && !!sendCategory.value);
function openSend() {
  sendNote.value = "";
  sendDeadline.value = null;
  sendCategory.value = null;
  sendFiles.value = [];
  sendOpen.value = true;
}
function closeSend() {
  sendOpen.value = false;
}
// Take the deal back from the board: its item is removed from that workflow.
const withdrawOpen = ref(false);
const withdrawing = ref(false);
function askWithdraw() {
  withdrawOpen.value = true;
}
async function withdrawFromWork() {
  const item = subItem.value;
  if (!item) return;
  withdrawing.value = true;
  // a delete that the database refuses silently removes nothing: ask for the removed row back
  const { data: removed, error } = await supabase.from("work_items").delete().eq("id", item.id).select("id");
  withdrawing.value = false;
  if (error || !removed?.length) {
    toast.add({ title: t("crm.work.withdrawFailed"), description: error?.message ?? t("crm.work.withdrawNotAllowed"), color: "error" });
    await refreshWorkInfo();
    return;
  }
  withdrawOpen.value = false;
  toast.add({ title: t("crm.work.withdrawn"), color: "success" });
  await refreshWorkInfo();
}
async function sendToWork() {
  if (!sendValid.value) return;
  const target = subPipeline.value;
  if (!target || !deal.value) return;
  const first = workInfo.value?.stages.find((s) => s.work_pipeline_id === target.id);
  if (!first) return;
  sendingToWork.value = true;
  const hours = DEADLINES.find((d) => d.value === sendDeadline.value)?.hours ?? 24;
  const row = {
    work_pipeline_id: target.id,
    stage_id: first.id,
    deal_id: dealId,
    title: contactName.value || deal.value.title,
    request_note: sendNote.value.trim(),
    deadline: new Date(Date.now() + hours * 3_600_000).toISOString(),
  };
  let { data: created, error } = await supabase.from("work_items").insert({ ...row, product_category_id: sendCategory.value }).select("id").single();
  // the category column arrives with a migration: until then send without it
  if (error?.code === "42703") ({ data: created, error } = await supabase.from("work_items").insert(row).select("id").single());
  if (error || !created) {
    sendingToWork.value = false;
    toast.add({ title: t("crm.work.sendFailed"), description: error?.message, color: "error" });
    return;
  }
  // the files belong to the deal too (its Files tab), and point at this request
  for (const file of sendFiles.value) {
    const path = `${dealId}/${Date.now()}-${file.name}`;
    const { error: uploadError } = await supabase.storage.from("deal-attachments").upload(path, file);
    if (uploadError) {
      toast.add({ title: t("files.uploadFailed"), description: `${file.name}: ${uploadError.message}`, color: "error" });
      continue;
    }
    const { error: rowError } = await supabase.from("deal_attachments").insert({ deal_id: dealId, file_name: file.name, storage_path: path, work_item_id: created.id });
    if (rowError) toast.add({ title: t("files.uploadFailed"), description: `${file.name}: ${rowError.message}`, color: "error" });
  }
  sendingToWork.value = false;
  refreshAttachments();
  toast.add({ title: t("crm.work.sent", { name: target.name }), color: "success" });
  sendOpen.value = false;
  await refreshWorkInfo();
}
const currentReasonName = computed(() => {
  if (!currentStage.value?.reason_category || !deal.value?.stage_reason_id) return null;
  return allReasons.value?.find((r) => r.id === deal.value?.stage_reason_id)?.name ?? null;
});

// See leads/[id].vue for why this syncs via watchEffect from useAsyncData's
// own `data` rather than only mutating `deal` inside the handler.
const { data: dealPayload, status } = await useAsyncData(`crm-deal-${dealId}`, async () => {
  const { data, error } = await supabase.from("deals").select("*").eq("id", dealId).single();
  if (error) throw error;
  return data;
});
watchEffect(() => {
  if (dealPayload.value) deal.value = dealPayload.value;
});

const { data: customer, refresh: refreshCustomer } = await useAsyncData<Customer | null>(`crm-deal-${dealId}-customer`, async () => {
  if (!deal.value?.customer_id) return null;
  const { data, error } = await supabase
    .from("customers")
    .select("id, name, company, phone, email")
    .eq("id", deal.value.customer_id)
    .single();
  if (error) throw error;
  return data;
});

// Pre-Won, the deal has no customer yet — the sidebar contact card falls
// back to the originating lead's info instead.
const { data: leadContact, refresh: refreshLeadContact } = await useAsyncData<LeadContact | null>(
  `crm-deal-${dealId}-lead-contact`,
  async () => {
    if (!deal.value?.lead_id) return null;
    const { data, error } = await supabase
      .from("leads")
      .select("id, name, company_name, lead_type, phone, phone2, email, source, notes, created_at, area_id")
      .eq("id", deal.value.lead_id)
      .single();
    if (error) throw error;
    return data;
  },
);

const { data: quotes } = await useAsyncData<Quote[]>(`crm-deal-${dealId}-quotes`, async () => {
  const { data, error } = await supabase
    .from("quotes")
    .select("id, quote_number, status, total")
    .eq("deal_id", dealId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data ?? [];
});

const { data: attachments, refresh: refreshAttachments } = await useAsyncData<DealAttachment[]>(
  `crm-deal-${dealId}-attachments`,
  async () => {
    const { data, error } = await supabase
      .from("deal_attachments")
      .select("id, file_name, storage_path, uploaded_by, created_at, kind")
      .eq("deal_id", dealId)
      .order("created_at", { ascending: false });
    if (error) throw error;
    return data ?? [];
  },
);

// Uploads to the private deal-attachments bucket, then records the row
// that tracks it — the offer_sent DB trigger checks this table, so the
// row must exist before the stage update that follows.
// The quote section: Offer sent asks for a file only while it is empty.
const hasQuote = computed(() => (attachments.value ?? []).some((a) => a.kind === "quote"));
async function uploadDealAttachment(file: File): Promise<{ error: string | null }> {
  const path = `${dealId}/${Date.now()}-${file.name}`;
  const { error: uploadError } = await supabase.storage.from("deal-attachments").upload(path, file);
  if (uploadError) return { error: uploadError.message };

  const { error: insertError } = await supabase
    .from("deal_attachments")
    .insert({ deal_id: dealId, file_name: file.name, storage_path: path, kind: "quote" });
  if (insertError) return { error: insertError.message };

  return { error: null };
}

// --- Edit the deal's originating lead right from this page, without
// navigating away — the lead record is the source of the contact info
// shown in the sidebar card whether the deal has converted to a customer
// yet or not.
const editLeadTypeOptions = computed(() => [
  { label: t("crm.leads.type.individual"), value: "individual" },
  { label: t("crm.leads.type.company"), value: "company" },
]);
const editSourceKeys = ["external_client", "facebook", "instagram", "meta", "google", "website", "event", "referral", "whatsapp", "api", "odoo"] as const;
const editSourceOptions = computed(() =>
  editSourceKeys.map((s) => ({ label: t(`crm.leads.sourceValues.${s}`), value: s })),
);

const editLeadModalOpen = ref(false);
const editLeadType = ref<"individual" | "company">("individual");
const editCompanyName = ref("");
const editName = ref("");
const editPhone = ref("");
const editPhone2 = ref("");
const editEmail = ref("");
const editArea = ref<string | null>(null);
const editSource = ref<(typeof editSourceKeys)[number] | undefined>(undefined);
const editLeadSaving = ref(false);

const editLeadSubmitDisabled = computed(() => !editName.value.trim() || !editPhone.value.trim());

function openEditLead() {
  if (!leadContact.value) return;
  editLeadType.value = leadContact.value.lead_type;
  editCompanyName.value = leadContact.value.company_name ?? "";
  editName.value = leadContact.value.name;
  editPhone.value = leadContact.value.phone ?? "";
  editPhone2.value = leadContact.value.phone2 ?? "";
  editEmail.value = leadContact.value.email ?? "";
  editArea.value = leadContact.value.area_id ?? null;
  editSource.value = leadContact.value.source ?? undefined;
  editLeadModalOpen.value = true;
}

async function saveEditLead() {
  if (editLeadSubmitDisabled.value || !deal.value?.lead_id) return;
  editLeadSaving.value = true;
  const payload: Record<string, unknown> = {
    lead_type: editLeadType.value,
    company_name: editLeadType.value === "company" ? editCompanyName.value.trim() || null : null,
    name: editName.value.trim(),
    phone: editPhone.value.trim(),
    phone2: trimOrNull(editPhone2.value),
    email: editEmail.value.trim() || null,
    source: editSource.value ?? null,
    area_id: editArea.value,
  };
  const { error } = await supabase.from("leads").update(payload).eq("id", deal.value.lead_id);
  editLeadSaving.value = false;

  if (error) {
    toast.add({ title: t("crm.leads.saveFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("crm.leads.leadSaved"), color: "success" });
  editLeadModalOpen.value = false;
  refreshLeadContact();
}

const { data: activities, refresh: refreshActivities } = await useAsyncData<Activity[]>(
  `crm-deal-${dealId}-activities`,
  async () => {
    const { data, error } = await supabase
      .from("deal_activities")
      .select("*")
      .eq("deal_id", dealId)
      .order("created_at", { ascending: false });
    if (error) throw error;
    return data ?? [];
  },
);

// --- Details form (title/value/date/pipeline/assignee) ---
async function onPipelineChange() {
  if (!deal.value) return;
  const firstStage = allStages.value?.find((s) => s.pipeline_id === deal.value!.pipeline_id);
  deal.value.stage_id = firstStage?.id ?? "";
  deal.value.stage_reason_id = null;
}

async function save() {
  if (!deal.value) return;
  saving.value = true;
  const payload: Record<string, unknown> = {
    title: deal.value.title,
    pipeline_id: deal.value.pipeline_id,
    stage_id: deal.value.stage_id,
    stage_reason_id: deal.value.stage_reason_id,
    value: deal.value.value,
    expected_close_date: deal.value.expected_close_date,
  };
  // The assignee is changed only through the reassign modal below, which
  // also asks for the stage and history visibility.

  const { error } = await supabase.from("deals").update(payload).eq("id", dealId);
  saving.value = false;

  if (error) {
    toast.add({ title: t("crm.deals.saveFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("crm.deals.dealSaved"), color: "success" });
  refreshActivities();
}

async function remove() {
  deleting.value = true;
  const { error } = await supabase.from("deals").delete().eq("id", dealId);
  deleting.value = false;

  if (error) {
    toast.add({ title: t("crm.deals.deleteFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("crm.deals.dealDeleted"), color: "success" });
  navigateTo("/crm/deals");
}

const creatingQuote = ref(false);
async function createQuote() {
  if (!deal.value) return;
  creatingQuote.value = true;
  const { data, error } = await supabase
    .from("quotes")
    .insert({ deal_id: dealId, customer_id: deal.value.customer_id })
    .select()
    .single();
  creatingQuote.value = false;

  if (error) {
    toast.add({ title: t("crm.deals.createQuoteFailed"), description: error.message, color: "error" });
    return;
  }
  navigateTo(`/crm/quotes/${data.id}`);
}

// --- Stage stepper: every change is confirmed in a modal that requires a
// note (why the stage is moving) — except Won, Bought from competitor, and
// Archive, which already require enough context of their own (value+date,
// or a reason) — plus a reason select when the target stage demands one.
// --- Reassign ---
// Picking a different assignee opens this modal instead of saving straight
// away (same flow as reassigning from the deals table): it also asks for the
// deal's stage — the current one or a new one — and whether the past history
// stays visible. "Hide" stamps history_hidden_before so everything up to now
// drops out of the timeline for anyone without crm_deals view_all (enforced
// by RLS); view_all always sees the full history and nothing is deleted.
const reassignOpen = ref(false);
const reassigning = ref(false);
const reassignTarget = ref<string | null>(null);
const reassignStageId = ref<string | null>(null);
const reassignReasonId = ref<string | null>(null);
const reassignHideHistory = ref(false);

const reassignStage = computed(() => allStages.value?.find((s) => s.id === reassignStageId.value));
const reassignReasonOptions = computed(() =>
  (allReasons.value ?? [])
    .filter((r) => r.pipeline_id === deal.value?.pipeline_id && r.category === reassignStage.value?.reason_category)
    .map((r) => ({ label: r.name, value: r.id })),
);
const reassignIsWon = computed(() => reassignStage.value?.system_key === "won" && reassignStageId.value !== deal.value?.stage_id);
const reassignValid = computed(
  () =>
    !!reassignStageId.value &&
    (!reassignStage.value?.reason_category || !!reassignReasonId.value) &&
    (!reassignIsWon.value || wonProductsOk.value),
);

// Moving to another stage invalidates the reason picked for the old one;
// going back to the current stage restores the deal's own reason.
watch(reassignStageId, (stageId) => {
  if (!reassignOpen.value) return;
  if (allStages.value?.find((s) => s.id === stageId)?.system_key === "won" && stageId !== deal.value?.stage_id) {
    prepareWonProducts(today(getLocalTimeZone()).toString());
  }
  reassignReasonId.value = stageId === deal.value?.stage_id ? (deal.value?.stage_reason_id ?? null) : null;
});

function openReassign(assigneeId: string | null) {
  if (!deal.value || !canAssign.value || assigneeId === deal.value.assigned_to) return;
  reassignTarget.value = assigneeId;
  reassignStageId.value = deal.value.stage_id;
  reassignReasonId.value = deal.value.stage_reason_id;
  reassignHideHistory.value = false;
  reassignOpen.value = true;
}

async function confirmReassign() {
  if (!deal.value || !reassignValid.value) return;
  reassigning.value = true;

  const reasonId = reassignStage.value?.reason_category ? reassignReasonId.value : null;
  const updates: Record<string, unknown> = {
    assigned_to: reassignTarget.value,
    stage_id: reassignStageId.value,
    stage_reason_id: reasonId,
  };
  if (reassignHideHistory.value) updates.history_hidden_before = new Date().toISOString();

  if (reassignStage.value?.system_key === "won" && !deal.value.customer_id) {
    const { customerId, error: conversionError } = await resolveWonCustomerId(supabase, deal.value.lead_id);
    if (conversionError || !customerId) {
      reassigning.value = false;
      const description = conversionError === "no_lead" ? t("crm.deals.noLeadForConversion") : conversionError;
      toast.add({ title: t("crm.deals.reassignFailed"), description: description ?? undefined, color: "error" });
      return;
    }
    updates.customer_id = customerId;
  }
  if (reassignIsWon.value) {
    const productsError = await saveWonProducts((updates.customer_id as string | undefined) ?? deal.value.customer_id);
    if (productsError) {
      reassigning.value = false;
      toast.add({ title: t("crm.deals.reassignFailed"), description: productsError, color: "error" });
      return;
    }
  }

  const { error } = await supabase.from("deals").update(updates).eq("id", dealId);
  reassigning.value = false;

  if (error) {
    toast.add({ title: t("crm.deals.reassignFailed"), description: error.message, color: "error" });
    return;
  }

  deal.value.assigned_to = reassignTarget.value;
  deal.value.stage_id = reassignStageId.value!;
  deal.value.stage_reason_id = reasonId;
  if (updates.customer_id) {
    deal.value.customer_id = updates.customer_id as string;
    refreshCustomer();
  }
  toast.add({ title: t("crm.deals.reassigned"), color: "success" });
  reassignOpen.value = false;
  refreshActivities();
}

// Winning a deal asks what was bought (Customer Service products). A deal that
// already has its products recorded is not asked again.
const wonProducts = ref<WonProductDraft[]>([]);
const wonHasProducts = ref(false);
// ...and its contract file (an upload, unless the deal already has one).
const contractFile = ref<File | null>(null);
const hasContract = ref(false);
async function prepareWonProducts(closeDate: string) {
  wonProducts.value = [
    newWonProduct({ name: deal.value?.title ?? "", contract_date: closeDate, sales_person_id: deal.value?.assigned_to ?? null }),
  ];
  contractFile.value = null;
  const [products, contract] = await Promise.all([dealHasProducts(supabase, dealId), dealHasContract(supabase, dealId)]);
  wonHasProducts.value = products;
  hasContract.value = contract;
}
const wonProductsOk = computed(
  () => (wonHasProducts.value || wonProductsValid(wonProducts.value)) && (hasContract.value || !!contractFile.value),
);
// Stores the contract file, then the products, before the deal moves to Won.
async function saveWonProducts(customerId: string | null) {
  if (!hasContract.value && contractFile.value) {
    const contractError = await uploadDealContract(supabase, dealId, contractFile.value);
    if (contractError) return contractError;
    hasContract.value = true;
    refreshAttachments();
  }
  if (wonHasProducts.value) return null;
  if (!customerId) return t("crm.deals.noLeadForConversion");
  return await recordDealProducts(supabase, dealId, customerId, wonProducts.value);
}

const stageChangeModalOpen = ref(false);
const pendingStageId = ref<string | null>(null);
const pendingReasonId = ref<string | null>(null);
const pendingNote = ref("");
const pendingValue = ref<number | null>(null);
const pendingCloseDate = ref("");
const pendingFile = ref<File | null>(null);
const changingStage = ref(false);

const pendingStage = computed(() => allStages.value?.find((s) => s.id === pendingStageId.value));
const pendingReasonOptions = computed(() =>
  (allReasons.value ?? [])
    .filter((r) => r.pipeline_id === deal.value?.pipeline_id && r.category === pendingStage.value?.reason_category)
    .map((r) => ({ label: r.name, value: r.id })),
);
// The "Won" and "Offer sent" stages are the pipeline's fixed system_key
// stages — never a heuristic, since is_closed/reason_category alone could
// match more than one stage.
const isWonStage = computed(() => pendingStage.value?.system_key === "won");
const isOfferSentStage = computed(() => pendingStage.value?.system_key === "offer_sent");
// A note is required on every stage change except Won (which already
// requires value + close date), Bought from competitor, and Archive
// (which already require picking a reason) — those already capture "why"
// well enough on their own.
const noteRequired = computed(() => !isWonStage.value && !pendingStage.value?.reason_category);

// Arriving from a drag-and-drop on the board (?changeStage=<stage id>): open the
// stage dialog for that stage straight away.
onMounted(() => {
  const target = route.query.changeStage;
  if (typeof target === "string") {
    selectStage(target);
    navigateTo({ path: route.path, query: {} }, { replace: true });
  }
});

function selectStage(stageId: string) {
  if (!canEdit.value || !deal.value || stageId === deal.value.stage_id) return;
  pendingStageId.value = stageId;
  pendingReasonId.value = null;
  pendingNote.value = "";
  pendingFile.value = null;
  const stage = allStages.value?.find((s) => s.id === stageId);
  const won = stage?.system_key === "won";
  pendingValue.value = won ? deal.value.value : null;
  pendingCloseDate.value = won ? deal.value.expected_close_date || today(getLocalTimeZone()).toString() : "";
  if (won) prepareWonProducts(pendingCloseDate.value);
  stageChangeModalOpen.value = true;
}

async function confirmStageChange() {
  if (!deal.value || !pendingStageId.value) return;
  if (noteRequired.value && !pendingNote.value.trim()) return;
  if (pendingStage.value?.reason_category && !pendingReasonId.value) return;
  if (isWonStage.value && (pendingValue.value == null || !pendingCloseDate.value)) return;
  if (isWonStage.value && !wonProductsOk.value) return;
  if (isOfferSentStage.value && !hasQuote.value && !pendingFile.value) return;

  changingStage.value = true;

  // A deal can't reach "Offer sent" without an attached file (DB-enforced
  // too) — upload and record it before the stage update, since the
  // attachment must already exist by the time the trigger checks it.
  if (isOfferSentStage.value && pendingFile.value) {
    const { error: uploadError } = await uploadDealAttachment(pendingFile.value);
    if (uploadError) {
      changingStage.value = false;
      toast.add({ title: t("crm.deals.attachmentUploadFailed"), description: uploadError, color: "error" });
      return;
    }
    refreshAttachments();
  }

  const updates: Record<string, unknown> = { stage_id: pendingStageId.value, stage_reason_id: pendingReasonId.value };
  let resolvedCustomerId: string | null = deal.value.customer_id;
  if (isWonStage.value) {
    updates.value = pendingValue.value;
    updates.expected_close_date = pendingCloseDate.value;

    if (!deal.value.customer_id) {
      const { customerId, error: conversionError } = await resolveWonCustomerId(supabase, deal.value.lead_id);
      if (conversionError || !customerId) {
        changingStage.value = false;
        const description = conversionError === "no_lead" ? t("crm.deals.noLeadForConversion") : conversionError;
        toast.add({ title: t("crm.deals.saveFailed"), description: description ?? undefined, color: "error" });
        return;
      }
      resolvedCustomerId = customerId;
      updates.customer_id = customerId;
    }

    // What was bought is recorded before the deal moves, so it can never be Won
    // without its products.
    const productsError = await saveWonProducts(resolvedCustomerId);
    if (productsError) {
      changingStage.value = false;
      toast.add({ title: t("crm.deals.saveFailed"), description: productsError, color: "error" });
      return;
    }
  }
  const { error } = await supabase.from("deals").update(updates).eq("id", dealId);

  if (error) {
    changingStage.value = false;
    toast.add({ title: t("crm.deals.saveFailed"), description: error.message, color: "error" });
    return;
  }

  // Backfill any quotes created earlier in the pipeline (before the deal had
  // a customer) now that one exists.
  if (isWonStage.value && resolvedCustomerId && resolvedCustomerId !== deal.value.customer_id) {
    await supabase
      .from("quotes")
      .update({ customer_id: resolvedCustomerId })
      .eq("deal_id", dealId)
      .is("customer_id", null);
  }

  // The stage change itself is auto-logged by a DB trigger (log_deal_activity)
  // — this adds the user's own note as a separate timeline entry right
  // alongside it, so the "why" isn't lost. Required except for Won/
  // competitor/archive (see noteRequired), but still recorded whenever one
  // is provided on those too.
  if (pendingNote.value.trim()) {
    // Tagged so automation rules ("assignee wrote a note") don't count this
    // hand-over comment as follow-up work.
    await supabase.from("deal_activities").insert({
      deal_id: dealId,
      type: "note",
      content: pendingNote.value.trim(),
      metadata: { stage_change: true },
    });
  }
  changingStage.value = false;

  deal.value.stage_id = pendingStageId.value;
  deal.value.stage_reason_id = pendingReasonId.value;
  if (isWonStage.value) {
    deal.value.value = pendingValue.value;
    deal.value.expected_close_date = pendingCloseDate.value;
    if (deal.value.customer_id !== resolvedCustomerId) {
      deal.value.customer_id = resolvedCustomerId;
      refreshCustomer();
    }
  }
  toast.add({ title: t("crm.deals.dealSaved"), color: "success" });
  stageChangeModalOpen.value = false;
  refreshActivities();
}

// --- Activity composer ---
interface ActivityTypeRow {
  id: string;
  key: string;
  name: string;
  icon: string;
  sort_order: number;
}

const { data: activityTypeRows } = await useAsyncData<ActivityTypeRow[]>(
  "crm-deal-activity-types",
  async () => {
    const { data, error } = await supabase.from("activity_types").select("*").order("sort_order");
    if (error) throw error;
    return data ?? [];
  },
);

// 'note' is a fixed built-in (its own always-visible quick composer, not
// part of the "log activity" modal) — the rest are admin-managed (see
// /admin/activity-types), so any number can exist.
const composerTypes = computed(() =>
  (activityTypeRows.value ?? []).map((r) => ({ key: r.key, name: r.name, icon: r.icon })),
);
const allActivityTypes = computed(() => [
  { key: "note", name: t("crm.deals.timeline.types.note"), icon: "i-lucide-sticky-note" },
  ...composerTypes.value,
]);
const manualTypeKeys = computed(() => new Set(allActivityTypes.value.map((t) => t.key)));

function activityIcon(typeKey: string) {
  if (typeKey === "created") return "i-lucide-sparkles";
  if (typeKey === "stage_changed") return "i-lucide-git-branch";
  if (typeKey === "assigned") return "i-lucide-user-check";
  return allActivityTypes.value.find((t) => t.key === typeKey)?.icon ?? "i-lucide-circle";
}

function activityTypeName(typeKey: string) {
  const known = allActivityTypes.value.find((t) => t.key === typeKey)?.name;
  if (known) return known;
  // A type that was removed from Settings later: use its built-in name when there is one.
  return te(`crm.deals.timeline.types.${typeKey}`) ? t(`crm.deals.timeline.types.${typeKey}`) : typeKey;
}

// Follow-up date/time — a calendar popover (defaults to today, opened via
// UPopover + UCalendar so the user can pick a day visually) plus a compact
// 12-hour time field. Shared by both the schedule and complete modals below.
const scheduledDate = ref<CalendarDate>(today(getLocalTimeZone()));
const scheduledTime = ref<Time>(new Time(9, 0));
const datePopoverOpen = ref(false);

const formattedScheduledDate = computed(() => {
  if (!scheduledDate.value) return "";
  return formatDMY(scheduledDate.value.toDate(getLocalTimeZone()));
});

function resetScheduleFields() {
  const now = new Date();
  scheduledDate.value = today(getLocalTimeZone());
  scheduledTime.value = new Time(now.getHours(), (Math.round(now.getMinutes() / 5) * 5) % 60);
}

function scheduledAtIso(): string | null {
  if (!scheduledDate.value || !scheduledTime.value) return null;
  return new Date(
    scheduledDate.value.year,
    scheduledDate.value.month - 1,
    scheduledDate.value.day,
    scheduledTime.value.hour,
    scheduledTime.value.minute,
    0,
    0,
  ).toISOString();
}

// --- Schedule a future activity — purely forward-looking: pick a type and
// a date/time, nothing else (no note — notes belong to what already
// happened, captured on completion instead). Only one open activity is
// allowed per deal at a time (DB-enforced), so the trigger button is
// disabled whenever one is already pending (see the "Upcoming" card).
const scheduleModalOpen = ref(false);
const scheduleType = ref("");
const scheduling = ref(false);
const scheduleSubmitDisabled = computed(
  () => !scheduleType.value || !scheduledDate.value || !scheduledTime.value,
);

function openScheduleModal() {
  scheduleType.value = composerTypes.value[0]?.key ?? "";
  resetScheduleFields();
  scheduleModalOpen.value = true;
}

async function scheduleActivity() {
  if (scheduleSubmitDisabled.value) return;
  scheduling.value = true;
  const { error } = await supabase.from("deal_activities").insert({
    deal_id: dealId,
    type: scheduleType.value,
    scheduled_at: scheduledAtIso(),
  });
  scheduling.value = false;

  if (error) {
    // A deal can hold only one open scheduled activity (unique index) — say
    // so in plain words instead of surfacing the raw constraint name.
    const alreadyOpen = error.message.includes("deal_activities_one_open_per_deal");
    toast.add({
      title: t("crm.deals.timeline.activityLogFailed"),
      description: alreadyOpen ? t("crm.deals.timeline.openActivityExists") : error.message,
      color: "error",
    });
    if (alreadyOpen) {
      scheduleModalOpen.value = false;
      refreshActivities();
    }
    return;
  }
  toast.add({ title: t("crm.deals.timeline.followUpScheduled"), color: "success" });
  scheduleModalOpen.value = false;
  refreshActivities();
}

// --- Mark an existing scheduled activity complete — always requires a note
// on what happened, and if the deal is still open, also requires scheduling
// the next action right behind it, so a deal is never left without one
// while active.
const completeModalOpen = ref(false);
const completingActivityId = ref<string | null>(null);
const nextActivityType = ref("");
const completionNote = ref("");
const completing = ref(false);

// The deal's stage can be changed right from this modal too, instead of
// requiring a separate trip to the stage stepper — defaults to the deal's
// current stage (no-op if left alone).
const completeStageId = ref<string | null>(null);
const completeReasonId = ref<string | null>(null);
const completeValue = ref<number | null>(null);
const completeCloseDate = ref("");
const completeFile = ref<File | null>(null);

const completeStage = computed(() => allStages.value?.find((s) => s.id === completeStageId.value));
const completeReasonOptions = computed(() =>
  (allReasons.value ?? [])
    .filter((r) => r.pipeline_id === deal.value?.pipeline_id && r.category === completeStage.value?.reason_category)
    .map((r) => ({ label: r.name, value: r.id })),
);
const completeIsWonStage = computed(() => completeStage.value?.system_key === "won");
const completeIsOfferSentStage = computed(() => completeStage.value?.system_key === "offer_sent");
const completeStageChanged = computed(() => completeStageId.value !== deal.value?.stage_id);

// Whether the deal will still be open after this completion — true if the
// stage picked in this same modal (which may differ from the deal's
// current one) isn't a closed stage.
const needsNextAction = computed(() => !completeStage.value?.is_closed);

const completeSubmitDisabled = computed(() => {
  if (!completionNote.value.trim()) return true;
  if (completeStage.value?.reason_category && !completeReasonId.value) return true;
  if (completeIsWonStage.value && (completeValue.value == null || !completeCloseDate.value)) return true;
  if (completeIsWonStage.value && completeStageChanged.value && !wonProductsOk.value) return true;
  if (completeIsOfferSentStage.value && !hasQuote.value && !completeFile.value) return true;
  if (!needsNextAction.value) return false;
  return !nextActivityType.value || !scheduledDate.value || !scheduledTime.value;
});

async function submitComplete() {
  if (completeSubmitDisabled.value || !completingActivityId.value || !deal.value) return;
  completing.value = true;

  if (completeStageChanged.value) {
    if (completeIsOfferSentStage.value && completeFile.value) {
      const { error: uploadError } = await uploadDealAttachment(completeFile.value);
      if (uploadError) {
        completing.value = false;
        toast.add({ title: t("crm.deals.attachmentUploadFailed"), description: uploadError, color: "error" });
        return;
      }
      refreshAttachments();
    }

    const updates: Record<string, unknown> = {
      stage_id: completeStageId.value,
      stage_reason_id: completeReasonId.value,
    };
    let resolvedCustomerId: string | null = deal.value.customer_id;
    if (completeIsWonStage.value) {
      updates.value = completeValue.value;
      updates.expected_close_date = completeCloseDate.value;

      if (!deal.value.customer_id) {
        const { customerId, error: conversionError } = await resolveWonCustomerId(supabase, deal.value.lead_id);
        if (conversionError || !customerId) {
          completing.value = false;
          const description = conversionError === "no_lead" ? t("crm.deals.noLeadForConversion") : conversionError;
          toast.add({ title: t("crm.deals.saveFailed"), description: description ?? undefined, color: "error" });
          return;
        }
        resolvedCustomerId = customerId;
        updates.customer_id = customerId;
      }

      const productsError = await saveWonProducts(resolvedCustomerId);
      if (productsError) {
        completing.value = false;
        toast.add({ title: t("crm.deals.saveFailed"), description: productsError, color: "error" });
        return;
      }
    }

    const { error: stageError } = await supabase.from("deals").update(updates).eq("id", dealId);
    if (stageError) {
      completing.value = false;
      toast.add({ title: t("crm.deals.saveFailed"), description: stageError.message, color: "error" });
      return;
    }

    if (completeIsWonStage.value && resolvedCustomerId && resolvedCustomerId !== deal.value.customer_id) {
      await supabase
        .from("quotes")
        .update({ customer_id: resolvedCustomerId })
        .eq("deal_id", dealId)
        .is("customer_id", null);
    }

    deal.value.stage_id = completeStageId.value!;
    deal.value.stage_reason_id = completeReasonId.value;
    if (completeIsWonStage.value) {
      deal.value.value = completeValue.value;
      deal.value.expected_close_date = completeCloseDate.value;
      if (deal.value.customer_id !== resolvedCustomerId) {
        deal.value.customer_id = resolvedCustomerId;
        refreshCustomer();
      }
    }
  }

  // Completes the activity (with its required note) and, if the deal is
  // still open (on whichever stage was just picked above), inserts the next
  // action atomically in the same call, so it can never end up completed
  // without a next action queued behind it.
  const { error } = await supabase.rpc("complete_deal_activity_with_followup", {
    p_activity_id: completingActivityId.value,
    p_content: completionNote.value.trim(),
    p_next_type: needsNextAction.value ? nextActivityType.value : null,
    p_next_scheduled_at: needsNextAction.value ? scheduledAtIso() : null,
  });
  completing.value = false;

  if (error) {
    toast.add({ title: t("crm.deals.timeline.activityCompleteFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("crm.deals.timeline.activityCompleted"), color: "success" });
  completeModalOpen.value = false;
  refreshActivities();
}

// Quick note — always-visible single-line composer just below the
// "Schedule Activity" button, separate from the modals above (which only
// offer the schedulable admin-managed types, not 'note').
const quickNoteContent = ref("");
const loggingNote = ref(false);

async function logNote() {
  if (!quickNoteContent.value.trim()) return;
  loggingNote.value = true;
  const { error } = await supabase.from("deal_activities").insert({
    deal_id: dealId,
    type: "note",
    content: quickNoteContent.value.trim(),
  });
  loggingNote.value = false;

  if (error) {
    toast.add({ title: t("crm.deals.timeline.activityLogFailed"), description: error.message, color: "error" });
    return;
  }

  toast.add({ title: t("crm.deals.timeline.activityLogged"), color: "success" });
  quickNoteContent.value = "";
  refreshActivities();
}

function markComplete(activity: Activity) {
  // Completing an activity always requires a note on what happened — and
  // if the deal is still open, it also can't be left without a next action
  // queued — so this always routes through the modal (see submitComplete),
  // never a silent direct update.
  completingActivityId.value = activity.id;
  nextActivityType.value = composerTypes.value[0]?.key ?? "";
  completionNote.value = "";
  completeStageId.value = deal.value?.stage_id ?? null;
  completeReasonId.value = deal.value?.stage_reason_id ?? null;
  completeValue.value = deal.value?.value ?? null;
  completeCloseDate.value = deal.value?.expected_close_date || today(getLocalTimeZone()).toString();
  completeFile.value = null;
  resetScheduleFields();
  completeModalOpen.value = true;
}

watch(completeStageId, (newStageId, oldStageId) => {
  if (newStageId === oldStageId) return;
  completeReasonId.value = null;
  completeFile.value = null;
  if (completeIsWonStage.value) {
    completeValue.value = deal.value?.value ?? null;
    completeCloseDate.value = deal.value?.expected_close_date || today(getLocalTimeZone()).toString();
    prepareWonProducts(completeCloseDate.value);
  }
});

async function removeActivity(activity: Activity) {
  const { error } = await supabase.from("deal_activities").delete().eq("id", activity.id);
  if (error) {
    toast.add({ title: t("crm.deals.timeline.activityDeleteFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("crm.deals.timeline.activityDeleted"), color: "success" });
  refreshActivities();
}

const upcomingActivities = computed(() =>
  (activities.value ?? [])
    .filter((a) => a.type !== "note" && manualTypeKeys.value.has(a.type) && a.scheduled_at && !a.completed_at)
    .sort((a, b) => new Date(a.scheduled_at!).getTime() - new Date(b.scheduled_at!).getTime()),
);

function formatDate(value: string | null | undefined, withTime = false) {
  if (!value) return "";
  return withTime ? formatDMYTime(value, locale.value) : formatDMY(value);
}

function stageName(id: string | null | undefined) {
  return allStages.value?.find((s) => s.id === id)?.name ?? "—";
}

// Open activities are cancelled when the deal's assignee changes (see
// cancel_open_activities_on_reassign); they carry a metadata flag so the
// timeline can tell that apart from a real completion.
function wasCancelledOnReassign(activity: Activity) {
  return !!activity.metadata?.cancelled_on_reassign;
}

function activityTitle(activity: Activity) {
  switch (activity.type) {
    case "created":
      return t("crm.deals.timeline.events.created");
    case "stage_changed":
      return t("crm.deals.timeline.events.stageChanged", {
        from: stageName(activity.metadata.from_stage_id as string),
        to: stageName(activity.metadata.to_stage_id as string),
      });
    case "assigned":
      if (activity.metadata.automation_rule_id) {
        return t("crm.deals.timeline.events.unassignedByRule", {
          rule: (activity.metadata.automation_rule_name as string) ?? "",
        });
      }
      return activity.metadata.to
        ? t("crm.deals.timeline.events.assignedTo", { to: profileLabel(activity.metadata.to as string) })
        : t("crm.deals.timeline.events.unassigned");
    default:
      return activityTypeName(activity.type);
  }
}

const timelineItems = computed<TimelineItem[]>(() =>
  (activities.value ?? []).map((a) => ({
    date: formatDate(a.created_at, true),
    title: activityTitle(a),
    // Every written note shows, whatever its type (even one whose activity type was later removed).
    description: !SYSTEM_TYPES.includes(a.type) ? (a.content?.trim() || undefined) : undefined,
    icon: activityIcon(a.type),
    actor: a.metadata?.automation_rule_id ? t("crm.deals.timeline.events.automationActor") : profileLabel(a.created_by),
    slot: "activity",
    _raw: a,
  })),
);

// --- Header summary, pipeline stepper and timeline filter -----------------
const contactName = computed(() => {
  if (customer.value) return customer.value.name;
  const l = leadContact.value;
  if (!l) return "—";
  return l.lead_type === "company" && l.company_name ? l.company_name : l.name;
});
const contactPhone = computed(() => customer.value?.phone ?? leadContact.value?.phone ?? null);
const dealCategoryList = computed(() => (deal.value?.title ? deal.value.title.split(/[،,]\s*/).filter(Boolean) : []));

function formatMoney(value: number | null | undefined) {
  if (!value) return null;
  return `${value.toLocaleString("en-US", { maximumFractionDigits: 0 })} ${t("common.currency")}`;
}

// Events the system logs by itself; everything else is something a person wrote or logged.
const SYSTEM_TYPES: string[] = ["created", "stage_changed", "assigned"];
const allActivities = computed(() => (activities.value ?? []) as Activity[]);

// The time in the current stage counts from the most recent stage change or
// assignment to a person, or from creation if neither happened.
const stageEnteredAt = computed(() => {
  // Stage changes, and assignments to a person (a new assignee gets a fresh clock).
  const changes = allActivities.value.filter((a) => a.type === "stage_changed" || (a.type === "assigned" && !!a.metadata?.to));
  const latest = changes.map((a) => a.created_at).sort().at(-1);
  return latest ?? deal.value?.created_at ?? null;
});
const daysInStage = computed(() =>
  stageEnteredAt.value ? Math.max(0, Date.now() - new Date(stageEnteredAt.value).getTime()) / 86400000 : 0,
);
const daysInStageLabel = computed(() =>
  daysInStage.value < 1
    ? t("crm.deals.stageAgeHours", { count: Math.max(1, Math.round(daysInStage.value * 24)) })
    : t("crm.deals.stageAgeDays", { count: Math.round(daysInStage.value) }),
);
const stageOverdue = computed(() => {
  const s = currentStage.value;
  if (!s || (s.max_stay_days == null && s.max_stay_hours == null)) return false;
  return daysInStage.value > (s.max_stay_days ?? 0) + (s.max_stay_hours ?? 0) / 24;
});

// Open stages form the stepper; closed ones (won / lost / archive) are
// offered separately as ways to close the deal.
const openStages = computed(() => pipelineStages.value.filter((s) => !s.is_closed));
const closedStages = computed(() => pipelineStages.value.filter((s) => s.is_closed));
const currentOpenIndex = computed(() => openStages.value.findIndex((s) => s.id === deal.value?.stage_id));
function stepClass(index: number) {
  if (index === currentOpenIndex.value) return "kords-step bg-primary font-semibold text-inverted shadow-[0_8px_24px_-12px_rgba(33,25,81,0.6)]";
  // A closed deal has been through every open stage.
  if (currentOpenIndex.value === -1 || index < currentOpenIndex.value)
    return "kords-step bg-primary/10 text-primary hover:bg-primary/15";
  return "kords-step bg-[#f5f5f7] text-[#6e6e73] hover:bg-primary/10";
}
function closeColor(stage: Stage): "success" | "error" | "neutral" {
  if (stage.system_key === "won") return "success";
  if (stage.reason_category === "competitor") return "error";
  return "neutral";
}

type TimelineFilter = "all" | "notes" | "activities" | "system";
const timelineFilter = ref<TimelineFilter>("all");
function filterMatches(type: Activity["type"], filter: TimelineFilter) {
  if (filter === "all") return true;
  if (filter === "notes") return type === "note";
  if (filter === "system") return SYSTEM_TYPES.includes(type);
  return type !== "note" && !SYSTEM_TYPES.includes(type);
}
const mainTab = ref<"details" | "files">("details");
// "Note" in the header: show the activity tab and put the cursor in the note box
const noteEl = ref<{ textareaRef?: HTMLTextAreaElement } | null>(null);
function focusNote() {
  mainTab.value = "details";
  nextTick(() => {
    noteEl.value?.textareaRef?.scrollIntoView({ behavior: "smooth", block: "center" });
    noteEl.value?.textareaRef?.focus();
  });
}
const mainTabs = computed(() => [
  { value: "details", label: t("crm.deals.activityTab") },
  { value: "files", label: `${t("files.tab")} (${attachments.value?.length ?? 0})` },
]);
function setTimelineFilter(v: TimelineFilter) {
  timelineFilter.value = v;
}
const timelineTabs = computed(() =>
  (["all", "notes", "activities", "system"] as const).map((value) => ({
    value,
    label: `${t(`crm.deals.timeline.filter.${value}`)} (${allActivities.value.filter((a) => filterMatches(a.type, value)).length})`,
  })),
);
const filteredTimelineItems = computed(() => timelineItems.value.filter((i) => filterMatches(i._raw.type, timelineFilter.value)));
function isPastDue(iso: string | null) {
  return !!iso && new Date(iso).getTime() < Date.now();
}
</script>

<template>
  <UDashboardPanel :ui="{ body: 'kords-canvas' }">
    <template #header>
      <UDashboardNavbar :title="deal?.title ?? t('crm.deals.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton v-if="canPushToCs" icon="i-lucide-send" color="primary" variant="soft" :label="t('crm.customers.pushToCs')" @click="pushOpen = true" />
          <UButton v-if="canDelete" icon="i-lucide-trash" color="error" variant="soft" :loading="deleting" @click="remove" />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>

      <div v-else-if="deal" class="grid grid-cols-1 gap-6 lg:grid-cols-3">
        <!-- Main column -->
        <div class="space-y-6 lg:col-span-2">
          <!-- Deal header: who it is, where it stands, and the things you do most -->
          <section class="kords-card kords-card-dark space-y-4 p-4 sm:p-5">
            <div class="flex flex-wrap items-start justify-between gap-4">
              <div class="min-w-0 space-y-1.5">
                <h2 class="truncate text-xl font-semibold text-highlighted sm:text-2xl">{{ contactName }}</h2>
                <div class="flex flex-wrap items-center gap-1.5">
                  <UBadge v-if="currentStage" :label="currentStage.name" color="primary" variant="solid" size="md" />
                  <UBadge v-for="cat in dealCategoryList" :key="cat" :label="cat" color="neutral" variant="subtle" size="sm" class="cds-tag" />
                </div>
              </div>
              <div class="text-end">
                <div class="text-2xl font-semibold" :class="deal.value ? 'text-success' : 'text-dimmed'">{{ formatMoney(deal.value) ?? "—" }}</div>
                <div class="text-xs text-muted">{{ t("crm.deals.value") }}</div>
              </div>
            </div>

            <!-- At a glance -->
            <dl class="grid grid-cols-2 gap-3 border-t border-default pt-3 sm:grid-cols-4">
              <div>
                <dt class="text-xs text-muted">{{ t("crm.deals.assignedTo") }}</dt>
                <dd class="mt-1 flex items-center gap-1.5 text-sm font-medium text-highlighted">
                  <KAvatar :name="deal.assigned_to ? profileLabel(deal.assigned_to) : null" kind="user" size="2xs" />
                  <span class="truncate">{{ profileLabel(deal.assigned_to) }}</span>
                </dd>
              </div>
              <div>
                <dt class="text-xs text-muted">{{ t("crm.deals.timeInStage") }}</dt>
                <dd class="mt-1 flex items-center gap-1 text-sm font-medium" :class="stageOverdue ? 'text-error' : 'text-highlighted'" :title="stageOverdue ? t('crm.deals.stageOverdue') : undefined">
                  <UIcon :name="stageOverdue ? 'i-lucide-triangle-alert' : 'i-lucide-clock'" class="size-4" />{{ daysInStageLabel }}
                </dd>
              </div>
              <div>
                <dt class="text-xs text-muted">{{ t("crm.deals.expectedCloseDate") }}</dt>
                <dd class="mt-1 text-sm font-medium text-highlighted">{{ formatDate(deal.expected_close_date) || "—" }}</dd>
              </div>
              <div>
                <dt class="text-xs text-muted">{{ t("crm.deals.createdOn") }}</dt>
                <dd class="mt-1 text-sm font-medium text-highlighted">{{ formatDate(deal.created_at) }}</dd>
              </div>
            </dl>

            <!-- Quick actions: the contact first, then what you can do with the deal -->
            <div class="grid grid-cols-2 gap-2 border-t border-default pt-3 sm:flex sm:flex-wrap">
              <UButton v-if="contactPhone" :to="`tel:${contactPhone}`" icon="i-lucide-phone" :label="t('crm.deals.callContact')" size="lg" color="neutral" variant="solid" class="justify-center border-0 !bg-sky-500 !text-white hover:!bg-sky-400" />
              <UButton v-if="toWhatsAppLink(contactPhone)" :to="toWhatsAppLink(contactPhone)!" target="_blank" rel="noopener noreferrer" icon="i-simple-icons-whatsapp" :label="t('crm.deals.chatOnWhatsApp')" size="lg" color="neutral" variant="solid" class="justify-center border-0 !bg-[#25D366] !text-white hover:!bg-[#1fb857]" />
              <UButton v-if="canEdit" icon="i-lucide-sticky-note" :label="t('crm.deals.quickNote')" size="lg" color="neutral" variant="solid" class="justify-center border-0 !bg-amber-400 !text-gray-900 hover:!bg-amber-300" @click="focusNote" />
              <UButton v-if="canEdit" icon="i-lucide-calendar-plus" :label="t('crm.deals.timeline.scheduleActivityButton')" size="lg" color="neutral" variant="solid" class="justify-center border-0 !bg-violet-500 !text-white hover:!bg-violet-400 disabled:!opacity-50" :disabled="upcomingActivities.length > 0" @click="openScheduleModal" />
              <UButton v-if="canRequestVisit" icon="i-lucide-map-pin-plus" :label="t('crm.visits.requestFromDeal')" size="lg" color="neutral" variant="solid" class="justify-center border-0 !bg-teal-500 !text-white hover:!bg-teal-400" @click="openVisitModal" />
              <UButton v-if="subPipeline && !subItem && canSendToWork" icon="i-lucide-send" :label="t('crm.work.send', { name: subPipeline.name })" size="lg" color="neutral" variant="solid" class="justify-center border-0 !bg-emerald-600 !text-white hover:!bg-emerald-500" @click="openSend" />
            </div>
          </section>

          <UTabs v-model="mainTab" :items="mainTabs" value-key="value" variant="link" :content="false" class="kords-pilltabs" />

          <FilesPanel v-if="mainTab === 'files'" :deal-id="dealId" :can-edit="canEdit" @changed="refreshAttachments" />

          <div v-show="mainTab === 'details'" class="space-y-6">
          <!-- Stage: where the deal is, and moving it -->
          <section class="kords-card space-y-4 p-4 sm:p-5">
            <div>
              <h3 class="text-sm font-semibold text-highlighted">{{ t("crm.deals.stageCardTitle") }}</h3>
              <p v-if="canEdit" class="text-xs text-muted">{{ t("crm.deals.stageCardHint") }}</p>
            </div>
            <div>
            <div class="grid grid-cols-2 gap-1.5 sm:flex sm:gap-2 sm:overflow-x-auto">
              <button
                v-for="(stage, index) in openStages"
                :key="stage.id"
                type="button"
                :disabled="!canEdit || changingStage"
                class="min-h-11 border px-3 py-2 text-center text-sm transition-colors disabled:cursor-not-allowed disabled:opacity-60 sm:min-h-0 sm:min-w-24 sm:flex-1 sm:[&:not(:first-child)]:-ms-px"
                :class="stepClass(index)"
                :aria-current="index === currentOpenIndex ? 'step' : undefined"
                @click="selectStage(stage.id)"
              >
                {{ stage.name }}
              </button>
            </div>
            <div v-if="closedStages.length" class="mt-3 flex flex-wrap items-center gap-2">
              <span class="text-xs text-muted">{{ t("crm.deals.closeAs") }}</span>
              <UButton
                v-for="stage in closedStages"
                :key="stage.id"
                :label="stage.name"
                :color="closeColor(stage)"
                :variant="stage.id === deal.stage_id ? 'solid' : 'outline'"
                :disabled="!canEdit || changingStage"
                size="sm"
                @click="selectStage(stage.id)"
              />
            </div>
            <p v-if="currentReasonName" class="mt-3 text-sm text-muted">
              {{ t("crm.deals.reason") }}: <span class="text-highlighted">{{ currentReasonName }}</span>
            </p>
          </div>
            <!-- The workflow this stage hands the deal to -->
            <div v-if="subPipeline" class="space-y-3 border-t border-default pt-4">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <div class="flex min-w-0 flex-wrap items-center gap-2 text-sm">
                <UIcon name="i-lucide-git-fork" class="size-5 shrink-0 text-primary" />
                <span class="font-medium text-highlighted">{{ subPipeline.name }}</span>
              </div>
              <div v-if="subItem" class="flex flex-wrap items-center gap-2">
                <UButton v-if="canOpenBoard" :to="`/technical-office/${subPipeline.id}`" color="neutral" variant="outline" icon="i-lucide-kanban" :label="t('crm.work.openBoard')" />
                <UButton v-if="canWithdraw" color="error" variant="ghost" icon="i-lucide-undo-2" :label="t('crm.work.withdraw')" @click="askWithdraw" />
              </div>
              <UButton v-else-if="canSendNew" icon="i-lucide-send" :label="t('crm.work.send', { name: subPipeline.name })" @click="openSend" />
            </div>
            <!-- Where the deal is in the workflow -->
            <ol v-if="subItem" class="flex flex-wrap items-center gap-1.5">
              <li
                v-for="(s, i) in subStages"
                :key="s.id"
                class="rounded-full border px-3 py-1 text-xs"
                :class="i === subStageIndex ? 'border-success bg-success text-inverted font-semibold' : i < subStageIndex ? 'border-success/40 bg-success/10 text-success' : 'border-default text-muted'"
              >
                {{ s.name }}
              </li>
            </ol>
          </div>
          </section>

          <!-- Write a note -->
          <section v-if="canEdit" class="kords-card space-y-2 p-4 sm:p-5">
            <h3 class="text-sm font-semibold text-highlighted">{{ t("crm.deals.composerTitle") }}</h3>
            <UTextarea
              ref="noteEl"
              v-model="quickNoteContent"
              :rows="3"
              :placeholder="t('crm.deals.timeline.quickNotePlaceholder')"
              class="w-full"
              @keydown.ctrl.enter.prevent="logNote"
              @keydown.meta.enter.prevent="logNote"
            />
            <div class="flex justify-end">
              <UButton icon="i-lucide-send-horizontal" :label="t('crm.deals.timeline.addNote')" :loading="loggingNote" :disabled="!quickNoteContent.trim()" @click="logNote" />
            </div>
          </section>

          <!-- Upcoming -->
          <UPageCard class="kords-card" v-if="upcomingActivities.length" :title="t('crm.deals.timeline.upcomingTitle')">
            <div class="space-y-2">
              <div
                v-for="activity in upcomingActivities"
                :key="activity.id"
                class="flex items-center justify-between gap-2 border border-s-4 border-default p-3"
                :class="isPastDue(activity.scheduled_at) ? 'border-s-error' : 'border-s-primary'"
              >
                <div class="flex items-center gap-2">
                  <UIcon :name="activityIcon(activity.type)" class="size-4 text-muted" />
                  <div>
                    <div class="flex items-center gap-2 text-sm font-medium text-highlighted">
                      {{ activityTypeName(activity.type) }}
                      <UBadge
                        v-if="isPastDue(activity.scheduled_at)"
                        :label="t('crm.deals.timeline.overdueLabel')"
                        color="error"
                        variant="subtle"
                        size="sm"
                        class="cds-tag"
                      />
                    </div>
                    <div v-if="activity.content" class="text-xs text-muted">{{ activity.content }}</div>
                    <div class="text-xs text-muted">
                      {{ formatDate(activity.scheduled_at, true) }} · {{ profileLabel(activity.created_by) }}
                    </div>
                  </div>
                </div>
                <UButton
                  v-if="canEdit"
                  :label="t('crm.deals.timeline.markComplete')"
                  size="xs"
                  variant="soft"
                  color="success"
                  @click="markComplete(activity)"
                />
              </div>
            </div>
          </UPageCard>

          <!-- Timeline -->
          <UPageCard class="kords-card">
            <template #header>
              <h2 class="font-semibold text-highlighted">{{ t("crm.deals.timeline.title") }}</h2>
            </template>
            <!-- compact filter chips: all / notes / activities / system -->
            <div class="mb-3 flex flex-wrap items-center gap-1.5">
              <button
                v-for="tab in timelineTabs"
                :key="tab.value"
                type="button"
                class="kords-chip !px-2.5 !py-1 !text-xs"
                :class="timelineFilter === tab.value && 'kords-chip-on'"
                @click="setTimelineFilter(tab.value)"
              >
                {{ tab.label }}
              </button>
            </div>
            <div v-if="!filteredTimelineItems.length" class="py-8 text-center text-sm text-muted">
              {{ t("crm.deals.timeline.noActivity") }}
            </div>
            <UTimeline v-else :items="filteredTimelineItems" size="sm">
              <template #activity-wrapper="{ item }">
                <div class="space-y-1">
                  <p class="text-xs text-muted"><bdi>{{ item.actor }}</bdi> · <bdi>{{ item.date }}</bdi></p>
                  <p class="font-medium text-highlighted">{{ item.title }}</p>
                  <p v-if="item.description" class="text-sm text-muted">{{ item.description }}</p>
                  <div class="flex items-center gap-2">
                    <UBadge
                      v-if="wasCancelledOnReassign(item._raw)"
                      :label="t('crm.deals.timeline.cancelledOnReassign')"
                      color="warning"
                      variant="subtle"
                      size="sm"
                    />
                    <UBadge
                      v-else-if="item._raw.completed_at"
                      :label="t('crm.deals.timeline.completedLabel')"
                      color="success"
                      variant="subtle"
                      size="sm"
                    />
                    <UButton
                      v-if="canEdit && !['created', 'stage_changed', 'assigned'].includes(item._raw.type)"
                      :label="t('common.delete')"
                      size="xs"
                      color="error"
                      variant="ghost"
                      @click="removeActivity(item._raw)"
                    />
                  </div>
                </div>
              </template>
            </UTimeline>
          </UPageCard>
          </div>
        </div>

        <!-- Sidebar -->
        <div class="space-y-6">
          <UPageCard class="kords-card" :title="t('crm.deals.contactTitle')">
            <div v-if="customer" class="space-y-1 text-sm">
              <p class="font-medium text-highlighted">{{ customer.name }}</p>
              <p v-if="customer.company" class="text-muted">{{ customer.company }}</p>
              <p v-if="customer.phone" class="flex items-center gap-1.5 text-muted">
                <a :href="`tel:${customer.phone}`" dir="ltr" class="hover:underline">{{ customer.phone }}</a>
                <a
                  v-if="toWhatsAppLink(customer.phone)"
                  :href="toWhatsAppLink(customer.phone)!"
                  target="_blank"
                  rel="noopener noreferrer"
                  :aria-label="t('crm.deals.chatOnWhatsApp')"
                  class="text-[#25D366] hover:opacity-80"
                  @click.stop
                >
                  <UIcon name="i-simple-icons-whatsapp" class="size-4" />
                </a>
              </p>
              <p v-if="customer.email" class="text-muted">{{ customer.email }}</p>
              <p v-if="leadContact?.area_id" class="flex items-center gap-1.5 text-muted">
                <UIcon name="i-lucide-map-pin" class="size-3.5" />{{ areaName(leadContact.area_id) }}
              </p>
              <p v-if="deal.lead_id" class="mt-2 text-xs text-muted">{{ t("crm.deals.fromLead") }}</p>
              <div class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1">
                <ULink :to="`/crm/customers/${deal.customer_id}`" class="inline-flex items-center gap-1 text-primary">
                  {{ t("crm.deals.viewCustomer") }}
                  <UIcon name="i-lucide-arrow-left" class="size-3" />
                </ULink>
                <button
                  v-if="canEditLead && leadContact"
                  type="button"
                  class="inline-flex items-center gap-1 text-primary"
                  @click="openEditLead"
                >
                  <UIcon name="i-lucide-pencil" class="size-3" />
                  {{ t("crm.deals.editLeadData") }}
                </button>
              </div>
            </div>
            <div v-else-if="leadContact" class="space-y-1 text-sm">
              <p class="font-medium text-highlighted">
                {{ leadContact.lead_type === "company" && leadContact.company_name ? leadContact.company_name : leadContact.name }}
              </p>
              <p v-if="leadContact.lead_type === 'company'" class="text-muted">{{ leadContact.name }}</p>
              <p v-if="leadContact.phone" class="flex items-center gap-1.5 text-muted">
                <a :href="`tel:${leadContact.phone}`" dir="ltr" class="hover:underline">{{ leadContact.phone }}</a>
                <a
                  v-if="toWhatsAppLink(leadContact.phone)"
                  :href="toWhatsAppLink(leadContact.phone)!"
                  target="_blank"
                  rel="noopener noreferrer"
                  :aria-label="t('crm.deals.chatOnWhatsApp')"
                  class="text-[#25D366] hover:opacity-80"
                  @click.stop
                >
                  <UIcon name="i-simple-icons-whatsapp" class="size-4" />
                </a>
              </p>
              <p v-if="leadContact.email" class="text-muted">{{ leadContact.email }}</p>
              <p v-if="leadContact.area_id" class="flex items-center gap-1.5 text-muted">
                <UIcon name="i-lucide-map-pin" class="size-3.5" />{{ areaName(leadContact.area_id) }}
              </p>
              <p class="mt-2 text-xs text-muted">{{ t("crm.deals.customerOnWin") }}</p>
              <div class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1">
                <ULink v-if="hasPermission('crm_leads', 'view')" :to="`/crm/leads/${deal.lead_id}`" class="inline-flex items-center gap-1 text-primary">
                  {{ t("crm.deals.viewLead") }}
                  <UIcon name="i-lucide-arrow-left" class="size-3" />
                </ULink>
                <button
                  v-if="canEditLead"
                  type="button"
                  class="inline-flex items-center gap-1 text-primary"
                  @click="openEditLead"
                >
                  <UIcon name="i-lucide-pencil" class="size-3" />
                  {{ t("crm.deals.editLeadData") }}
                </button>
              </div>
            </div>
          </UPageCard>

          <!-- Trips & inspections -->
          <UPageCard class="kords-card" v-if="canSeeVisits" :title="t('crm.visits.dealCardTitle')">
            <div class="space-y-2">
              <div v-for="v in dealVisits" :key="v.id">
              <NuxtLink
                :to="`/crm/visits?open=${v.id}`"
                class="flex flex-wrap items-center justify-between gap-2 border border-default p-3 transition-colors hover:border-primary hover:bg-elevated"
              >
                <span class="flex min-w-0 items-center gap-2 text-sm">
                  <UIcon :name="visitKindIcon(v.kind)" class="size-4 shrink-0 text-primary" />
                  <span class="font-medium text-highlighted">{{ visitKindLabel(v.kind) }}</span>
                  <span class="text-muted">· {{ visitFormatDate(v.visit_date) }} · <bdi dir="ltr">{{ visitTimeRange(v) }}</bdi></span>
                </span>
                <UBadge :label="visitStatusLabel(v.status)" :color="visitStatusColors[v.status]" variant="subtle" size="sm" class="cds-tag" />
              </NuxtLink>
              <div v-if="v.notes?.trim() || visitNotesOf(v.id).length" class="space-y-1 border border-t-0 border-default bg-muted p-2 text-xs text-toned">
                <p v-if="v.notes?.trim()" class="whitespace-pre-line">{{ v.notes }}</p>
                <p v-for="(e, i) in visitNotesOf(v.id)" :key="i" class="whitespace-pre-line text-muted">{{ e.note }}</p>
              </div>
              </div>
              <p v-if="!dealVisits?.length" class="text-sm text-muted">{{ t("crm.visits.dealCardEmpty") }}</p>
              <UButton
                v-if="canRequestVisit"
                icon="i-lucide-map-pin-plus"
                :label="t('crm.visits.requestFromDeal')"
                color="neutral"
                variant="outline"
                class="min-h-11 w-full justify-center sm:min-h-0 sm:w-auto"
                @click="openVisitModal"
              />
            </div>
          </UPageCard>

          <!-- Notes written on the lead this deal came from -->
          <UPageCard v-if="leadContact?.notes?.trim()" class="kords-card" :title="t('crm.deals.leadNotesTitle')">
            <p class="whitespace-pre-line text-sm text-toned">{{ leadContact.notes }}</p>
            <p class="mt-2 text-xs text-muted">
              {{ t("crm.deals.leadNotesFrom", { date: formatDate(leadContact.created_at) }) }}
              <ULink v-if="hasPermission('crm_leads', 'view')" :to="`/crm/leads/${leadContact.id}`" class="ms-2 text-primary">{{ t("crm.deals.viewLead") }}</ULink>
            </p>
          </UPageCard>

          <UPageCard class="kords-card" :title="t('common.details')">
            <div class="space-y-4">
              <UFormField :label="t('crm.deals.dealTitle')">
                <UInput v-model="deal.title" :disabled="!canEdit" class="w-full" />
              </UFormField>
              <UFormField :label="t('crm.deals.pipeline')">
                <USelect
                  v-model="deal.pipeline_id"
                  :items="pipelineOptions"
                  value-key="value"
                  :disabled="!canEdit"
                  class="w-full"
                  @update:model-value="onPipelineChange"
                />
              </UFormField>
              <UFormField :label="t('crm.deals.value')">
                <UInputNumber v-model="deal.value" :disabled="!canEdit" class="w-full" />
              </UFormField>
              <UFormField :label="t('crm.deals.expectedCloseDate')">
                <UInput v-model="deal.expected_close_date" type="date" :disabled="!canEdit" class="w-full" />
              </UFormField>
              <UFormField :label="t('crm.deals.assignedTo')">
                <USelect
                  :model-value="deal.assigned_to"
                  :items="assigneeOptions"
                  value-key="value"
                  :disabled="!canAssign"
                  class="w-full"
                  @update:model-value="(value: string | null) => openReassign(value)"
                />
                <p v-if="!canAssign" class="mt-1 text-xs text-muted">{{ t("crm.deals.assignPermissionHint") }}</p>
              </UFormField>
              <p class="text-xs text-muted">{{ t("crm.deals.createdOn") }}: {{ formatDate(deal.created_at) }}</p>
              <UButton v-if="canEdit" :label="t('common.save')" :loading="saving" @click="save" />
            </div>
          </UPageCard>

          <!-- Quotes card temporarily hidden — see layouts/dashboard.vue for
          the matching hide of the sidebar's Quotes nav entry. -->
        </div>
      </div>
    </template>
  </UDashboardPanel>

  <KDeleteConfirmation
    v-model:open="withdrawOpen"
    :title="t('crm.work.withdraw')"
    :message="t('crm.work.withdrawBody', { name: subPipeline?.name ?? '' })"
    :confirm-label="t('crm.work.withdraw')"
    :loading="withdrawing"
    @confirm="withdrawFromWork"
  />

  <KDialog v-model:open="sendOpen" :title="t('crm.work.sendTitle', { name: subPipeline?.name ?? '' })">
    <div class="space-y-4">
      <UFormField :label="t('crm.work.productCategory')" required>
        <USelect v-model="sendCategory" :items="sendCategoryItems" value-key="value" icon="i-lucide-tags" :placeholder="t('crm.work.productCategoryPick')" class="w-full" />
      </UFormField>
      <UFormField :label="t('crm.work.requestNote')" required>
        <UTextarea v-model="sendNote" :rows="4" :placeholder="t('crm.work.requestNoteHint')" class="w-full" autofocus />
      </UFormField>
      <UFormField :label="t('crm.work.deadline')" required>
        <USelect :model-value="sendDeadline ?? undefined" :items="deadlineItems" value-key="value" :placeholder="t('crm.work.deadlinePick')" class="w-full" @update:model-value="setDeadline" />
      </UFormField>
      <UFormField :label="t('crm.work.attachFiles')">
        <UFileUpload v-model="sendFiles" multiple class="w-full" />
      </UFormField>
    </div>
    <template #actions>
      <UButton color="neutral" variant="outline" :label="t('common.cancel')" @click="closeSend" />
      <UButton icon="i-lucide-send" :label="t('crm.work.confirmSend')" :loading="sendingToWork" :disabled="!sendValid" @click="sendToWork" />
    </template>
  </KDialog>

  <PushToCsModal v-if="canPushToCs && deal?.customer_id" v-model:open="pushOpen" :customer-id="deal.customer_id" :customer-name="deal.title" />

  <VisitRequestModal v-model:open="visitModalOpen" :deal-id="dealId" @saved="refreshVisits" />

  <UModal v-model:open="reassignOpen" :title="t('crm.deals.reassignTitle')">
    <template #body>
      <div class="space-y-4">
        <UFormField :label="t('crm.deals.assignedTo')">
          <USelect v-model="reassignTarget" :items="assigneeOptions" value-key="value" class="w-full" />
        </UFormField>
        <UFormField :label="t('crm.deals.stage')" required>
          <USelect
            v-model="reassignStageId"
            :items="pipelineStages.map((s) => ({ label: s.name, value: s.id }))"
            value-key="value"
            class="w-full"
          />
        </UFormField>
        <UFormField v-if="reassignStage?.reason_category" :label="t('crm.deals.reason')" required>
          <USelect v-model="reassignReasonId" :items="reassignReasonOptions" value-key="value" class="w-full" />
        </UFormField>
        <UFormField v-if="reassignIsWon && !hasContract" :label="t('crm.deals.contractFile')" :help="t('crm.deals.contractFileHint')" required>
          <UFileUpload v-model="contractFile" class="w-full" />
        </UFormField>
        <WonProductsFields
          v-if="reassignIsWon && !wonHasProducts"
          v-model="wonProducts"
          :defaults="{ contract_date: today(getLocalTimeZone()).toString(), sales_person_id: deal?.assigned_to ?? null }"
        />
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

  <UModal v-model:open="stageChangeModalOpen" :title="t('crm.deals.changeStage', { stage: pendingStage?.name })">
    <template #body>
      <div class="space-y-4">
        <template v-if="pendingStage?.reason_category">
          <p class="text-sm text-muted">{{ t("crm.deals.reasonRequired") }}</p>
          <USelect v-model="pendingReasonId" :items="pendingReasonOptions" value-key="value" class="w-full" />
        </template>
        <template v-if="isWonStage">
          <UFormField :label="t('crm.deals.value')" required>
            <UInputNumber v-model="pendingValue" class="w-full" />
          </UFormField>
          <UFormField :label="t('crm.deals.wonDate')" required>
            <UInput v-model="pendingCloseDate" type="date" class="w-full" />
          </UFormField>
          <UFormField v-if="!hasContract" :label="t('crm.deals.contractFile')" :help="t('crm.deals.contractFileHint')" required>
            <UFileUpload v-model="contractFile" class="w-full" />
          </UFormField>
          <WonProductsFields v-if="!wonHasProducts" v-model="wonProducts" :defaults="{ contract_date: pendingCloseDate, sales_person_id: deal?.assigned_to ?? null }" />
        </template>
        <template v-if="isOfferSentStage && !hasQuote">
          <UAlert
            icon="i-lucide-paperclip"
            color="warning"
            variant="subtle"
            :title="t('crm.deals.attachFileRequiredTitle')"
            :description="t('crm.deals.attachFileRequiredHint')"
          />
          <UFormField :label="t('crm.deals.attachFile')" required>
            <UFileUpload v-model="pendingFile" class="w-full" />
          </UFormField>
        </template>
        <UFormField v-if="noteRequired" :label="t('crm.deals.stageChangeNote')" required>
          <UTextarea
            v-model="pendingNote"
            :placeholder="t('crm.deals.stageChangeNotePlaceholder')"
            class="w-full"
            :rows="3"
            autofocus
          />
        </UFormField>
        <UButton
          :label="t('common.save')"
          :loading="changingStage"
          :disabled="
            (noteRequired && !pendingNote.trim()) ||
            (!!pendingStage?.reason_category && !pendingReasonId) ||
            (isWonStage && (pendingValue == null || !pendingCloseDate)) ||
            (isWonStage && !wonProductsOk) ||
            (isOfferSentStage && !hasQuote && !pendingFile)
          "
          block
          @click="confirmStageChange"
        />
      </div>
    </template>
  </UModal>

  <UModal v-model:open="scheduleModalOpen" :title="t('crm.deals.timeline.scheduleActivityButton')">
    <template #body>
      <div class="space-y-3">
        <div class="flex flex-wrap gap-2">
          <UButton
            v-for="type in composerTypes"
            :key="type.key"
            :label="type.name"
            :icon="type.icon"
            :variant="scheduleType === type.key ? 'solid' : 'soft'"
            :color="scheduleType === type.key ? 'primary' : 'neutral'"
            size="sm"
            @click="scheduleType = type.key"
          />
        </div>
        <div class="flex gap-3">
          <UFormField :label="t('crm.deals.timeline.scheduledDate')" required class="flex-1">
            <UPopover v-model:open="datePopoverOpen">
              <UButton
                color="neutral"
                variant="outline"
                icon="i-lucide-calendar"
                :label="formattedScheduledDate"
                class="w-full justify-start"
              />
              <template #content>
                <UCalendar v-model="scheduledDate" class="p-2" @update:model-value="datePopoverOpen = false" />
              </template>
            </UPopover>
          </UFormField>
          <UFormField :label="t('crm.deals.timeline.scheduledTime')" required class="flex-1">
            <UInputTime v-model="scheduledTime" locale="en-US" :hour-cycle="12" class="w-full" />
          </UFormField>
        </div>
        <UButton
          :label="t('crm.deals.timeline.scheduleActivityButton')"
          :loading="scheduling"
          :disabled="scheduleSubmitDisabled"
          block
          @click="scheduleActivity"
        />
      </div>
    </template>
  </UModal>

  <UModal
    v-model:open="completeModalOpen"
    :title="t('crm.deals.timeline.markComplete')"
    :close="false"
    :dismissible="false"
  >
    <template #body>
      <div class="space-y-3">
        <UTextarea
          v-model="completionNote"
          :placeholder="t('crm.deals.timeline.composerPlaceholder')"
          class="w-full"
          :rows="3"
          autofocus
        />

        <UFormField :label="t('crm.deals.changeStageLabel')">
          <USelect
            v-model="completeStageId"
            :items="pipelineStages.map((s) => ({ label: s.name, value: s.id }))"
            value-key="value"
            class="w-full"
          />
        </UFormField>

        <template v-if="completeStage?.reason_category">
          <p class="text-sm text-muted">{{ t("crm.deals.reasonRequired") }}</p>
          <USelect v-model="completeReasonId" :items="completeReasonOptions" value-key="value" class="w-full" />
        </template>

        <template v-if="completeIsWonStage">
          <UFormField :label="t('crm.deals.value')" required>
            <UInputNumber v-model="completeValue" class="w-full" />
          </UFormField>
          <UFormField :label="t('crm.deals.wonDate')" required>
            <UInput v-model="completeCloseDate" type="date" class="w-full" />
          </UFormField>
          <UFormField v-if="completeStageChanged && !hasContract" :label="t('crm.deals.contractFile')" :help="t('crm.deals.contractFileHint')" required>
            <UFileUpload v-model="contractFile" class="w-full" />
          </UFormField>
          <WonProductsFields
            v-if="completeStageChanged && !wonHasProducts"
            v-model="wonProducts"
            :defaults="{ contract_date: completeCloseDate, sales_person_id: deal?.assigned_to ?? null }"
          />
        </template>

        <template v-if="completeIsOfferSentStage && !hasQuote">
          <UAlert
            icon="i-lucide-paperclip"
            color="warning"
            variant="subtle"
            :title="t('crm.deals.attachFileRequiredTitle')"
            :description="t('crm.deals.attachFileRequiredHint')"
          />
          <UFormField :label="t('crm.deals.attachFile')" required>
            <UFileUpload v-model="completeFile" class="w-full" />
          </UFormField>
        </template>

        <template v-if="needsNextAction">
          <UAlert
            icon="i-lucide-calendar-clock"
            color="warning"
            variant="subtle"
            :title="t('crm.deals.timeline.forceScheduleTitle')"
            :description="t('crm.deals.timeline.forceScheduleHint')"
          />
          <div class="flex flex-wrap gap-2">
            <UButton
              v-for="type in composerTypes"
              :key="type.key"
              :label="type.name"
              :icon="type.icon"
              :variant="nextActivityType === type.key ? 'solid' : 'soft'"
              :color="nextActivityType === type.key ? 'primary' : 'neutral'"
              size="sm"
              @click="nextActivityType = type.key"
            />
          </div>
          <div class="flex gap-3">
            <UFormField :label="t('crm.deals.timeline.scheduledDate')" required class="flex-1">
              <UPopover v-model:open="datePopoverOpen">
                <UButton
                  color="neutral"
                  variant="outline"
                  icon="i-lucide-calendar"
                  :label="formattedScheduledDate"
                  class="w-full justify-start"
                />
                <template #content>
                  <UCalendar v-model="scheduledDate" class="p-2" @update:model-value="datePopoverOpen = false" />
                </template>
              </UPopover>
            </UFormField>
            <UFormField :label="t('crm.deals.timeline.scheduledTime')" required class="flex-1">
              <UInputTime v-model="scheduledTime" locale="en-US" :hour-cycle="12" class="w-full" />
            </UFormField>
          </div>
        </template>

        <UButton
          :label="t('crm.deals.timeline.markComplete')"
          :loading="completing"
          :disabled="completeSubmitDisabled"
          block
          @click="submitComplete"
        />
      </div>
    </template>
  </UModal>

  <UModal v-model:open="editLeadModalOpen" :title="t('crm.deals.editLeadDataTitle')">
    <template #body>
      <div class="space-y-3">
        <UFormField :label="t('crm.leads.leadType')">
          <URadioGroup v-model="editLeadType" orientation="horizontal" :items="editLeadTypeOptions" value-key="value" />
        </UFormField>
        <UFormField v-if="editLeadType === 'company'" :label="t('crm.leads.companyName')">
          <UInput v-model="editCompanyName" class="w-full" />
        </UFormField>
        <UFormField :label="editLeadType === 'company' ? t('crm.leads.contactPerson') : t('common.name')">
          <UInput v-model="editName" class="w-full" />
        </UFormField>
        <UFormField :label="t('common.phone')">
          <PhoneInput v-model="editPhone" />
        </UFormField>
        <UFormField :label="t('crm.leads.phone2')">
          <PhoneInput v-model="editPhone2" />
        </UFormField>
        <UFormField :label="t('cs.customers.area')">
          <AreaSelect v-model="editArea" />
        </UFormField>
        <UFormField :label="t('common.email')">
          <UInput v-model="editEmail" type="email" class="w-full" />
        </UFormField>
        <UFormField v-if="canSeeSource" :label="t('crm.leads.source')">
          <USelect v-model="editSource" :items="editSourceOptions" value-key="value" class="w-full" />
        </UFormField>
        <UButton
          :label="t('common.save')"
          :loading="editLeadSaving"
          :disabled="editLeadSubmitDisabled"
          block
          @click="saveEditLead"
        />
      </div>
    </template>
  </UModal>
</template>
