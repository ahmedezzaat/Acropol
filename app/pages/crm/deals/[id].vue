<script setup lang="ts">
import type { TimelineItem } from "@nuxt/ui";

definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "crm_deals" },
});

const route = useRoute();
const dealId = route.params.id as string;
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
  customer_id: string;
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

interface Quote {
  id: string;
  quote_number: string;
  status: string;
  total: number;
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

const { data: pipelines } = await useAsyncData<Pipeline[]>("crm-deal-pipelines", async () => {
  const { data, error } = await supabase.from("pipelines").select("id, name").order("sort_order");
  if (error) throw error;
  return data ?? [];
});
const { data: allStages } = await useAsyncData<Stage[]>("crm-deal-stages", async () => {
  const { data, error } = await supabase
    .from("pipeline_stages")
    .select("id, pipeline_id, name, sort_order, is_closed, reason_category")
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

const { data: customer } = await useAsyncData<Customer | null>(`crm-deal-${dealId}-customer`, async () => {
  if (!deal.value) return null;
  const { data, error } = await supabase
    .from("customers")
    .select("id, name, company, phone, email")
    .eq("id", deal.value.customer_id)
    .single();
  if (error) throw error;
  return data;
});

const { data: quotes } = await useAsyncData<Quote[]>(`crm-deal-${dealId}-quotes`, async () => {
  const { data, error } = await supabase
    .from("quotes")
    .select("id, quote_number, status, total")
    .eq("deal_id", dealId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data ?? [];
});

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

// --- Stage stepper: instant change, prompts for a reason when required ---
const stageReasonModalOpen = ref(false);
const pendingStageId = ref<string | null>(null);
const pendingReasonId = ref<string | null>(null);
const changingStage = ref(false);

const pendingStage = computed(() => allStages.value?.find((s) => s.id === pendingStageId.value));
const pendingReasonOptions = computed(() =>
  (allReasons.value ?? [])
    .filter((r) => r.pipeline_id === deal.value?.pipeline_id && r.category === pendingStage.value?.reason_category)
    .map((r) => ({ label: r.name, value: r.id })),
);

async function selectStage(stageId: string) {
  if (!canEdit.value || !deal.value || stageId === deal.value.stage_id) return;
  const targetStage = allStages.value?.find((s) => s.id === stageId);
  if (targetStage?.reason_category) {
    pendingStageId.value = stageId;
    pendingReasonId.value = null;
    stageReasonModalOpen.value = true;
    return;
  }
  await commitStageChange(stageId, null);
}

async function commitStageChange(stageId: string, reasonId: string | null) {
  if (!deal.value) return;
  changingStage.value = true;
  const { error } = await supabase
    .from("deals")
    .update({ stage_id: stageId, stage_reason_id: reasonId })
    .eq("id", dealId);
  changingStage.value = false;

  if (error) {
    toast.add({ title: t("crm.deals.saveFailed"), description: error.message, color: "error" });
    return;
  }
  deal.value.stage_id = stageId;
  deal.value.stage_reason_id = reasonId;
  toast.add({ title: t("crm.deals.dealSaved"), color: "success" });
  refreshActivities();
}

async function confirmStageReason() {
  if (!pendingStageId.value || !pendingReasonId.value) return;
  await commitStageChange(pendingStageId.value, pendingReasonId.value);
  stageReasonModalOpen.value = false;
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

const logComposerOpen = ref(false);
// 'log' = pick what already happened; 'schedule' = forced follow-up step,
// only entered when the deal isn't on a closed stage — a deal shouldn't be
// left without a next action while it's still open.
const composerStep = ref<"log" | "schedule">("log");
const activityType = ref("");
const activityContent = ref("");
const scheduleEnabled = ref(false);
const scheduledAt = ref("");
const logging = ref(false);

function openComposer() {
  composerStep.value = "log";
  activityType.value = composerTypes.value[0]?.key ?? "";
  activityContent.value = "";
  scheduleEnabled.value = false;
  scheduledAt.value = "";
  logComposerOpen.value = true;
}

async function logActivity() {
  if (!activityContent.value.trim() || !activityType.value) return;
  logging.value = true;
  const { error } = await supabase.from("deal_activities").insert({
    deal_id: dealId,
    type: activityType.value,
    content: activityContent.value.trim(),
    scheduled_at: scheduleEnabled.value && scheduledAt.value ? scheduledAt.value : null,
  });
  logging.value = false;

  if (error) {
    toast.add({ title: t("crm.deals.timeline.activityLogFailed"), description: error.message, color: "error" });
    return;
  }

  toast.add({ title: t("crm.deals.timeline.activityLogged"), color: "success" });
  refreshActivities();

  if (currentStage.value?.is_closed) {
    logComposerOpen.value = false;
    return;
  }

  // Deal is still open — force scheduling the next action before the
  // composer can close.
  composerStep.value = "schedule";
  activityType.value = composerTypes.value[0]?.key ?? "";
  activityContent.value = "";
  scheduledAt.value = "";
}

async function scheduleFollowUp() {
  if (!activityContent.value.trim() || !activityType.value || !scheduledAt.value) return;
  logging.value = true;
  const { error } = await supabase.from("deal_activities").insert({
    deal_id: dealId,
    type: activityType.value,
    content: activityContent.value.trim(),
    scheduled_at: scheduledAt.value,
  });
  logging.value = false;

  if (error) {
    toast.add({ title: t("crm.deals.timeline.activityLogFailed"), description: error.message, color: "error" });
    return;
  }

  toast.add({ title: t("crm.deals.timeline.followUpScheduled"), color: "success" });
  logComposerOpen.value = false;
  refreshActivities();
}

// Quick note — always-visible single-line composer just below the "Log
// Activity" button, separate from the modal (which only offers the
// schedulable admin-managed types, not 'note').
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

async function markComplete(activity: Activity) {
  const { error } = await supabase
    .from("deal_activities")
    .update({ completed_at: new Date().toISOString() })
    .eq("id", activity.id);
  if (error) {
    toast.add({ title: t("crm.deals.timeline.activityCompleteFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("crm.deals.timeline.activityCompleted"), color: "success" });
  refreshActivities();
}

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
                    <div class="text-sm font-medium text-highlighted">{{ activity.content }}</div>
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
                  icon="i-lucide-plus"
                  :label="t('crm.deals.timeline.logActivityButton')"
                  @click="openComposer"
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
              <p v-if="customer.phone" class="text-muted">{{ customer.phone }}</p>
              <p v-if="customer.email" class="text-muted">{{ customer.email }}</p>
              <p v-if="deal.lead_id" class="mt-2 text-xs text-muted">{{ t("crm.deals.fromLead") }}</p>
              <ULink :to="`/crm/customers/${deal.customer_id}`" class="mt-2 inline-flex items-center gap-1 text-primary">
                {{ t("crm.deals.viewCustomer") }}
                <UIcon name="i-lucide-arrow-left" class="size-3" />
              </ULink>
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

          <UPageCard :title="t('crm.deals.quotesTitle')">
            <template #footer v-if="canCreateQuote">
              <UButton :label="t('crm.deals.newQuote')" icon="i-lucide-plus" variant="soft" :loading="creatingQuote" @click="createQuote" />
            </template>
            <div v-if="!quotes?.length" class="text-sm text-muted">{{ t("crm.deals.noQuotesYet") }}</div>
            <ul v-else class="divide-y divide-default">
              <li v-for="quote in quotes" :key="quote.id" class="py-2">
                <ULink :to="`/crm/quotes/${quote.id}`" class="flex items-center justify-between">
                  <span>{{ quote.quote_number }}</span>
                  <span class="text-sm text-muted">{{ t(`crm.quotes.statusValues.${quote.status}`) }} · {{ quote.total }}</span>
                </ULink>
              </li>
            </ul>
          </UPageCard>
        </div>
      </div>
    </template>
  </UDashboardPanel>

  <UModal v-model:open="stageReasonModalOpen" :title="t('crm.deals.reason')">
    <template #body>
      <div class="space-y-4">
        <p class="text-sm text-muted">{{ t("crm.deals.reasonRequired") }}</p>
        <USelect v-model="pendingReasonId" :items="pendingReasonOptions" value-key="value" class="w-full" />
        <UButton
          :label="t('common.save')"
          :loading="changingStage"
          :disabled="!pendingReasonId"
          block
          @click="confirmStageReason"
        />
      </div>
    </template>
  </UModal>

  <UModal
    v-model:open="logComposerOpen"
    :title="composerStep === 'log' ? t('crm.deals.timeline.logActivityButton') : t('crm.deals.timeline.forceScheduleTitle')"
    :close="composerStep === 'log'"
    :dismissible="composerStep === 'log'"
  >
    <template #body>
      <div v-if="composerStep === 'log'" class="space-y-3">
        <div class="flex flex-wrap gap-2">
          <UButton
            v-for="type in composerTypes"
            :key="type.key"
            :label="type.name"
            :icon="type.icon"
            :variant="activityType === type.key ? 'solid' : 'soft'"
            :color="activityType === type.key ? 'primary' : 'neutral'"
            size="sm"
            @click="activityType = type.key"
          />
        </div>
        <UTextarea
          v-model="activityContent"
          :placeholder="t('crm.deals.timeline.composerPlaceholder')"
          class="w-full"
          :rows="3"
          autofocus
        />
        <div class="flex flex-wrap items-center gap-3">
          <UCheckbox v-model="scheduleEnabled" :label="t('crm.deals.timeline.scheduleToggle')" />
          <UInput v-if="scheduleEnabled" v-model="scheduledAt" type="datetime-local" />
        </div>
        <UButton
          :label="t('crm.deals.timeline.logActivity')"
          :loading="logging"
          :disabled="!activityContent.trim() || !activityType"
          block
          @click="logActivity"
        />
      </div>

      <div v-else class="space-y-3">
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
            :variant="activityType === type.key ? 'solid' : 'soft'"
            :color="activityType === type.key ? 'primary' : 'neutral'"
            size="sm"
            @click="activityType = type.key"
          />
        </div>
        <UTextarea
          v-model="activityContent"
          :placeholder="t('crm.deals.timeline.composerPlaceholder')"
          class="w-full"
          :rows="3"
        />
        <UFormField :label="t('crm.deals.timeline.scheduledAt')" required>
          <UInput v-model="scheduledAt" type="datetime-local" class="w-full" />
        </UFormField>
        <UButton
          :label="t('crm.deals.timeline.scheduleFollowUp')"
          :loading="logging"
          :disabled="!activityContent.trim() || !activityType || !scheduledAt"
          block
          @click="scheduleFollowUp"
        />
      </div>
    </template>
  </UModal>
</template>
