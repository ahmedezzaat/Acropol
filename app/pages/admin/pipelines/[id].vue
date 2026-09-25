<script setup lang="ts">
definePageMeta({ layout: "dashboard" });

const route = useRoute();
const pipelineId = route.params.id as string;
const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

interface StageRow {
  _key: string;
  id: string | null;
  name: string;
  is_closed: boolean;
  reason_category: "archive" | "competitor" | null;
}

interface ReasonRow {
  _key: string;
  id: string | null;
  name: string;
}

const name = ref("");
const saving = ref(false);
const savingStages = ref(false);
const savingReasons = ref(false);
const deleting = ref(false);

const stages = ref<StageRow[]>([]);
const removedStageIds = ref<string[]>([]);

const archiveReasons = ref<ReasonRow[]>([]);
const competitorReasons = ref<ReasonRow[]>([]);
const removedReasonIds = ref<string[]>([]);

function newKey() {
  return crypto.randomUUID();
}

const reasonCategoryOptions = computed(() => [
  { label: t("admin.pipelines.reasonCategoryNone"), value: null },
  { label: t("admin.pipelines.reasonCategoryArchive"), value: "archive" },
  { label: t("admin.pipelines.reasonCategoryCompetitor"), value: "competitor" },
]);

// See crm/leads/[id].vue for why this goes through useAsyncData's own
// `data` (via watchEffect) instead of only mutating the local refs inside
// the handler.
const { data: pipelinePayload, status } = await useAsyncData(`admin-pipeline-${pipelineId}`, async () => {
  const [{ data: pipeline, error: pipelineError }, { data: stageRows, error: stagesError }, { data: reasonRows, error: reasonsError }] =
    await Promise.all([
      supabase.from("pipelines").select("*").eq("id", pipelineId).single(),
      supabase.from("pipeline_stages").select("*").eq("pipeline_id", pipelineId).order("sort_order"),
      supabase.from("pipeline_stage_reasons").select("*").eq("pipeline_id", pipelineId).order("sort_order"),
    ]);

  if (pipelineError) throw pipelineError;
  if (stagesError) throw stagesError;
  if (reasonsError) throw reasonsError;

  return { pipeline, stageRows: stageRows ?? [], reasonRows: reasonRows ?? [] };
});
watchEffect(() => {
  if (!pipelinePayload.value) return;
  const { pipeline, stageRows, reasonRows } = pipelinePayload.value;
  name.value = pipeline.name;
  stages.value = stageRows.map((s) => ({
    _key: newKey(),
    id: s.id,
    name: s.name,
    is_closed: s.is_closed,
    reason_category: s.reason_category,
  }));
  archiveReasons.value = reasonRows
    .filter((r) => r.category === "archive")
    .map((r) => ({ _key: newKey(), id: r.id, name: r.name }));
  competitorReasons.value = reasonRows
    .filter((r) => r.category === "competitor")
    .map((r) => ({ _key: newKey(), id: r.id, name: r.name }));
});

