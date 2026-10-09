<script setup lang="ts">
definePageMeta({ layout: "dashboard" });

const route = useRoute();
const pipelineId = route.params.id as string;
const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();
const { loadPipelines } = useCs();

interface StageRow {
  _key: string;
  id: string | null;
  name: string;
  is_final: boolean;
  require_date: boolean;
  max_stay_days: number | null;
  max_stay_hours: number | null;
  inUse: number;
}

const name = ref("");
const stages = ref<StageRow[]>([]);
const removedStageIds = ref<string[]>([]);
const savingName = ref(false);
const savingStages = ref(false);
const deleting = ref(false);

function newKey() {
  return crypto.randomUUID();
}

// See crm/leads/[id].vue for why this goes through useAsyncData's own `data`
// (via watchEffect) instead of only mutating the local refs inside the handler.
const { data: payload, status } = await useAsyncData(`admin-cs-pipeline-${pipelineId}`, async () => {
  const [pipeline, stageRows, products] = await Promise.all([
    supabase.from("cs_pipelines").select("*").eq("id", pipelineId).single(),
    supabase
      .from("cs_pipeline_stages")
      .select("id, name, is_final, require_date, max_stay_days, max_stay_hours")
      .eq("pipeline_id", pipelineId)
      .order("sort_order"),
    supabase.from("customer_products").select("stage_id").eq("pipeline_id", pipelineId),
  ]);
  if (pipeline.error) throw pipeline.error;
  if (stageRows.error) throw stageRows.error;
  const counts = new Map<string, number>();
  for (const p of products.data ?? []) counts.set(p.stage_id, (counts.get(p.stage_id) ?? 0) + 1);
  return { pipeline: pipeline.data, stageRows: stageRows.data ?? [], counts, productCount: products.data?.length ?? 0 };
});
watchEffect(() => {
  if (!payload.value) return;
  name.value = payload.value.pipeline.name;
  stages.value = payload.value.stageRows.map((s) => ({
    _key: newKey(),
    id: s.id,
    name: s.name,
    is_final: s.is_final,
    require_date: s.require_date,
    max_stay_days: s.max_stay_days,
    max_stay_hours: s.max_stay_hours,
    inUse: payload.value!.counts.get(s.id) ?? 0,
  }));
});

async function saveName() {
  if (!name.value.trim()) return;
  savingName.value = true;
  const { error } = await supabase.from("cs_pipelines").update({ name: name.value.trim() }).eq("id", pipelineId);
  savingName.value = false;
  if (error) {
    toast.add({ title: t("admin.csPipelines.saveFailed"), description: error.message, color: "error" });
    return;
  }
  await loadPipelines(true);
  toast.add({ title: t("admin.csPipelines.saved"), color: "success" });
}

function addStage() {
  stages.value.push({
    _key: newKey(),
    id: null,
    name: t("admin.csPipelines.newStageDefault"),
    is_final: false,
    require_date: false,
    max_stay_days: null,
    max_stay_hours: null,
    inUse: 0,
  });
}

function removeStage(index: number) {
  const stage = stages.value[index];
  if (!stage) return;
  // A stage that products currently sit in can't be deleted: it can be
  // renamed, or the products moved on first.
  if (stage.inUse > 0) {
    toast.add({
      title: t("admin.csPipelines.inUseTitle"),
      description: t("admin.csPipelines.inUseHint", { count: stage.inUse }),
      color: "warning",
    });
    return;
  }
  if (stage.id) removedStageIds.value.push(stage.id);
  stages.value.splice(index, 1);
}

function moveStage(index: number, direction: -1 | 1) {
  const target = index + direction;
  if (target < 0 || target >= stages.value.length) return;
  const [moved] = stages.value.splice(index, 1);
  if (moved) stages.value.splice(target, 0, moved);
}

const stagesValid = computed(() => stages.value.length > 0 && stages.value.every((s) => s.name.trim().length > 0));

async function saveStages() {
  if (!stagesValid.value) return;
  savingStages.value = true;

  if (removedStageIds.value.length) {
    const { error } = await supabase.from("cs_pipeline_stages").delete().in("id", removedStageIds.value);
    if (error) return fail(error.message);
    removedStageIds.value = [];
  }

  for (const [index, stage] of stages.value.entries()) {
    const body = {
      pipeline_id: pipelineId,
      name: stage.name.trim(),
      sort_order: index + 1,
      is_final: stage.is_final,
      require_date: stage.require_date,
      max_stay_days: stage.max_stay_days,
      max_stay_hours: stage.max_stay_hours,
    };
    const { data, error } = stage.id
      ? await supabase.from("cs_pipeline_stages").update(body).eq("id", stage.id).select().single()
      : await supabase.from("cs_pipeline_stages").insert(body).select().single();
    if (error) return fail(error.message);
    stage.id = data.id;
  }

  savingStages.value = false;
  await loadPipelines(true);
  toast.add({ title: t("admin.csPipelines.saved"), color: "success" });
}

