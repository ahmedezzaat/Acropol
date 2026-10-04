<script setup lang="ts">
import { CalendarDate, Time, getLocalTimeZone, today } from "@internationalized/date";

definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "crm_deals" },
});

const supabase = useSupabaseClient();
const toast = useToast();
const { t, locale } = useI18n();

interface ActivityRow {
  id: string;
  deal_id: string;
  type: string;
  content: string | null;
  scheduled_at: string | null;
  completed_at: string | null;
  created_by: string | null;
}

interface DealRow {
  id: string;
  title: string;
  customer_id: string | null;
  lead_id: string | null;
  assigned_to: string | null;
  stage_id: string;
}

interface Stage {
  id: string;
  is_closed: boolean;
}

interface ActivityTypeRow {
  key: string;
  name: string;
  icon: string;
}

interface Profile {
  id: string;
  full_name: string | null;
  email: string;
}

interface Customer {
  id: string;
  name: string;
}

interface LeadOption {
  id: string;
  name: string;
  lead_type: "individual" | "company";
  company_name: string | null;
}

// deal_activities RLS already scopes rows to what this user can see — own
// deals, plus their team's if they lead one, plus everyone's with
// crm_deals:view_all — the same three-tier model already proven on the CRM
// dashboard. A plain select is enough; no extra filtering needed here.
const { data: activities, refresh: refreshActivities, status } = await useAsyncData<ActivityRow[]>(
  "crm-calendar-activities",
  async () => {
    const { data, error } = await supabase
      .from("deal_activities")
      .select("id, deal_id, type, content, scheduled_at, completed_at, created_by")
      .not("scheduled_at", "is", null)
      .neq("type", "note")
      .order("scheduled_at", { ascending: true });
    if (error) throw error;
    return data ?? [];
  },
);

// Approved (and finished) field trips / inspections sit in the same calendar
// as calls and meetings. field_visits RLS scopes them: your own, your team's
// if you lead one, everyone's for approvers / view-all.
const { data: visits } = await useAsyncData<Visit[]>("crm-calendar-visits", async () => {
  const { data, error } = await supabase
    .from("field_visits")
    .select("*")
    .in("status", ["approved", "done"])
    .order("visit_date", { ascending: true });
  if (error) throw error;
  return (data ?? []) as Visit[];
});

const { data: deals } = await useAsyncData<DealRow[]>("crm-calendar-deals", async () => {
  const { data, error } = await supabase.from("deals").select("id, title, customer_id, lead_id, assigned_to, stage_id");
  if (error) throw error;
  return data ?? [];
});

const { data: stages } = await useAsyncData<Stage[]>("crm-calendar-stages", async () => {
  const { data, error } = await supabase.from("pipeline_stages").select("id, is_closed");
  if (error) throw error;
  return data ?? [];
});

const { data: activityTypeRows } = await useAsyncData<ActivityTypeRow[]>("crm-calendar-activity-types", async () => {
  const { data, error } = await supabase.from("activity_types").select("key, name, icon").order("sort_order");
  if (error) throw error;
  return data ?? [];
});

const { data: profiles } = await useAsyncData<Profile[]>("crm-calendar-profiles", async () => {
  const { data, error } = await supabase.from("profiles").select("id, full_name, email");
  if (error) throw error;
  return data ?? [];
});

const { data: customers } = await useAsyncData<Customer[]>("crm-calendar-customers", async () => {
  const { data, error } = await supabase.from("customers").select("id, name");
  if (error) throw error;
  return data ?? [];
});

const { data: leads } = await useAsyncData<LeadOption[]>("crm-calendar-leads", async () => {
  const { data, error } = await supabase.from("leads").select("id, name, lead_type, company_name");
  if (error) throw error;
  return data ?? [];
});

function dealById(id: string) {
  return deals.value?.find((d) => d.id === id);
}
function dealTitle(id: string) {
  return dealById(id)?.title ?? "—";
}
function dealContactName(id: string) {
  const deal = dealById(id);
  if (!deal) return "—";
  if (deal.customer_id) return customers.value?.find((c) => c.id === deal.customer_id)?.name ?? "—";
  const lead = leads.value?.find((l) => l.id === deal.lead_id);
  if (!lead) return "—";
  return lead.lead_type === "company" && lead.company_name ? lead.company_name : lead.name;
}
function profileLabel(id: string | null) {
  const p = profiles.value?.find((p) => p.id === id);
  return p?.full_name || p?.email || "—";
}
function activityTypeName(key: string) {
  return activityTypeRows.value?.find((t) => t.key === key)?.name ?? key;
}
function activityIcon(key: string) {
  return activityTypeRows.value?.find((t) => t.key === key)?.icon ?? "i-lucide-circle";
}
function dealIsClosed(dealId: string) {
  const deal = dealById(dealId);
  return !!stages.value?.find((s) => s.id === deal?.stage_id)?.is_closed;
}
function formatDate(value: string | null, withTime = true) {
  if (!value) return "";
  return new Date(value).toLocaleString(locale.value === "ar" ? "ar" : "en", {
    dateStyle: "medium",
    timeStyle: withTime ? "short" : undefined,
  });
}

