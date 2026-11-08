<script setup lang="ts">
// Leave (الإجازات): your balances and working hours, asking for a vacation or a delay permission,
// your requests, and — for approvers — the requests waiting for you. People who may see everything
// also get every request and every balance.
import type { Approver, LeavePolicy, LeaveType } from "~/composables/useLeave";

definePageMeta({ layout: "dashboard" });
useHead({ htmlAttrs: { class: "carbon kords" } });

const supabase = useSupabaseClient();
const me = useSupabaseUser();
const toast = useToast();
const { t, locale } = useI18n();
const { hasPermission, isAdmin } = usePermissions();
const { loadTypes, loadPolicy, loadApprovers, loadMyApprover, errorText } = useLeave();

interface VacationRow {
  id: string; user_id: string; leave_type_id: string; start_date: string; end_date: string; days: number; note: string | null;
  approver_id: string; status: Status; attachments: { name: string; path: string }[]; decided_by: string | null; decided_at: string | null;
  decision_note: string | null; created_at: string;
}
interface DelayRow {
  id: string; user_id: string; delay_date: string; hours: number; reason: string | null; approver_id: string; status: Status;
  decided_by: string | null; decided_at: string | null; decision_note: string | null; created_at: string;
}
type Status = "pending" | "approved" | "rejected" | "cancelled";
interface Balance { user_id: string; leave_type_id: string; credit: number; used: number; pending: number }

const canViewAll = computed(() => isAdmin.value || hasPermission("leave", "view_all"));
const myId = computed(() => me.value?.sub as string);

const { data: setup } = await useAsyncData("leave-setup", async () => {
  const [types, policy, approvers, people, myApprover] = await Promise.all([
    loadTypes(),
    loadPolicy(),
    loadApprovers(),
    supabase.from("profiles").select("id, full_name, email").order("full_name"),
    loadMyApprover(),
  ]);
  return { types, policy, approvers, myApprover, people: (people.data ?? []) as Approver[] };
});
const types = computed<LeaveType[]>(() => setup.value?.types ?? []);
const policy = computed<LeavePolicy>(() => setup.value?.policy ?? { delay_max_hours: 2, delay_per_month: 3, weekend_days: [5, 6], year_start_month: 1, default_start: "09:00", default_end: "17:00" });
const approvers = computed(() => setup.value?.approvers ?? []);
// the person set to approve my requests: they go there automatically
const myApprover = computed(() => setup.value?.myApprover ?? null);
const nameOf = (id: string | null) => {
  const p = setup.value?.people.find((x) => x.id === id);
  return p ? p.full_name || p.email : "—";
};
const typeName = (id: string) => types.value.find((x) => x.id === id)?.name ?? "—";

// my working hours
const { data: schedule } = await useAsyncData("leave-my-schedule", async () => {
  const { data } = await supabase.from("user_work_schedules").select("start_time, end_time").eq("profile_id", myId.value).maybeSingle();
  return { start: (data?.start_time ?? policy.value.default_start).slice(0, 5), end: (data?.end_time ?? policy.value.default_end).slice(0, 5) };
});

const { data: requests, refresh } = await useAsyncData("leave-requests", async () => {
  const [v, d] = await Promise.all([
    supabase.from("leave_requests").select("*").order("created_at", { ascending: false }),
    supabase.from("leave_delay_requests").select("*").order("created_at", { ascending: false }),
  ]);
  return { vacations: (v.data ?? []) as VacationRow[], delays: (d.data ?? []) as DelayRow[] };
});
const { data: balances, refresh: refreshBalances } = await useAsyncData<Balance[]>("leave-balances", async () => {
  const { data } = await supabase.rpc("leave_balances", { p_all: canViewAll.value });
  return ((data ?? []) as Balance[]).map((b) => ({ ...b, credit: Number(b.credit), used: Number(b.used), pending: Number(b.pending) }));
});
const reloadAll = () => Promise.all([refresh(), refreshBalances()]);

// ---- My balances and my delay permission this month
const myBalances = computed(() => (balances.value ?? []).filter((b) => b.user_id === myId.value));
const remaining = computed(() => Object.fromEntries(myBalances.value.map((b) => [b.leave_type_id, Math.max(0, b.credit - b.used - b.pending)])));
const monthKey = () => new Date().toISOString().slice(0, 7);
const myDelays = computed(() => (requests.value?.delays ?? []).filter((d) => d.user_id === myId.value));
const delayUsed = computed(() => myDelays.value.filter((d) => ["pending", "approved"].includes(d.status) && d.delay_date.slice(0, 7) === monthKey()).length);

