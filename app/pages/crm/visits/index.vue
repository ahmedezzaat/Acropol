<script setup lang="ts">
definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "crm_visits" },
});

useHead({ htmlAttrs: { class: "carbon" } });

const supabase = useSupabaseClient();
const user = useSupabaseUser();
const toast = useToast();
const route = useRoute();
const { t } = useI18n();
const { hasPermission, isAdmin } = usePermissions();
const { statusColors, statusLabel, kindLabel, kindIcon, formatDate, timeRange, dealLabel, visitSubject, visitTypes, loadDeals, loadTypes } = useVisits();

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

const me = computed(() => user.value?.sub as string | undefined);

const { data: visits, refresh } = await useAsyncData<Visit[]>("crm-visits", async () => {
  const { data, error } = await supabase
    .from("field_visits")
    .select("*")
    .order("visit_date", { ascending: false })
    .order("time_from", { ascending: false });
  if (error) throw error;
  return (data ?? []) as Visit[];
});

const { data: people } = await useAsyncData<{ profiles: Profile[]; teams: Team[] }>("crm-visits-people", async () => {
  const [{ data: profiles }, { data: teams }] = await Promise.all([
    supabase.from("profiles").select("id, full_name, email, team_id"),
    supabase.from("teams").select("id, leader_id"),
  ]);
  return { profiles: profiles ?? [], teams: teams ?? [] };
});
await useAsyncData("crm-visits-deals", async () => {
  await Promise.all([loadDeals(true), loadTypes(true)]);
  return true;
});

function personName(id: string | null) {
  if (!id) return "—";
  const p = people.value?.profiles.find((p) => p.id === id);
  return p?.full_name || p?.email || "?";
}

// ---- Who can do what (mirrors field_visit_action() in the database, which
// is the real enforcement; this only decides which buttons to offer).
const isFinalApprover = computed(
  () => isAdmin.value || hasPermission("crm_visits", "approve") || hasPermission("crm_visits", "view_all"),
);

function leaderOf(requesterId: string) {
  const teamId = people.value?.profiles.find((p) => p.id === requesterId)?.team_id;
  return people.value?.teams.find((tm) => tm.id === teamId)?.leader_id ?? null;
}

function availableActions(v: Visit): VisitAction[] {
  const mine = v.requested_by === me.value;
  const leader = leaderOf(v.requested_by);
  const isLeader = !!leader && leader === me.value;
  const actions: VisitAction[] = [];

  const canDecide =
    !mine &&
    ((v.status === "pending_leader" && (isLeader || isAdmin.value)) ||
      (v.status === "pending_final" && isFinalApprover.value));
  if (canDecide) actions.push("approve", "reject");

  const canClose = mine || isLeader || isFinalApprover.value;
  if (v.status === "approved" && canClose) actions.push("done");
  if (["pending_leader", "pending_final", "approved"].includes(v.status) && canClose) actions.push("cancel");
  return actions;
}

function needsMyAction(v: Visit) {
  return availableActions(v).includes("approve");
}

// ---- Filters
type Filter = "all" | "mine" | "pending" | "approved" | "done" | "closed";
const filter = ref<Filter>("all");
const kindFilter = ref<VisitKind | "all">("all");
const search = ref("");

const filterTabs = computed(() =>
  (["all", "mine", "pending", "approved", "done", "closed"] as const).map((f) => ({
    label: t(`crm.visits.filters.${f}`),
    value: f,
    badge: f === "mine" ? (visits.value ?? []).filter(needsMyAction).length || undefined : undefined,
  })),
);
const kindOptions = computed(() => [
  { label: t("crm.visits.allTypes"), value: "all" },
  ...visitTypes.value.map((x) => ({ label: x.name, value: x.key })),
]);

const filtered = computed(() =>
  (visits.value ?? []).filter((v) => {
    if (kindFilter.value !== "all" && v.kind !== kindFilter.value) return false;
    if (filter.value === "mine" && !needsMyAction(v)) return false;
    if (filter.value === "pending" && !["pending_leader", "pending_final"].includes(v.status)) return false;
    if (filter.value === "approved" && v.status !== "approved") return false;
    if (filter.value === "done" && v.status !== "done") return false;
    if (filter.value === "closed" && !["rejected", "cancelled"].includes(v.status)) return false;
    if (search.value) {
      const q = search.value.toLowerCase();
      const hay = `${dealLabel(v.deal_id)} ${personName(v.requested_by)} ${v.address} ${kindLabel(v.kind)}`.toLowerCase();
      if (!hay.includes(q)) return false;
    }
    return true;
  }),
);

// ---- Create / edit
const createOpen = ref(false);
const editOpen = ref(false);

// ---- Details
const detailOpen = ref(false);
const selected = ref<Visit | null>(null);
const events = ref<VisitEvent[]>([]);
const pendingAction = ref<VisitAction | null>(null);
const actionNote = ref("");
const acting = ref(false);

async function loadEvents(id: string) {
  const { data } = await supabase
    .from("field_visit_events")
    .select("*")
    .eq("visit_id", id)
    .order("created_at", { ascending: true });
  events.value = (data ?? []) as VisitEvent[];
}