const todayStart = computed(() => today(getLocalTimeZone()).toDate(getLocalTimeZone()));
const tomorrowStart = computed(() => today(getLocalTimeZone()).add({ days: 1 }).toDate(getLocalTimeZone()));

// Calls, meetings... and approved trips/inspections, merged into one timeline.
interface CalendarEntry {
  key: string;
  at: Date;
  closed: boolean;
  activity?: ActivityRow;
  visit?: Visit;
}

function visitStart(v: Visit) {
  return new Date(`${v.visit_date}T${v.time_from}`);
}

const entries = computed<CalendarEntry[]>(() => [
  ...(activities.value ?? []).map((a) => ({
    key: `a-${a.id}`,
    at: new Date(a.scheduled_at!),
    closed: !!a.completed_at,
    activity: a,
  })),
  ...(visits.value ?? []).map((v) => ({
    key: `v-${v.id}`,
    at: visitStart(v),
    closed: v.status === "done",
    visit: v,
  })),
]);

// Soonest first for today/upcoming, oldest-overdue-first for overdue. An
// approved trip whose day has passed without being marked done lands in
// Overdue — it still needs closing (done/cancelled, with a note).
const byTime = (a: CalendarEntry, b: CalendarEntry) => a.at.getTime() - b.at.getTime();
const openEntries = computed(() => entries.value.filter((e) => !e.closed).sort(byTime));

const todayEntries = computed(() => openEntries.value.filter((e) => e.at >= todayStart.value && e.at < tomorrowStart.value));
const overdueEntries = computed(() => openEntries.value.filter((e) => e.at < todayStart.value));
const upcomingEntries = computed(() => openEntries.value.filter((e) => e.at >= tomorrowStart.value));
const closedEntries = computed(() =>
  entries.value
    .filter((e) => e.closed)
    .sort((a, b) => {
      const when = (e: CalendarEntry) =>
        e.activity ? new Date(e.activity.completed_at!).getTime() : new Date(e.visit!.updated_at).getTime();
      return when(b) - when(a);
    }),
);

const activeTab = ref<"today" | "upcoming" | "overdue" | "closed">("today");
const tabItems = computed(() => [
  { label: `${t("crm.calendar.today")} (${todayEntries.value.length})`, value: "today" },
  { label: `${t("crm.calendar.upcoming")} (${upcomingEntries.value.length})`, value: "upcoming" },
  { label: `${t("crm.calendar.overdue")} (${overdueEntries.value.length})`, value: "overdue" },
  { label: `${t("crm.calendar.closed")} (${closedEntries.value.length})`, value: "closed" },
]);
const visibleEntries = computed(() => {
  if (activeTab.value === "today") return todayEntries.value;
  if (activeTab.value === "upcoming") return upcomingEntries.value;
  if (activeTab.value === "overdue") return overdueEntries.value;
  return closedEntries.value;
});

function openDeal(dealId: string) {
  navigateTo(`/crm/deals/${dealId}`);
}

const { statusColors: visitStatusColors, statusLabel: visitStatusLabel, kindLabel: visitKindLabel, kindIcon: visitKindIcon, formatDate: visitFormatDate, timeRange: visitTimeRange } = useVisits();
function openVisit(v: Visit) {
  navigateTo(`/crm/visits?open=${v.id}`);
}

// --- Complete an activity right from the list — same rule as the deal
// page: completing always requires a note, and if the deal is still open
// it can't be left without a next action queued right behind it.
const composerTypes = computed(() => activityTypeRows.value ?? []);
const completeModalOpen = ref(false);
const completingActivity = ref<ActivityRow | null>(null);
const completionNote = ref("");
const nextActivityType = ref("");
const completing = ref(false);

const needsNextAction = computed(
  () => !!completingActivity.value && !dealIsClosed(completingActivity.value.deal_id),
);
const completeSubmitDisabled = computed(() => {
  if (!completionNote.value.trim()) return true;
  if (!needsNextAction.value) return false;
  return !nextActivityType.value || !scheduledDate.value || !scheduledTime.value;
});

const scheduledDate = ref<CalendarDate>(today(getLocalTimeZone()));
const scheduledTime = ref<Time>(new Time(9, 0));
const datePopoverOpen = ref(false);
const formattedScheduledDate = computed(() =>
  scheduledDate.value
    ? scheduledDate.value.toDate(getLocalTimeZone()).toLocaleDateString(locale.value === "ar" ? "ar" : "en", { dateStyle: "medium" })
    : "",
);
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

function openCompleteModal(activity: ActivityRow) {
  completingActivity.value = activity;
  completionNote.value = "";
  nextActivityType.value = composerTypes.value[0]?.key ?? "";
  const now = new Date();
  scheduledDate.value = today(getLocalTimeZone());
  scheduledTime.value = new Time(now.getHours(), (Math.round(now.getMinutes() / 5) * 5) % 60);
  completeModalOpen.value = true;
}