// ---- Lists
type Tab = "mine" | "approve" | "all" | "balances";
const tab = ref<Tab>("mine");
const waiting = computed(() => [
  ...(requests.value?.vacations ?? []).filter((r) => r.approver_id === myId.value && r.status === "pending").map((r) => ({ kind: "vacation" as const, row: r })),
  ...(requests.value?.delays ?? []).filter((r) => r.approver_id === myId.value && r.status === "pending").map((r) => ({ kind: "delay" as const, row: r })),
]);
function merged(rows: { vacations: VacationRow[]; delays: DelayRow[] }, filter: (userId: string) => boolean) {
  return [
    ...rows.vacations.filter((r) => filter(r.user_id)).map((r) => ({ kind: "vacation" as const, row: r })),
    ...rows.delays.filter((r) => filter(r.user_id)).map((r) => ({ kind: "delay" as const, row: r })),
  ].sort((a, b) => new Date(b.row.created_at).getTime() - new Date(a.row.created_at).getTime());
}
const mine = computed(() => merged(requests.value ?? { vacations: [], delays: [] }, (u) => u === myId.value));
const everyone = computed(() => merged(requests.value ?? { vacations: [], delays: [] }, () => true));
const tabs = computed(() => [
  { value: "mine", label: t("leave.tabs.mine") },
  ...(approvers.value.length || waiting.value.length || isAdmin.value || hasPermission("leave", "approve") ? [{ value: "approve", label: `${t("leave.tabs.approve")} (${waiting.value.length})` }] : []),
  ...(canViewAll.value ? [{ value: "all", label: t("leave.tabs.all") }, { value: "balances", label: t("leave.tabs.balances") }] : []),
]);

const statusTone = { pending: "warning", approved: "success", rejected: "error", cancelled: "neutral" } as const;

// ---- Everyone's balances (view all)
const balanceRows = computed(() => {
  const byUser = new Map<string, Balance[]>();
  for (const b of balances.value ?? []) byUser.set(b.user_id, [...(byUser.get(b.user_id) ?? []), b]);
  return [...byUser.entries()].map(([id, list]) => ({ id, name: nameOf(id), list }));
});

// ---- Ask / cancel / decide
const vacationOpen = ref(false);
const delayOpen = ref(false);
async function cancel(kind: "vacation" | "delay", id: string) {
  const { error } = await supabase.from(kind === "vacation" ? "leave_requests" : "leave_delay_requests").update({ status: "cancelled" }).eq("id", id);
  if (error) toast.add({ title: t("leave.requestFailed"), description: errorText(error.message), color: "error" });
  await reloadAll();
}
const deciding = ref<{ kind: "vacation" | "delay"; id: string; approve: boolean } | null>(null);
const decideOpen = computed({ get: () => !!deciding.value, set: (v) => { if (!v) deciding.value = null; } });
const decisionNote = ref("");
const decideBusy = ref(false);
function ask(kind: "vacation" | "delay", id: string, approve: boolean) {
  decisionNote.value = "";
  deciding.value = { kind, id, approve };
}
async function confirmDecision() {
  const d = deciding.value;
  if (!d) return;
  decideBusy.value = true;
  const { error } = await supabase.rpc("leave_decide", { p_kind: d.kind, p_id: d.id, p_approve: d.approve, p_note: decisionNote.value });
  decideBusy.value = false;
  if (error) {
    toast.add({ title: t("leave.requestFailed"), description: errorText(error.message), color: "error" });
    return;
  }
  deciding.value = null;
  await reloadAll();
}

// ---- Files of a request
async function download(file: { name: string; path: string }) {
  const { data, error } = await supabase.storage.from("leave-files").createSignedUrl(file.path, 60, { download: file.name });
  if (error || !data) {
    toast.add({ title: t("leave.downloadFailed"), description: error?.message, color: "error" });
    return;
  }
  const a = document.createElement("a");
  a.href = data.signedUrl;
  a.download = file.name;
  document.body.appendChild(a);
  a.click();
  a.remove();
}

const fmtDay = (d: string) => formatDMY(d);
</script>

