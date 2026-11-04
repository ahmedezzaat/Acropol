<script setup lang="ts">
// Tasks: anyone can give a task to themselves or to another user, with a deadline, a priority, a
// note and (optionally) a customer. Three columns — to do, in progress, done — and cards can be
// dragged between them.
import type { TaskRow } from "~/components/TaskFormModal.vue";

definePageMeta({ layout: "dashboard" });
useHead({ htmlAttrs: { class: "carbon kords" } });

const supabase = useSupabaseClient();
const me = useSupabaseUser();
const toast = useToast();
const { t, locale } = useI18n();
const { hasPermission, hasAnyModulePermission, isAdmin } = usePermissions();

type Status = TaskRow["status"];
const STATUSES: Status[] = ["todo", "in_progress", "done"];

const { data: tasksData, refresh } = await useAsyncData<TaskRow[]>("tasks-list", async () => {
  const { data, error } = await supabase
    .from("tasks")
    .select("id, title, note, priority, status, deadline, customer_id, assigned_to, created_by, completed_at, created_at, customer:customers(id, name, company)")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as unknown as TaskRow[];
});
const tasks = computed(() => tasksData.value ?? []);
// how many files each task has (read on its own, so the page still works where files are not set up yet)
const { data: fileCounts, refresh: refreshCounts } = await useAsyncData<Record<string, number>>("tasks-file-counts", async () => {
  const { data } = await supabase.from("task_attachments").select("task_id");
  const counts: Record<string, number> = {};
  for (const r of data ?? []) counts[r.task_id as string] = (counts[r.task_id as string] ?? 0) + 1;
  return counts;
});
const { data: people } = await useAsyncData<{ id: string; full_name: string | null; email: string }[]>("tasks-people", async () => {
  const { data } = await supabase.from("profiles").select("id, full_name, email").eq("is_active", true).order("full_name");
  return data ?? [];
});
const personName = (id: string) => {
  const p = people.value?.find((x) => x.id === id);
  return p ? p.full_name || p.email : "—";
};

// ---- Filter: my tasks, tasks I gave to others, or everyone's (for those who may)
const canViewAll = computed(() => isAdmin.value || hasPermission("tasks", "view_all"));
type Scope = "mine" | "given" | "all";
const scope = ref<Scope>("mine");
const scopeTabs = computed(() => [
  { value: "mine", label: `${t("tasks.scope.mine")} (${tasks.value.filter((x) => x.assigned_to === me.value?.sub).length})` },
  { value: "given", label: `${t("tasks.scope.given")} (${tasks.value.filter((x) => x.created_by === me.value?.sub && x.assigned_to !== me.value?.sub).length})` },
  ...(canViewAll.value ? [{ value: "all", label: `${t("tasks.scope.all")} (${tasks.value.length})` }] : []),
]);
const shown = computed(() => {
  const mine = me.value?.sub;
  if (scope.value === "mine") return tasks.value.filter((x) => x.assigned_to === mine);
  if (scope.value === "given") return tasks.value.filter((x) => x.created_by === mine && x.assigned_to !== mine);
  return tasks.value;
});
const PRIORITY_RANK = { urgent: 0, high: 1, medium: 2, low: 3 } as const;
function column(status: Status) {
  const list = shown.value.filter((x) => x.status === status);
  if (status === "done") return list.sort((a, b) => new Date(b.completed_at ?? 0).getTime() - new Date(a.completed_at ?? 0).getTime());
  // soonest deadline first (none last), then the more important first
  return list.sort((a, b) => {
    const da = a.deadline ? new Date(a.deadline).getTime() : Infinity;
    const db = b.deadline ? new Date(b.deadline).getTime() : Infinity;
    return da - db || PRIORITY_RANK[a.priority] - PRIORITY_RANK[b.priority];
  });
}

const overdue = (x: TaskRow) => x.status !== "done" && !!x.deadline && new Date(x.deadline).getTime() < Date.now();
const priorityTone = { urgent: "error", high: "warning", medium: "primary", low: "neutral" } as const;
const statusTone = { todo: "neutral", in_progress: "primary", done: "success" } as const;
const statusIcon = { todo: "i-lucide-circle", in_progress: "i-lucide-loader", done: "i-lucide-circle-check" } as const;