async function submitComplete() {
  if (completeSubmitDisabled.value || !completingActivity.value) return;
  completing.value = true;
  const { error } = await supabase.rpc("complete_deal_activity_with_followup", {
    p_activity_id: completingActivity.value.id,
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
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="t('crm.calendar.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
      </UDashboardNavbar>
      <UDashboardToolbar>
        <template #left>
          <UTabs v-model="activeTab" :items="tabItems" value-key="value" />
        </template>
      </UDashboardToolbar>
    </template>

    <template #body>
      <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>

      <div v-else-if="!visibleEntries.length" class="py-16 text-center text-sm text-muted">
        {{ t("crm.calendar.noActivities") }}
      </div>

      <div v-else class="space-y-2">
        <template v-for="entry in visibleEntries" :key="entry.key">
          <!-- Approved / finished field trip or inspection -->
          <div
            v-if="entry.visit"
            class="flex cursor-pointer items-start gap-3 rounded-lg border border-s-4 border-default border-s-info p-3 hover:border-primary"
            @click="openVisit(entry.visit)"
          >
            <UIcon :name="visitKindIcon(entry.visit.kind)" class="mt-0.5 size-5 shrink-0 text-info" />
            <div class="min-w-0 flex-1">
              <div class="flex flex-wrap items-baseline justify-between gap-x-2">
                <span class="flex items-center gap-2 font-medium text-highlighted">
                  {{ visitKindLabel(entry.visit.kind) }}
                  <UBadge
                    :label="visitStatusLabel(entry.visit.status)"
                    :color="visitStatusColors[entry.visit.status]"
                    variant="subtle"
                    size="sm"
                    class="cds-tag"
                  />
                </span>
                <span class="text-xs" :class="activeTab === 'overdue' ? 'text-error' : 'text-muted'">
                  {{ visitFormatDate(entry.visit.visit_date) }} · <bdi dir="ltr">{{ visitTimeRange(entry.visit) }}</bdi>
                </span>
              </div>
              <div class="text-sm text-highlighted">{{ dealTitle(entry.visit.deal_id) }}</div>
              <div class="text-sm text-muted">{{ dealContactName(entry.visit.deal_id) }}</div>
              <div class="mt-1 flex flex-wrap items-center gap-x-2 text-xs text-muted">
                <span class="flex items-center gap-1"><UIcon name="i-lucide-map-pin" class="size-3.5" />{{ entry.visit.address }}</span>
                <span>· {{ profileLabel(entry.visit.requested_by) }}</span>
              </div>
            </div>
          </div>

          <!-- Call, meeting, site visit... -->
          <div
            v-else-if="entry.activity"
            class="flex cursor-pointer items-start gap-3 rounded-lg border border-default p-3 hover:border-primary"
            @click="openDeal(entry.activity.deal_id)"
          >
            <UIcon :name="activityIcon(entry.activity.type)" class="mt-0.5 size-5 shrink-0 text-muted" />
            <div class="min-w-0 flex-1">
              <div class="flex flex-wrap items-baseline justify-between gap-x-2">
                <span class="font-medium text-highlighted">{{ activityTypeName(entry.activity.type) }}</span>
                <span
                  class="text-xs"
                  :class="activeTab === 'overdue' ? 'text-error' : 'text-muted'"
                >
                  {{ formatDate(activeTab === "closed" ? entry.activity.completed_at : entry.activity.scheduled_at) }}
                </span>
              </div>
              <div class="text-sm text-highlighted">{{ dealTitle(entry.activity.deal_id) }}</div>
              <div class="text-sm text-muted">{{ dealContactName(entry.activity.deal_id) }}</div>
              <div class="mt-1 flex flex-wrap items-center gap-x-2 text-xs text-muted">
                <span v-if="entry.activity.content">{{ entry.activity.content }}</span>
                <span>· {{ profileLabel(dealById(entry.activity.deal_id)?.assigned_to ?? null) }}</span>
              </div>
            </div>
            <UButton
              v-if="activeTab !== 'closed'"
              :label="t('crm.deals.timeline.markComplete')"
              icon="i-lucide-check"
              size="xs"
              color="neutral"
              variant="soft"
              class="shrink-0"
              @click.stop="openCompleteModal(entry.activity)"
            />
          </div>
        </template>
      </div>
    </template>
  </UDashboardPanel>

  <UModal v-model:open="completeModalOpen" :title="t('crm.deals.timeline.markComplete')" :close="false" :dismissible="false">
    <template #body>
      <div class="space-y-3">
        <UTextarea
          v-model="completionNote"
          :placeholder="t('crm.deals.timeline.composerPlaceholder')"
          class="w-full"
          :rows="3"
          autofocus
        />

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
              <UInputTime v-model="scheduledTime" :hour-cycle="12" class="w-full" />
            </UFormField>
          </div>
        </template>

        <div class="flex gap-2">
          <UButton
            :label="t('common.cancel')"
            color="neutral"
            variant="ghost"
            :disabled="completing"
            @click="completeModalOpen = false"
          />
          <UButton
            :label="t('crm.deals.timeline.markComplete')"
            :loading="completing"
            :disabled="completeSubmitDisabled"
            block
            class="flex-1"
            @click="submitComplete"
          />
        </div>
      </div>
    </template>
  </UModal>
</template>