async function openDetails(v: Visit) {
  selected.value = v;
  pendingAction.value = null;
  actionNote.value = "";
  events.value = [];
  detailOpen.value = true;
  await loadEvents(v.id);
}

// Opened from a notification: /crm/visits?open=<id>
onMounted(() => {
  const id = typeof route.query.open === "string" ? route.query.open : null;
  const v = id ? visits.value?.find((x) => x.id === id) : null;
  if (v) openDetails(v);
});

const canEdit = computed(() => {
  const v = selected.value;
  if (!v || v.requested_by !== me.value || !hasPermission("crm_visits", "edit")) return false;
  if (v.status === "pending_leader") return true;
  return v.status === "pending_final" && !events.value.some((e) => e.action === "leader_approved");
});

const noteRequired = computed(() => pendingAction.value !== null && pendingAction.value !== "approve");
const noteOk = computed(() => !noteRequired.value || actionNote.value.trim().length > 0);

function startAction(action: VisitAction) {
  pendingAction.value = action;
  actionNote.value = "";
}

async function runAction() {
  if (!selected.value || !pendingAction.value || !noteOk.value) return;
  acting.value = true;
  const { error } = await supabase.rpc("field_visit_action", {
    p_visit: selected.value.id,
    p_action: pendingAction.value,
    p_note: actionNote.value.trim() || null,
  });
  acting.value = false;

  if (error) {
    toast.add({ title: t("crm.visits.actionFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("crm.visits.actionDone"), color: "success" });
  pendingAction.value = null;
  actionNote.value = "";
  await refresh();
  selected.value = visits.value?.find((x) => x.id === selected.value!.id) ?? selected.value;
  await loadEvents(selected.value.id);
}

async function afterSaved() {
  await refresh();
  if (selected.value) {
    selected.value = visits.value?.find((x) => x.id === selected.value!.id) ?? selected.value;
  }
}

function openCreate() {
  createOpen.value = true;
}
// Editing replaces the details dialog instead of stacking on top of it (a
// second dialog opened over the first ends up behind it). The details dialog
// comes back when the edit dialog closes, saved or not.
function openEdit() {
  detailOpen.value = false;
  editOpen.value = true;
}
watch(editOpen, (isOpen) => {
  if (!isOpen && selected.value) detailOpen.value = true;
});
function cancelAction() {
  pendingAction.value = null;
}

const detailActions = computed(() => (selected.value ? availableActions(selected.value) : []));
function eventTime(value: string) {
  return new Date(value).toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });
}
function actionColor(a: VisitAction) {
  return a === "approve" || a === "done" ? "primary" : a === "reject" ? "error" : "neutral";
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="t('crm.visits.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton
            v-if="hasPermission('crm_visits', 'create')"
            icon="i-lucide-plus"
            :label="t('crm.visits.new')"
            @click="openCreate"
          />
        </template>
      </UDashboardNavbar>

      <div class="w-full space-y-3 border-b border-default px-4 py-3 sm:px-6">
        <div class="-mx-4 overflow-x-auto overflow-y-hidden px-4 [scrollbar-width:none] sm:mx-0 sm:px-0 [&::-webkit-scrollbar]:hidden">
          <UTabs v-model="filter" :items="filterTabs" value-key="value" variant="link" :content="false" class="w-max min-w-full" />
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <UInput
            v-model="search"
            icon="i-lucide-search"
            :placeholder="t('crm.visits.search')"
            class="min-w-0 flex-1 basis-48"
          />
          <USelect v-model="kindFilter" :items="kindOptions" value-key="value" class="w-40" />
        </div>
      </div>
    </template>

    <template #body>
      <p v-if="!filtered.length" class="py-16 text-center text-sm text-muted">{{ t("crm.visits.empty") }}</p>

      <div v-else class="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
        <button
          v-for="v in filtered"
          :key="v.id"
          type="button"
          class="flex flex-col gap-2 border border-default bg-default p-4 text-start transition-colors hover:border-primary hover:bg-elevated"
          :class="needsMyAction(v) && 'border-s-4 border-s-warning'"
          @click="openDetails(v)"
        >
          <div class="flex items-start justify-between gap-2">
            <span class="flex min-w-0 items-center gap-2 font-semibold text-highlighted">
              <UIcon :name="kindIcon(v.kind)" class="size-4 shrink-0 text-primary" />
              <span class="truncate">{{ kindLabel(v.kind) }} · {{ visitSubject(v) }}</span>
            </span>
            <UBadge :label="statusLabel(v.status)" :color="statusColors[v.status]" variant="subtle" size="sm" class="cds-tag shrink-0" />
          </div>
          <div class="flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-toned">
            <span class="flex items-center gap-1"><UIcon name="i-lucide-calendar" class="size-4" />{{ formatDate(v.visit_date) }}</span>
            <span class="flex items-center gap-1" dir="ltr"><UIcon name="i-lucide-clock" class="size-4" />{{ timeRange(v) }}</span>
          </div>
          <div class="flex items-start gap-1 text-sm text-muted">
            <UIcon name="i-lucide-map-pin" class="mt-0.5 size-4 shrink-0" />
            <span class="line-clamp-2">{{ v.address }}</span>
          </div>
          <div class="mt-1 flex items-center justify-between gap-2 text-xs text-muted">
            <span>{{ t("crm.visits.requestedBy") }}: {{ personName(v.requested_by) }}</span>
            <UBadge v-if="needsMyAction(v)" :label="t('crm.visits.filters.mine')" color="warning" size="sm" class="cds-tag" />
          </div>
        </button>
      </div>
    </template>
  </UDashboardPanel>

  <VisitRequestModal v-model:open="createOpen" @saved="refresh" />
  <VisitRequestModal v-model:open="editOpen" :visit="selected" @saved="afterSaved" />

  <UModal v-model:open="detailOpen" :title="selected ? `${kindLabel(selected.kind)} · ${visitSubject(selected)}` : ''">
    <template #body>
      <div v-if="selected" class="space-y-5">
        <div class="flex flex-wrap items-center gap-2">
          <UBadge :label="statusLabel(selected.status)" :color="statusColors[selected.status]" variant="subtle" class="cds-tag" />
          <NuxtLink v-if="selected.deal_id" :to="`/crm/deals/${selected.deal_id}`" class="text-sm text-primary hover:underline">
            {{ t("crm.visits.openDeal") }}
          </NuxtLink>
          <UButton
            v-if="canEdit"
            icon="i-lucide-pencil"
            size="xs"
            color="neutral"
            variant="outline"
            :label="t('crm.visits.edit')"
            class="ms-auto"
            @click="openEdit"
          />
        </div>

        <dl class="grid gap-3 text-sm sm:grid-cols-2">
          <div>
            <dt class="text-xs text-muted">{{ t("crm.visits.date") }}</dt>
            <dd class="font-medium text-highlighted">{{ formatDate(selected.visit_date) }}</dd>
          </div>
          <div>
            <dt class="text-xs text-muted">{{ t("crm.visits.timeFrom") }} – {{ t("crm.visits.timeTo") }}</dt>
            <dd class="font-medium text-highlighted" dir="ltr">{{ timeRange(selected) }}</dd>
          </div>
          <div class="sm:col-span-2">
            <dt class="text-xs text-muted">{{ t("crm.visits.address") }}</dt>
            <dd class="font-medium text-highlighted">{{ selected.address }}</dd>
          </div>
          <div v-if="selected.notes" class="sm:col-span-2">
            <dt class="text-xs text-muted">{{ t("crm.visits.notes") }}</dt>
            <dd class="whitespace-pre-line text-toned">{{ selected.notes }}</dd>
          </div>
          <div>
            <dt class="text-xs text-muted">{{ t("crm.visits.requestedBy") }}</dt>
            <dd class="text-toned">{{ personName(selected.requested_by) }}</dd>
          </div>
        </dl>

        <!-- Actions -->
        <div v-if="detailActions.length" class="space-y-3 border-t border-default pt-4">
          <template v-if="!pendingAction">
            <div class="flex flex-wrap gap-2">
              <UButton
                v-for="a in detailActions"
                :key="a"
                :label="t(`crm.visits.actions.${a}`)"
                :color="actionColor(a)"
                :variant="a === 'cancel' ? 'outline' : 'solid'"
                class="min-h-11 flex-1 justify-center sm:min-h-0 sm:flex-none"
                @click="startAction(a)"
              />
            </div>
          </template>
          <template v-else>
            <UFormField :label="t(`crm.visits.actionNote.${pendingAction}`)" :required="noteRequired">
              <UTextarea v-model="actionNote" :rows="3" autofocus class="w-full" />
            </UFormField>
            <div class="flex gap-2">
              <UButton
                color="neutral"
                variant="outline"
                :label="t('crm.visits.back')"
                class="flex-1 justify-center"
                @click="cancelAction"
              />
              <UButton
                :label="t('crm.visits.confirm')"
                :color="actionColor(pendingAction)"
                :loading="acting"
                :disabled="!noteOk"
                class="flex-1 justify-center"
                @click="runAction"
              />
            </div>
          </template>
        </div>

        <!-- History -->
        <div class="border-t border-default pt-4">
          <h3 class="mb-3 text-sm font-semibold text-highlighted">{{ t("crm.visits.history") }}</h3>
          <ol class="space-y-3">
            <li v-for="e in events" :key="e.id" class="flex gap-3 text-sm">
              <span class="mt-1.5 size-2 shrink-0 rounded-full bg-primary" />
              <div class="min-w-0">
                <div class="font-medium text-highlighted">
                  {{ t(`crm.visits.events.${e.action}`) }}
                  <span class="font-normal text-muted">· {{ personName(e.actor_id) }}</span>
                </div>
                <p v-if="e.note" class="whitespace-pre-line text-toned">{{ e.note }}</p>
                <div class="text-xs text-muted">{{ eventTime(e.created_at) }}</div>
              </div>
            </li>
          </ol>
        </div>
      </div>
    </template>
  </UModal>
</template>