function fail(message?: string) {
  savingStages.value = false;
  toast.add({ title: t("admin.csPipelines.saveFailed"), description: message, color: "error" });
}

async function deletePipeline() {
  if ((payload.value?.productCount ?? 0) > 0) {
    toast.add({
      title: t("admin.csPipelines.inUseTitle"),
      description: t("admin.csPipelines.pipelineInUse", { count: payload.value?.productCount ?? 0 }),
      color: "warning",
    });
    return;
  }
  deleting.value = true;
  const { error } = await supabase.from("cs_pipelines").delete().eq("id", pipelineId);
  deleting.value = false;
  if (error) {
    toast.add({ title: t("admin.csPipelines.saveFailed"), description: error.message, color: "error" });
    return;
  }
  await loadPipelines(true);
  await navigateTo("/admin/cs-pipelines");
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="name || t('admin.csPipelines.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton
            icon="i-lucide-trash"
            :label="t('admin.csPipelines.deletePipeline')"
            color="error"
            variant="soft"
            :loading="deleting"
            @click="deletePipeline"
          />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>

      <div v-else class="max-w-3xl space-y-8">
        <UPageCard :title="t('admin.csPipelines.detailsTitle')">
          <div class="space-y-4">
            <UFormField :label="t('admin.csPipelines.name')">
              <UInput v-model="name" class="w-full" />
            </UFormField>
            <UButton :label="t('common.save')" :loading="savingName" :disabled="!name.trim()" @click="saveName" />
          </div>
        </UPageCard>

        <UPageCard :title="t('admin.csPipelines.stagesTitle')" :description="t('admin.csPipelines.stagesDescription')">
          <div class="space-y-3">
            <div v-for="(stage, index) in stages" :key="stage._key" class="space-y-2 border border-default p-3">
              <div class="flex items-center gap-2">
                <div class="flex flex-col">
                  <UButton icon="i-lucide-chevron-up" color="neutral" variant="ghost" size="xs" :disabled="index === 0" @click="moveStage(index, -1)" />
                  <UButton
                    icon="i-lucide-chevron-down"
                    color="neutral"
                    variant="ghost"
                    size="xs"
                    :disabled="index === stages.length - 1"
                    @click="moveStage(index, 1)"
                  />
                </div>
                <UInput v-model="stage.name" :placeholder="t('admin.csPipelines.stageName')" class="min-w-40 flex-1" />
                <UButton icon="i-lucide-trash" color="error" variant="ghost" size="sm" :aria-label="t('common.delete')" @click="removeStage(index)" />
              </div>
              <div class="flex flex-wrap items-center gap-x-4 gap-y-2 ps-9">
                <UCheckbox v-model="stage.is_final" :label="t('admin.csPipelines.final')" />
                <UCheckbox v-model="stage.require_date" :label="t('admin.csPipelines.requireDate')" />
                <div class="flex items-center gap-1">
                  <UInputNumber v-model="stage.max_stay_days" :min="0" :placeholder="t('admin.csPipelines.days')" class="w-24" />
                  <span class="text-xs text-muted">{{ t("admin.csPipelines.days") }}</span>
                  <UInputNumber v-model="stage.max_stay_hours" :min="0" :max="23" :placeholder="t('admin.csPipelines.hours')" class="w-24" />
                  <span class="text-xs text-muted">{{ t("admin.csPipelines.hours") }}</span>
                </div>
                <span v-if="stage.inUse > 0" class="text-xs text-muted">{{ t("admin.csPipelines.inUseCount", { count: stage.inUse }) }}</span>
              </div>
            </div>

            <UButton icon="i-lucide-plus" :label="t('admin.csPipelines.addStage')" variant="soft" @click="addStage" />
            <div>
              <UButton :label="t('common.save')" :loading="savingStages" :disabled="!stagesValid" @click="saveStages" />
            </div>
          </div>
        </UPageCard>
      </div>
    </template>
  </UDashboardPanel>
</template>
