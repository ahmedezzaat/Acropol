<script setup lang="ts">
import type { TimelineItem } from "@nuxt/ui";
import { CalendarDate, Time, getLocalTimeZone, today } from "@internationalized/date";

definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "crm_deals" },
});

const route = useRoute();
const dealId = route.params.id as string;
useHead({ htmlAttrs: { class: "carbon" } });

const supabase = useSupabaseClient();
const toast = useToast();
const { hasPermission } = usePermissions();
const { t, locale } = useI18n();

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
    .select("id, pipeline_id, name, sort_order, is_closed, reason_category, system_key")
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
      .select("id, name, company_name, lead_type, phone, phone2, email, source")
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
      .select("id, file_name, storage_path, uploaded_by, created_at")
      .eq("deal_id", dealId)
      .order("created_at", { ascending: false });
    if (error) throw error;
    return data ?? [];
  },
);

// Uploads to the private deal-attachments bucket, then records the row
// that tracks it — the offer_sent DB trigger checks this table, so the
// row must exist before the stage update that follows.
async function uploadDealAttachment(file: File): Promise<{ error: string | null }> {
  const path = `${dealId}/${Date.now()}-${file.name}`;
  const { error: uploadError } = await supabase.storage.from("deal-attachments").upload(path, file);
  if (uploadError) return { error: uploadError.message };

  const { error: insertError } = await supabase
    .from("deal_attachments")
    .insert({ deal_id: dealId, file_name: file.name, storage_path: path });
  if (insertError) return { error: insertError.message };

  return { error: null };
}

async function downloadAttachment(attachment: DealAttachment) {
  const { data, error } = await supabase.storage
    .from("deal-attachments")
    .createSignedUrl(attachment.storage_path, 60);
  if (error || !data) {
    toast.add({ title: t("crm.deals.attachmentUploadFailed"), description: error?.message, color: "error" });
    return;
  }
  window.open(data.signedUrl, "_blank");
}

// --- Edit the deal's originating lead right from this page, without
// navigating away — the lead record is the source of the contact info
// shown in the sidebar card whether the deal has converted to a customer
// yet or not.
const editLeadTypeOptions = computed(() => [
  { label: t("crm.leads.type.individual"), value: "individual" },
  { label: t("crm.leads.type.company"), value: "company" },
]);
const editSourceKeys = ["facebook", "instagram", "meta", "google", "website", "event", "referral"] as const;
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
  if (canAssign.value) payload.assigned_to = deal.value.assigned_to;

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
  stageChangeModalOpen.value = true;
}

