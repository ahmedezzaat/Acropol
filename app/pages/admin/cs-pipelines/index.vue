<script setup lang="ts">
definePageMeta({ layout: "dashboard" });

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();
const { loadPipelines } = useCs();

interface PipelineRow {
  id: string;
  name: string;
  sort_order: number;
  stageCount: number;
}

const { data: pipelines, refresh, status } = await useAsyncData<PipelineRow[]>("admin-cs-pipelines", async () => {
  const [{ data: pips, error }, { data: stg }] = await Promise.all([
    supabase.from("cs_pipelines").select("id, name, sort_order").order("sort_order"),
    supabase.from("cs_pipeline_stages").select("pipeline_id"),
  ]);
  if (error) throw error;
  return (pips ?? []).map((p) => ({ ...p, stageCount: (stg ?? []).filter((s) => s.pipeline_id === p.id).length }));
});

const createOpen = ref(false);
const creating = ref(false);
const newName = ref("");

function openCreate() {
  newName.value = "";
  createOpen.value = true;
}

async function create() {
  if (!newName.value.trim()) return;
  creating.value = true;
  const { data, error } = await supabase
    .from("cs_pipelines")
    .insert({ name: newName.value.trim(), sort_order: (pipelines.value?.length ?? 0) + 1 })
    .select("id")
    .single();
  creating.value = false;

  if (error || !data) {
    toast.add({ title: t("admin.csPipelines.createFailed"), description: error?.message, color: "error" });
    return;
  }
  createOpen.value = false;
  await loadPipelines(true);
  // Start the new funnel with one stage so it is usable right away.
  await supabase.from("cs_pipeline_stages").insert({ pipeline_id: data.id, name: t("admin.csPipelines.firstStageDefault"), sort_order: 1 });
  await navigateTo(`/admin/cs-pipelines/${data.id}`);
}

function openPipeline(id: string) {
  navigateTo(`/admin/cs-pipelines/${id}`);
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="t('admin.csPipelines.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton icon="i-lucide-plus" :label="t('admin.csPipelines.newPipeline')" @click="openCreate" />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>
      <div v-else class="max-w-2xl space-y-3">
        <p class="text-sm text-muted">{{ t("admin.csPipelines.description") }}</p>
        <button
          v-for="p in pipelines"
          :key="p.id"
          type="button"
          class="flex w-full items-center justify-between gap-2 border border-default p-4 text-start transition-colors hover:border-primary hover:bg-elevated"
          @click="openPipeline(p.id)"
        >
          <span class="font-medium text-highlighted">{{ p.name }}</span>
          <UBadge :label="t('admin.csPipelines.stagesCount', { count: p.stageCount })" color="neutral" variant="subtle" class="cds-tag" />
        </button>
      </div>
    </template>
  </UDashboardPanel>

  <UModal v-model:open="createOpen" :title="t('admin.csPipelines.newPipeline')">
    <template #body>
      <div class="space-y-4">
        <UFormField :label="t('admin.csPipelines.name')">
          <UInput v-model="newName" class="w-full" @keydown.enter="create" />
        </UFormField>
        <UButton :label="t('common.create')" :loading="creating" :disabled="!newName.trim()" block @click="create" />
      </div>
    </template>
  </UModal>
</template>
