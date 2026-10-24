<script setup lang="ts">
// Sub-workflows: pipelines with their own stages and board (e.g. the technical
// office). A deal stage hands a deal to one of them (set in the deal pipeline editor).
definePageMeta({ layout: "dashboard" });

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

interface StageRow {
  _key: string;
  id: string | null;
  name: string;
}
interface Workflow {
  id: string;
  name: string;
  stages: StageRow[];
  removed: string[];
  saving: boolean;
}

let keySeed = 0;
const newKey = () => `k${++keySeed}`;

const workflows = ref<Workflow[]>([]);
const loading = ref(true);

async function load() {
  const [{ data: pipelines }, { data: stages }] = await Promise.all([
    supabase.from("work_pipelines").select("id, name").order("sort_order"),
    supabase.from("work_pipeline_stages").select("id, work_pipeline_id, name").order("sort_order"),
  ]);
  workflows.value = (pipelines ?? []).map((p) => ({
    id: p.id,
    name: p.name,
    removed: [],
    saving: false,
    stages: (stages ?? []).filter((s) => s.work_pipeline_id === p.id).map((s) => ({ _key: newKey(), id: s.id, name: s.name })),
  }));
  loading.value = false;
}
await load();

async function createWorkflow() {
  const { data, error } = await supabase
    .from("work_pipelines")
    .insert({ name: t("admin.workPipelines.new"), sort_order: workflows.value.length + 1 })
    .select("id")
    .single();
  if (error || !data) {
    toast.add({ title: t("admin.workPipelines.saveFailed"), description: error?.message, color: "error" });
    return;
  }
  await load();
}

function addStage(w: Workflow) {
  w.stages.push({ _key: newKey(), id: null, name: t("admin.workPipelines.newStageDefault") });
}
function removeStage(w: Workflow, index: number) {
  const s = w.stages[index]!;
  if (s.id) w.removed.push(s.id);
  w.stages.splice(index, 1);
}
function moveStage(w: Workflow, index: number, dir: -1 | 1) {
  const to = index + dir;
  if (to < 0 || to >= w.stages.length) return;
  const [s] = w.stages.splice(index, 1);
  w.stages.splice(to, 0, s!);
}

async function save(w: Workflow) {
  w.saving = true;
  const fail = (message: string) => {
    w.saving = false;
    toast.add({ title: t("admin.workPipelines.saveFailed"), description: message, color: "error" });
  };
  const { error: nameError } = await supabase.from("work_pipelines").update({ name: w.name.trim() }).eq("id", w.id);
  if (nameError) return fail(nameError.message);
  if (w.removed.length) {
    const { error } = await supabase.from("work_pipeline_stages").delete().in("id", w.removed);
    if (error) return fail(error.message);
    w.removed = [];
  }
  for (const [index, s] of w.stages.entries()) {
    const payload = { work_pipeline_id: w.id, name: s.name.trim(), sort_order: index + 1 };
    const { data, error } = s.id
      ? await supabase.from("work_pipeline_stages").update(payload).eq("id", s.id).select("id").single()
      : await supabase.from("work_pipeline_stages").insert(payload).select("id").single();
    if (error || !data) return fail(error?.message ?? "");
    s.id = data.id;
  }
  w.saving = false;
  toast.add({ title: t("admin.workPipelines.saved"), color: "success" });
}

const deleteTarget = ref<Workflow | null>(null);
const deleteOpen = computed({ get: () => !!deleteTarget.value, set: (v) => { if (!v) deleteTarget.value = null; } });
const deleting = ref(false);
function askDelete(w: Workflow) {
  deleteTarget.value = w;
}
async function confirmDelete() {
  if (!deleteTarget.value) return;
  deleting.value = true;
  const { error } = await supabase.from("work_pipelines").delete().eq("id", deleteTarget.value.id);
  deleting.value = false;
  if (error) {
    toast.add({ title: t("admin.workPipelines.saveFailed"), description: error.message, color: "error" });
    return;
  }
  deleteTarget.value = null;
  await load();
}
</script>

<template>
  <UDashboardPanel :ui="{ body: 'kords-canvas' }">
    <template #header>
      <UDashboardNavbar :title="t('admin.workPipelines.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton icon="i-lucide-plus" :label="t('admin.workPipelines.new')" @click="createWorkflow" />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <div class="mx-auto w-full max-w-3xl space-y-4">
        <p class="text-sm text-muted">{{ t("admin.workPipelines.subtitle") }}</p>
        <p v-if="!loading && !workflows.length" class="kords-card p-10 text-center text-sm text-muted">{{ t("admin.workPipelines.empty") }}</p>

        <section v-for="w in workflows" :key="w.id" class="kords-card space-y-4 p-4">
          <div class="flex flex-wrap items-end gap-2">
            <UFormField :label="t('admin.workPipelines.name')" class="min-w-48 flex-1">
              <UInput v-model="w.name" class="w-full" />
            </UFormField>
            <UButton color="error" variant="ghost" icon="i-lucide-trash-2" :label="t('admin.workPipelines.delete')" @click="askDelete(w)" />
          </div>

          <div class="space-y-2">
            <p class="text-sm font-medium text-highlighted">{{ t("admin.workPipelines.stages") }}</p>
            <div v-for="(s, i) in w.stages" :key="s._key" class="flex items-center gap-2">
              <div class="flex">
                <UButton icon="i-lucide-chevron-up" color="neutral" variant="ghost" size="xs" :disabled="i === 0" @click="moveStage(w, i, -1)" />
                <UButton icon="i-lucide-chevron-down" color="neutral" variant="ghost" size="xs" :disabled="i === w.stages.length - 1" @click="moveStage(w, i, 1)" />
              </div>
              <UInput v-model="s.name" :placeholder="t('admin.workPipelines.stageName')" class="flex-1" />
              <UButton icon="i-lucide-trash" color="error" variant="ghost" size="sm" @click="removeStage(w, i)" />
            </div>
            <UButton icon="i-lucide-plus" color="neutral" variant="outline" size="sm" :label="t('admin.workPipelines.addStage')" @click="addStage(w)" />
          </div>

          <UButton :label="t('admin.workPipelines.save')" :loading="w.saving" :disabled="!w.name.trim() || !w.stages.length || w.stages.some((s) => !s.name.trim())" @click="save(w)" />
        </section>
      </div>
    </template>
  </UDashboardPanel>

  <KDeleteConfirmation
    v-model:open="deleteOpen"
    :title="t('admin.workPipelines.delete')"
    :message="t('admin.workPipelines.deleteBody', { name: deleteTarget?.name ?? '' })"
    :loading="deleting"
    @confirm="confirmDelete"
  />
</template>