<template>
  <UDashboardPanel :ui="{ body: 'kords-canvas !p-3 sm:!p-6' }">
    <template #header>
      <UDashboardNavbar :title="t('leave.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton icon="i-lucide-clock" color="neutral" variant="outline" :label="t('leave.requestDelay')" @click="delayOpen = true" />
          <UButton icon="i-lucide-calendar-plus" :label="t('leave.requestVacation')" @click="vacationOpen = true" />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <div class="space-y-5">
        <!-- Balances, delay permission and working hours -->
        <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <div v-for="b in myBalances" :key="b.leave_type_id" class="kords-card space-y-2 p-4">
            <p class="text-sm font-medium text-muted">{{ typeName(b.leave_type_id) }}</p>
            <p class="text-2xl font-semibold text-highlighted">{{ Math.max(0, b.credit - b.used - b.pending) }} <span class="text-sm font-normal text-muted">/ {{ b.credit }} {{ t("leave.day") }}</span></p>
            <UProgress :model-value="b.used + b.pending" :max="Math.max(b.credit, 1)" size="xs" />
            <p class="text-xs text-muted">{{ t("leave.usedPending", { used: b.used, pending: b.pending }) }}</p>
          </div>
          <div class="kords-card space-y-2 p-4">
            <p class="text-sm font-medium text-muted">{{ t("leave.delayPermission") }}</p>
            <p class="text-2xl font-semibold text-highlighted">{{ Math.max(0, policy.delay_per_month - delayUsed) }} <span class="text-sm font-normal text-muted">/ {{ policy.delay_per_month }} {{ t("leave.thisMonth") }}</span></p>
            <p class="text-xs text-muted">{{ t("leave.delayRule", { hours: policy.delay_max_hours, times: policy.delay_per_month }) }}</p>
          </div>
          <div class="kords-card space-y-2 p-4">
            <p class="text-sm font-medium text-muted">{{ t("leave.myHours") }}</p>
            <p class="text-2xl font-semibold text-highlighted" dir="ltr">{{ schedule?.start }} – {{ schedule?.end }}</p>
            <p class="text-xs text-muted">{{ t("leave.hoursHint") }}</p>
          </div>
        </div>

        <UTabs v-model="tab" :items="tabs" value-key="value" variant="link" size="sm" :content="false" class="kords-pilltabs" />

        <!-- A request row, for the lists below -->
        <template v-if="tab === 'mine' || tab === 'approve' || tab === 'all'">
          <p v-if="!(tab === 'mine' ? mine : tab === 'approve' ? waiting : everyone).length" class="kords-card p-8 text-center text-sm text-muted">{{ t("leave.empty") }}</p>
          <ul v-else class="space-y-2">
            <li v-for="x in (tab === 'mine' ? mine : tab === 'approve' ? waiting : everyone)" :key="`${x.kind}-${x.row.id}`" class="kords-card space-y-2 p-4 text-sm">
              <div class="flex flex-wrap items-center justify-between gap-2">
                <div class="flex flex-wrap items-center gap-2">
                  <UIcon :name="x.kind === 'vacation' ? 'i-lucide-calendar-heart' : 'i-lucide-clock'" class="size-4 text-primary" />
                  <span class="font-semibold text-highlighted">
                    <template v-if="x.kind === 'vacation'">{{ typeName((x.row as VacationRow).leave_type_id) }} · {{ fmtDay((x.row as VacationRow).start_date) }} → {{ fmtDay((x.row as VacationRow).end_date) }}</template>
                    <template v-else>{{ t("leave.delayPermission") }} · {{ fmtDay((x.row as DelayRow).delay_date) }}</template>
                  </span>
                  <KBadge :label="t(`leave.status.${x.row.status}`)" :tone="statusTone[x.row.status]" />
                </div>
                <span class="text-xs text-muted">{{ formatDMYTime(x.row.created_at, locale) }}</span>
              </div>
              <div class="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-muted">
                <span v-if="tab !== 'mine'" class="flex items-center gap-1"><UIcon name="i-lucide-user" class="size-3.5" />{{ nameOf(x.row.user_id) }}</span>
                <span v-if="x.kind === 'vacation'">{{ t("leave.daysCount", { n: (x.row as VacationRow).days }) }}</span>
                <span v-else>{{ t("leave.hoursCount", { n: (x.row as DelayRow).hours }) }}</span>
                <span class="flex items-center gap-1"><UIcon name="i-lucide-user-check" class="size-3.5" />{{ nameOf(x.row.approver_id) }}</span>
              </div>
              <p v-if="x.kind === 'vacation' ? (x.row as VacationRow).note : (x.row as DelayRow).reason" class="whitespace-pre-line text-toned">{{ x.kind === "vacation" ? (x.row as VacationRow).note : (x.row as DelayRow).reason }}</p>
              <div v-if="x.kind === 'vacation' && (x.row as VacationRow).attachments?.length" class="flex flex-wrap gap-1.5">
                <button v-for="f in (x.row as VacationRow).attachments" :key="f.path" type="button" class="flex max-w-full items-center gap-1 rounded-full border border-default px-2 py-0.5 text-xs text-primary hover:bg-muted" @click="download(f)">
                  <UIcon name="i-lucide-download" class="size-3.5 shrink-0" /><span class="truncate"><bdi>{{ f.name }}</bdi></span>
                </button>
              </div>
              <p v-if="x.row.decision_note" class="rounded-[8px] bg-muted p-2 text-xs text-toned">{{ nameOf(x.row.decided_by) }}: {{ x.row.decision_note }}</p>
              <div class="flex flex-wrap gap-2 pt-1">
                <template v-if="x.row.status === 'pending' && (x.row.approver_id === myId || isAdmin) && tab !== 'mine'">
                  <UButton size="xs" color="success" variant="soft" icon="i-lucide-check" :label="t('leave.approve')" @click="ask(x.kind, x.row.id, true)" />
                  <UButton size="xs" color="error" variant="soft" icon="i-lucide-x" :label="t('leave.reject')" @click="ask(x.kind, x.row.id, false)" />
                </template>
                <UButton v-if="x.row.status === 'pending' && x.row.user_id === myId" size="xs" color="neutral" variant="ghost" icon="i-lucide-undo-2" :label="t('leave.cancel')" @click="cancel(x.kind, x.row.id)" />
              </div>
            </li>
          </ul>
        </template>

        <!-- Everyone's balances (people who see everything) -->
        <div v-else-if="tab === 'balances'" class="kords-card overflow-x-auto">
          <table class="w-full min-w-[32rem] text-sm">
            <thead>
              <tr class="border-b border-default text-xs text-muted">
                <th class="px-4 py-3 text-start font-medium">{{ t("leave.employee") }}</th>
                <th v-for="ty in types" :key="ty.id" class="px-4 py-3 text-start font-medium">{{ ty.name }}</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-default">
              <tr v-for="r in balanceRows" :key="r.id" class="hover:bg-elevated">
                <td class="px-4 py-3 font-medium text-highlighted">{{ r.name }}</td>
                <td v-for="ty in types" :key="ty.id" class="px-4 py-3">
                  <template v-for="b in r.list.filter((x) => x.leave_type_id === ty.id)" :key="b.leave_type_id">
                    <span class="font-semibold">{{ Math.max(0, b.credit - b.used - b.pending) }}</span><span class="text-muted"> / {{ b.credit }}</span>
                    <span v-if="b.pending" class="ms-1 text-xs text-warning">({{ t("leave.pendingShort", { n: b.pending }) }})</span>
                  </template>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </template>
  </UDashboardPanel>

  <LeaveRequestModal v-model:open="vacationOpen" :types="types" :policy="policy" :approvers="approvers" :remaining="remaining" :fixed-approver="myApprover" @saved="reloadAll" />
  <DelayRequestModal v-model:open="delayOpen" :policy="policy" :approvers="approvers" :used-this-month="delayUsed" :schedule="schedule ?? { start: policy.default_start, end: policy.default_end }" :fixed-approver="myApprover" @saved="reloadAll" />

  <UModal v-model:open="decideOpen" :title="deciding?.approve ? t('leave.approve') : t('leave.reject')">
    <template #body>
      <div class="space-y-4">
        <UFormField :label="t('leave.decisionNote')">
          <UTextarea v-model="decisionNote" :rows="3" class="w-full" />
        </UFormField>
        <UButton :label="deciding?.approve ? t('leave.approve') : t('leave.reject')" :color="deciding?.approve ? 'success' : 'error'" :loading="decideBusy" size="lg" block @click="confirmDecision" />
      </div>
    </template>
  </UModal>
</template>