// the page of a customer, for whoever may open it
function customerLink(id: string) {
  if (hasAnyModulePermission("cs_customers")) return `/cs/customers/${id}`;
  if (hasAnyModulePermission("crm_customers")) return `/crm/customers/${id}`;
  return null;
}
const canChange = (x: TaskRow) => x.created_by === me.value?.sub || x.assigned_to === me.value?.sub || isAdmin.value;
const canDelete = (x: TaskRow) => x.created_by === me.value?.sub || isAdmin.value;

// ---- Move a task between statuses
async function setStatus(task: TaskRow, status: Status) {
  if (task.status === status || !canChange(task)) return;
  const before = { status: task.status, completed_at: task.completed_at };
  task.status = status;
  task.completed_at = status === "done" ? new Date().toISOString() : null;
  const { error } = await supabase.from("tasks").update({ status }).eq("id", task.id);
  if (error) {
    task.status = before.status;
    task.completed_at = before.completed_at;
    toast.add({ title: t("tasks.saveFailed"), description: error.message, color: "error" });
  }
}
const nextStatus = (s: Status): Status => (s === "todo" ? "in_progress" : s === "in_progress" ? "done" : "todo");

// ---- Drag a card to another column
const dragId = ref<string | null>(null);
const overStatus = ref<Status | null>(null);
function onDrop(status: Status) {
  const task = tasks.value.find((x) => x.id === dragId.value);
  dragId.value = null;
  overStatus.value = null;
  if (task) setStatus(task, status);
}

// ---- Create / edit / delete
const formOpen = ref(false);
const editing = ref<TaskRow | null>(null);
function openNew() {
  editing.value = null;
  formOpen.value = true;
}
function openEdit(x: TaskRow) {
  editing.value = x;
  formOpen.value = true;
}
const removing = ref<TaskRow | null>(null);
const removeOpen = computed({ get: () => !!removing.value, set: (v) => { if (!v) removing.value = null; } });
const removeBusy = ref(false);
async function confirmRemove() {
  const x = removing.value;
  if (!x) return;
  removeBusy.value = true;
  const { data, error } = await supabase.from("tasks").delete().eq("id", x.id).select("id");
  removeBusy.value = false;
  if (error || !data?.length) {
    toast.add({ title: t("tasks.deleteFailed"), description: error?.message, color: "error" });
    return;
  }
  removing.value = null;
  await refresh();
}
</script>

