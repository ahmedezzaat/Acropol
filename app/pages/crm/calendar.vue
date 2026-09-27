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

const openActivities = computed(() => (activities.value ?? []).filter((a) => !a.completed_at));

// The base query is already ordered by scheduled_at ascending, so each
// filter below inherits the right order for free — soonest first for
// today/upcoming, oldest-overdue-first for overdue.
const todayActivities = computed(() =>
  openActivities.value.filter((a) => {
    const d = new Date(a.scheduled_at!);
    return d >= todayStart.value && d < tomorrowStart.value;
  }),
);
const overdueActivities = computed(() =>
  openActivities.value.filter((a) => new Date(a.scheduled_at!) < todayStart.value),
);
const upcomingActivities = computed(() =>
  openActivities.value.filter((a) => new Date(a.scheduled_at!) >= tomorrowStart.value),
);
const closedActivities = computed(() =>
  (activities.value ?? [])
    .filter((a) => !!a.completed_at)
    .sort((a, b) => new Date(b.completed_at!).getTime() - new Date(a.completed_at!).getTime()),
);

const activeTab = ref<"today" | "upcoming" | "overdue" | "closed">("today");
const tabItems = computed(() => [
  { label: `${t("crm.calendar.today")} (${todayActivities.value.length})`, value: "today" },
  { label: `${t("crm.calendar.upcoming")} (${upcomingActivities.value.length})`, value: "upcoming" },
  { label: `${t("crm.calendar.overdue")} (${overdueActivities.value.length})`, value: "overdue" },
  { label: `${t("crm.calendar.closed")} (${closedActivities.value.length})`, value: "closed" },
]);
const visibleActivities = computed(() => {
  if (activeTab.value === "today") return todayActivities.value;
  if (activeTab.value === "upcoming") return upcomingActivities.value;
  if (activeTab.value === "overdue") return overdueActivities.value;
  return closedActivities.value;
});

function openDeal(dealId: string) {
  navigateTo(`/crm/deals/${dealId}`);
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

      <div v-else-if="!visibleActivities.length" class="py-16 text-center text-sm text-muted">
        {{ t("crm.calendar.noActivities") }}
      </div>

      <div v-else class="space-y-2">
        <div
          v-for="activity in visibleActivities"
          :key="activity.id"
          class="flex cursor-pointer items-start gap-3 rounded-lg border border-default p-3 hover:border-primary"
          @click="openDeal(activity.deal_id)"
        >
          <UIcon :name="activityIcon(activity.type)" class="mt-0.5 size-5 shrink-0 text-muted" />
          <div class="min-w-0 flex-1">
            <div class="flex flex-wrap items-baseline justify-between gap-x-2">
              <span class="font-medium text-highlighted">{{ activityTypeName(activity.type) }}</span>
              <span
                class="text-xs"
                :class="activeTab === 'overdue' ? 'text-error' : 'text-muted'"
              >
                {{ formatDate(activeTab === "closed" ? activity.completed_at : activity.scheduled_at) }}
              </span>
            </div>
            <div class="text-sm text-highlighted">{{ dealTitle(activity.deal_id) }}</div>
            <div class="text-sm text-muted">{{ dealContactName(activity.deal_id) }}</div>
            <div class="mt-1 flex flex-wrap items-center gap-x-2 text-xs text-muted">
              <span v-if="activity.content">{{ activity.content }}</span>
              <span>· {{ profileLabel(dealById(activity.deal_id)?.assigned_to ?? null) }}</span>
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
            @click.stop="openCompleteModal(activity)"
          />
        </div>
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