async function saveDetails() {
  saving.value = true;
  const { error } = await supabase.from("pipelines").update({ name: name.value }).eq("id", pipelineId);
  saving.value = false;

  if (error) {
    toast.add({ title: t("admin.pipelines.saveFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("admin.pipelines.pipelineSaved"), color: "success" });
}

function addStage() {
  stages.value.push({
    _key: newKey(),
    id: null,
    name: t("admin.pipelines.newStageDefault"),
    is_closed: false,
    reason_category: null,
  });
}

function removeStage(index: number) {
  const stage = stages.value[index];
  if (stage.id) removedStageIds.value.push(stage.id);
  stages.value.splice(index, 1);
}

function moveStage(index: number, direction: -1 | 1) {
  const target = index + direction;
  if (target < 0 || target >= stages.value.length) return;
  const [moved] = stages.value.splice(index, 1);
  stages.value.splice(target, 0, moved);
}

async function saveStages() {
  savingStages.value = true;

  if (removedStageIds.value.length > 0) {
    const { error } = await supabase.from("pipeline_stages").delete().in("id", removedStageIds.value);
    if (error) {
      savingStages.value = false;
      toast.add({ title: t("admin.pipelines.saveStagesFailed"), description: error.message, color: "error" });
      return;
    }
    removedStageIds.value = [];
  }

  for (const [index, stage] of stages.value.entries()) {
    const payload = {
      pipeline_id: pipelineId,
      name: stage.name,
      sort_order: index + 1,
      is_closed: stage.is_closed,
      reason_category: stage.reason_category,
    };

    const { data, error } = stage.id
      ? await supabase.from("pipeline_stages").update(payload).eq("id", stage.id).select().single()
      : await supabase.from("pipeline_stages").insert(payload).select().single();

    if (error) {
      savingStages.value = false;
      toast.add({ title: t("admin.pipelines.saveStagesFailed"), description: error.message, color: "error" });
      return;
    }
    stage.id = data.id;
  }

  savingStages.value = false;
  toast.add({ title: t("admin.pipelines.stagesSaved"), color: "success" });
}

function addReason(category: "archive" | "competitor") {
  const list = category === "archive" ? archiveReasons : competitorReasons;
  list.value.push({ _key: newKey(), id: null, name: t("admin.pipelines.newReasonDefault") });
}

function removeReason(category: "archive" | "competitor", index: number) {
  const list = category === "archive" ? archiveReasons : competitorReasons;
  const reason = list.value[index];
  if (reason.id) removedReasonIds.value.push(reason.id);
  list.value.splice(index, 1);
}

async function saveReasons() {
  savingReasons.value = true;

  if (removedReasonIds.value.length > 0) {
    const { error } = await supabase.from("pipeline_stage_reasons").delete().in("id", removedReasonIds.value);
    if (error) {
      savingReasons.value = false;
      toast.add({ title: t("admin.pipelines.saveReasonsFailed"), description: error.message, color: "error" });
      return;
    }
    removedReasonIds.value = [];
  }

  for (const [category, list] of [["archive", archiveReasons], ["competitor", competitorReasons]] as const) {
    for (const [index, reason] of list.value.entries()) {
      const payload = { pipeline_id: pipelineId, category, name: reason.name, sort_order: index + 1 };
      const { data, error } = reason.id
        ? await supabase.from("pipeline_stage_reasons").update(payload).eq("id", reason.id).select().single()
        : await supabase.from("pipeline_stage_reasons").insert(payload).select().single();

      if (error) {
        savingReasons.value = false;
        toast.add({ title: t("admin.pipelines.saveReasonsFailed"), description: error.message, color: "error" });
        return;
      }
      reason.id = data.id;
    }
  }

  savingReasons.value = false;
  toast.add({ title: t("admin.pipelines.reasonsSaved"), color: "success" });
}

async function deletePipeline() {
  deleting.value = true;
  const { error } = await supabase.from("pipelines").delete().eq("id", pipelineId);
  deleting.value = false;

  if (error) {
    toast.add({ title: t("admin.pipelines.deletePipelineFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("admin.pipelines.pipelineDeleted"), color: "success" });
  navigateTo("/admin/pipelines");
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="name || t('admin.pipelines.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton
            icon="i-lucide-trash"
            :label="t('admin.pipelines.deletePipeline')"
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
        <UPageCard :title="t('admin.pipelines.detailsTitle')">
          <div class="space-y-4">
            <UFormField :label="t('admin.pipelines.name')">
              <UInput v-model="name" class="w-full" />
            </UFormField>
            <UButton :label="t('admin.pipelines.saveDetails')" :loading="saving" @click="saveDetails" />
          </div>
        </UPageCard>

        <UPageCard :title="t('admin.pipelines.stagesTitle')" :description="t('admin.pipelines.stagesDescription')">
          <div class="space-y-3">
            <div
              v-for="(stage, index) in stages"
              :key="stage._key"
              class="flex flex-wrap items-center gap-2 rounded-lg border border-default p-3"
            >
              <div class="flex flex-col">
                <UButton
                  icon="i-lucide-chevron-up"
                  color="neutral"
                  variant="ghost"
                  size="xs"
                  :disabled="index === 0"
                  @click="moveStage(index, -1)"
                />
                <UButton
                  icon="i-lucide-chevron-down"
                  color="neutral"
                  variant="ghost"
                  size="xs"
                  :disabled="index === stages.length - 1"
                  @click="moveStage(index, 1)"
                />
              </div>
              <UInput v-model="stage.name" :placeholder="t('admin.pipelines.stageName')" class="min-w-40 flex-1" />
              <UCheckbox v-model="stage.is_closed" :label="t('admin.pipelines.closed')" />
              <USelect
                v-model="stage.reason_category"
                :items="reasonCategoryOptions"
                value-key="value"
                :placeholder="t('admin.pipelines.reasonCategory')"
                class="w-56"
              />
              <UButton
                icon="i-lucide-trash"
                color="error"
                variant="ghost"
                size="sm"
                @click="removeStage(index)"
              />
            </div>

            <UButton icon="i-lucide-plus" :label="t('admin.pipelines.addStage')" variant="soft" @click="addStage" />
            <div>
              <UButton :label="t('common.save')" :loading="savingStages" @click="saveStages" />
            </div>
          </div>
        </UPageCard>

        <UPageCard :title="t('admin.pipelines.reasonsTitle')" :description="t('admin.pipelines.reasonsDescription')">
          <div class="grid gap-6 sm:grid-cols-2">
            <div>
              <h3 class="mb-2 font-medium text-highlighted">{{ t("admin.pipelines.archiveReasons") }}</h3>
              <div class="space-y-2">
                <div v-for="(reason, index) in archiveReasons" :key="reason._key" class="flex items-center gap-2">
                  <UInput v-model="reason.name" class="flex-1" />
                  <UButton icon="i-lucide-trash" color="error" variant="ghost" size="sm" @click="removeReason('archive', index)" />
                </div>
                <UButton icon="i-lucide-plus" :label="t('admin.pipelines.addReason')" variant="soft" size="sm" @click="addReason('archive')" />
              </div>
            </div>
            <div>
              <h3 class="mb-2 font-medium text-highlighted">{{ t("admin.pipelines.competitorReasons") }}</h3>
              <div class="space-y-2">
                <div v-for="(reason, index) in competitorReasons" :key="reason._key" class="flex items-center gap-2">
                  <UInput v-model="reason.name" class="flex-1" />
                  <UButton icon="i-lucide-trash" color="error" variant="ghost" size="sm" @click="removeReason('competitor', index)" />
                </div>
                <UButton icon="i-lucide-plus" :label="t('admin.pipelines.addReason')" variant="soft" size="sm" @click="addReason('competitor')" />
              </div>
            </div>
          </div>
          <div class="mt-4">
            <UButton :label="t('common.save')" :loading="savingReasons" @click="saveReasons" />
          </div>
        </UPageCard>
      </div>
    </template>
  </UDashboardPanel>
</template>