<template>
  <UDashboardPanel :ui="{ body: 'kords-canvas !p-3 sm:!p-6' }">
    <template #header>
      <UDashboardNavbar :title="t('tasks.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton icon="i-lucide-plus" :label="t('tasks.new')" @click="openNew" />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <div class="space-y-4">
        <UTabs v-model="scope" :items="scopeTabs" value-key="value" variant="link" size="sm" :content="false" class="kords-pilltabs" />

        <div class="flex items-start gap-3 overflow-x-auto pb-4">
          <section v-for="s in STATUSES" :key="s" class="w-72 shrink-0 space-y-2 sm:w-80">
            <header class="flex items-center justify-between px-1">
              <h3 class="flex items-center gap-2 text-sm font-semibold text-highlighted">
                <UIcon :name="statusIcon[s]" class="size-4" :class="s === 'done' ? 'text-success' : s === 'in_progress' ? 'text-primary' : 'text-muted'" />
                {{ t(`tasks.status.${s}`) }}
              </h3>
              <KBadge :label="String(column(s).length)" :tone="statusTone[s]" />
            </header>
            <div
              class="min-h-32 space-y-2 rounded-[14px] bg-muted p-2 transition"
              :class="overStatus === s && 'ring-2 ring-primary/40'"
              @dragover.prevent="overStatus = s"
              @dragleave="overStatus = null"
              @drop.prevent="onDrop(s)"
            >
              <p v-if="!column(s).length" class="px-2 py-6 text-center text-xs text-muted">{{ t("tasks.empty") }}</p>
              <article
                v-for="x in column(s)"
                :key="x.id"
                class="kords-card space-y-2 p-3 text-sm"
                :class="[dragId === x.id && 'opacity-40', canChange(x) && 'cursor-grab active:cursor-grabbing']"
                :draggable="canChange(x)"
                @dragstart="dragId = x.id"
                @dragend="dragId = null; overStatus = null"
              >
                <div class="flex items-start justify-between gap-2">
                  <h4 class="font-semibold text-highlighted" :class="x.status === 'done' && 'text-muted line-through'">{{ x.title }}</h4>
                  <KBadge :label="t(`tasks.priority.${x.priority}`)" :tone="priorityTone[x.priority]" class="shrink-0" />
                </div>
                <p v-if="x.note" class="line-clamp-3 whitespace-pre-line text-xs text-toned">{{ x.note }}</p>
                <div v-if="x.deadline" class="flex items-center gap-1.5 text-xs" :class="overdue(x) ? 'font-semibold text-error' : 'text-muted'">
                  <UIcon name="i-lucide-calendar-clock" class="size-3.5" />{{ formatDMYTime(x.deadline, locale) }}
                  <KBadge v-if="overdue(x)" :label="t('tasks.overdue')" tone="error" />
                </div>
                <div v-if="x.customer" class="flex items-center gap-1.5 text-xs">
                  <UIcon name="i-lucide-user-round" class="size-3.5 text-muted" />
                  <NuxtLink v-if="customerLink(x.customer.id)" :to="customerLink(x.customer.id)!" class="truncate text-primary hover:underline" @click.stop>{{ x.customer.company || x.customer.name }}</NuxtLink>
                  <span v-else class="truncate text-toned">{{ x.customer.company || x.customer.name }}</span>
                </div>
                <div class="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 text-xs text-muted">
                  <span class="flex items-center gap-1"><UIcon name="i-lucide-user" class="size-3.5" />{{ x.assigned_to === me?.sub ? t("tasks.me") : personName(x.assigned_to) }}</span>
                  <button v-if="fileCounts?.[x.id]" type="button" class="flex items-center gap-1 text-primary hover:underline" :title="t('tasks.files')" @click="openEdit(x)">
                    <UIcon name="i-lucide-paperclip" class="size-3.5" />{{ fileCounts[x.id] }}
                  </button>
                  <span v-if="x.created_by !== x.assigned_to" class="truncate">{{ t("tasks.from", { name: x.created_by === me?.sub ? t("tasks.me") : personName(x.created_by) }) }}</span>
                </div>
                <div v-if="canChange(x)" class="flex items-center justify-between gap-2 pt-1">
                  <UButton
                    size="xs"
                    :color="x.status === 'in_progress' ? 'success' : 'primary'"
                    variant="soft"
                    :icon="x.status === 'done' ? 'i-lucide-rotate-ccw' : x.status === 'todo' ? 'i-lucide-play' : 'i-lucide-check'"
                    :label="x.status === 'todo' ? t('tasks.start') : x.status === 'in_progress' ? t('tasks.finish') : t('tasks.reopen')"
                    @click="setStatus(x, nextStatus(x.status))"
                  />
                  <div class="flex items-center">
                    <UButton icon="i-lucide-pencil" color="neutral" variant="ghost" size="xs" :aria-label="t('common.edit')" @click="openEdit(x)" />
                    <UButton v-if="canDelete(x)" icon="i-lucide-trash-2" color="error" variant="ghost" size="xs" :aria-label="t('common.delete')" @click="removing = x" />
                  </div>
                </div>
              </article>
            </div>
          </section>
        </div>
      </div>
    </template>
  </UDashboardPanel>

  <TaskFormModal v-model:open="formOpen" :task="editing" :people="people ?? []" @saved="() => { refresh(); refreshCounts(); }" @changed="refreshCounts" />

  <UModal v-model:open="removeOpen" :title="t('tasks.deleteTitle')">
    <template #body>
      <p class="text-sm text-toned">{{ t("tasks.deleteBody", { name: removing?.title ?? "" }) }}</p>
    </template>
    <template #footer>
      <div class="flex w-full justify-end gap-2">
        <UButton color="neutral" variant="outline" :label="t('common.cancel')" @click="removing = null" />
        <UButton color="error" :label="t('common.delete')" :loading="removeBusy" @click="confirmRemove" />
      </div>
    </template>
  </UModal>
</template>