async function confirmStageChange() {
  if (!deal.value || !pendingStageId.value) return;
  if (noteRequired.value && !pendingNote.value.trim()) return;
  if (pendingStage.value?.reason_category && !pendingReasonId.value) return;
  if (isWonStage.value && (pendingValue.value == null || !pendingCloseDate.value)) return;
  if (isOfferSentStage.value && !pendingFile.value) return;

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
    await supabase.from("deal_activities").insert({
      deal_id: dealId,
      type: "note",
      content: pendingNote.value.trim(),
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
  return allActivityTypes.value.find((t) => t.key === typeKey)?.name ?? typeKey;
}

// Follow-up date/time — a calendar popover (defaults to today, opened via
// UPopover + UCalendar so the user can pick a day visually) plus a compact
// 12-hour time field. Shared by both the schedule and complete modals below.
const scheduledDate = ref<CalendarDate>(today(getLocalTimeZone()));
const scheduledTime = ref<Time>(new Time(9, 0));
const datePopoverOpen = ref(false);

const formattedScheduledDate = computed(() => {
  if (!scheduledDate.value) return "";
  return scheduledDate.value
    .toDate(getLocalTimeZone())
    .toLocaleDateString(locale.value === "ar" ? "ar" : "en", { dateStyle: "medium" });
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
    toast.add({ title: t("crm.deals.timeline.activityLogFailed"), description: error.message, color: "error" });
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
  if (completeIsOfferSentStage.value && !completeFile.value) return true;
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
  return new Date(value).toLocaleString(locale.value === "ar" ? "ar" : "en", {
    dateStyle: "medium",
    timeStyle: withTime ? "short" : undefined,
  });
}

function stageName(id: string | null | undefined) {
  return allStages.value?.find((s) => s.id === id)?.name ?? "—";
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
    description: manualTypeKeys.value.has(a.type) ? (a.content ?? undefined) : undefined,
    icon: activityIcon(a.type),
    actor: profileLabel(a.created_by),
    slot: "activity",
    _raw: a,
  })),
);
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="deal?.title ?? t('crm.deals.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
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
          <!-- Stage stepper -->
          <UPageCard>
            <div class="flex flex-wrap gap-2">
              <UButton
                v-for="stage in pipelineStages"
                :key="stage.id"
                :label="stage.name"
                :color="stage.id === deal.stage_id ? 'primary' : stage.is_closed ? 'neutral' : 'neutral'"
                :variant="stage.id === deal.stage_id ? 'solid' : 'soft'"
                :disabled="!canEdit || changingStage"
                size="sm"
                @click="selectStage(stage.id)"
              />
            </div>
            <p v-if="currentReasonName" class="mt-3 text-sm text-muted">
              {{ t("crm.deals.reason") }}: <span class="text-highlighted">{{ currentReasonName }}</span>
            </p>
          </UPageCard>

          <!-- Upcoming -->
          <UPageCard v-if="upcomingActivities.length" :title="t('crm.deals.timeline.upcomingTitle')">
            <div class="space-y-2">
              <div
                v-for="activity in upcomingActivities"
                :key="activity.id"
                class="flex items-center justify-between gap-2 rounded-lg border border-default p-3"
              >
                <div class="flex items-center gap-2">
                  <UIcon :name="activityIcon(activity.type)" class="size-4 text-muted" />
                  <div>
                    <div class="text-sm font-medium text-highlighted">{{ activityTypeName(activity.type) }}</div>
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
          <UPageCard>
            <template #header>
              <div class="flex items-center justify-between gap-2">
                <h2 class="font-semibold text-highlighted">{{ t("crm.deals.timeline.title") }}</h2>
                <UButton
                  v-if="canEdit"
                  icon="i-lucide-calendar-plus"
                  :label="t('crm.deals.timeline.scheduleActivityButton')"
                  :disabled="upcomingActivities.length > 0"
                  @click="openScheduleModal"
                />
              </div>
            </template>
            <div v-if="canEdit" class="mb-4 flex gap-2">
              <UInput
                v-model="quickNoteContent"
                icon="i-lucide-sticky-note"
                :placeholder="t('crm.deals.timeline.quickNotePlaceholder')"
                class="flex-1"
                @keyup.enter="logNote"
              />
              <UButton
                icon="i-lucide-send-horizontal"
                :label="t('crm.deals.timeline.addNote')"
                :loading="loggingNote"
                :disabled="!quickNoteContent.trim()"
                @click="logNote"
              />
            </div>
            <div v-if="!timelineItems.length" class="py-8 text-center text-sm text-muted">
              {{ t("crm.deals.timeline.noActivity") }}
            </div>
            <UTimeline v-else :items="timelineItems" size="sm">
              <template #activity-wrapper="{ item }">
                <div class="space-y-1">
                  <p class="text-xs text-muted">{{ item.actor }} · {{ item.date }}</p>
                  <p class="font-medium text-highlighted">{{ item.title }}</p>
                  <p v-if="item.description" class="text-sm text-muted">{{ item.description }}</p>
                  <div class="flex items-center gap-2">
                    <UBadge
                      v-if="item._raw.completed_at"
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

        <!-- Sidebar -->
        <div class="space-y-6">
          <UPageCard :title="t('crm.deals.contactTitle')">
            <div v-if="customer" class="space-y-1 text-sm">
              <p class="font-medium text-highlighted">{{ customer.name }}</p>
              <p v-if="customer.company" class="text-muted">{{ customer.company }}</p>
              <p v-if="customer.phone" class="flex items-center gap-1.5 text-muted">
                {{ customer.phone }}
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
                {{ leadContact.phone }}
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
              <p class="mt-2 text-xs text-muted">{{ t("crm.deals.customerOnWin") }}</p>
              <div class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1">
                <ULink :to="`/crm/leads/${deal.lead_id}`" class="inline-flex items-center gap-1 text-primary">
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

          <UPageCard :title="t('common.details')">
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
                  v-model="deal.assigned_to"
                  :items="assigneeOptions"
                  value-key="value"
                  :disabled="!canAssign"
                  class="w-full"
                />
                <p v-if="!canAssign" class="mt-1 text-xs text-muted">{{ t("crm.deals.assignPermissionHint") }}</p>
              </UFormField>
              <p class="text-xs text-muted">{{ t("crm.deals.createdOn") }}: {{ formatDate(deal.created_at) }}</p>
              <UButton v-if="canEdit" :label="t('common.save')" :loading="saving" @click="save" />
            </div>
          </UPageCard>

          <!-- Quotes card temporarily hidden — see layouts/dashboard.vue for
          the matching hide of the sidebar's Quotes nav entry. -->

          <UPageCard v-if="attachments?.length" :title="t('crm.deals.attachmentsTitle')">
            <ul class="divide-y divide-default">
              <li v-for="attachment in attachments" :key="attachment.id" class="py-2">
                <button
                  type="button"
                  class="flex w-full items-center gap-2 text-start text-primary"
                  @click="downloadAttachment(attachment)"
                >
                  <UIcon name="i-lucide-paperclip" class="size-4 shrink-0" />
                  <span class="truncate">{{ attachment.file_name }}</span>
                </button>
              </li>
            </ul>
          </UPageCard>
        </div>
      </div>
    </template>
  </UDashboardPanel>

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
        </template>
        <template v-if="isOfferSentStage">
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
            (isOfferSentStage && !pendingFile)
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
        </template>

        <template v-if="completeIsOfferSentStage">
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
        <UFormField :label="t('common.email')">
          <UInput v-model="editEmail" type="email" class="w-full" />
        </UFormField>
        <UFormField :label="t('crm.leads.source')">
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
