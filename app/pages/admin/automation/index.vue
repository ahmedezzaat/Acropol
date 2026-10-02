<script setup lang="ts">
definePageMeta({ layout: "dashboard" });

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

type NoteCondition = "any" | "no_note" | "has_note";

interface RuleRow {
  _key: string;
  id: string | null;
  name: string;
  pipeline_id: string | null;
  stage_id: string | null;
  after_hours: number | null;
  note_condition: NoteCondition;
  is_active: boolean;
}

interface StageInfo {
  id: string;
  name: string;
  pipeline_id: string;
  is_closed: boolean;
  max_stay_days: number | null;
  max_stay_hours: number | null;
}

const rules = ref<RuleRow[]>([]);
const removedIds = ref<string[]>([]);
const saving = ref(false);
const running = ref(false);

function newKey() {
  return crypto.randomUUID();
}

const { data: payload, status } = await useAsyncData("admin-automation-rules", async () => {
  const [pipelines, stages, ruleRows] = await Promise.all([
    supabase.from("pipelines").select("id, name").order("sort_order"),
    supabase
      .from("pipeline_stages")
      .select("id, name, pipeline_id, is_closed, max_stay_days, max_stay_hours")
      .order("sort_order"),
    supabase.from("automation_rules").select("*").order("created_at"),
  ]);
  if (pipelines.error) throw pipelines.error;
  if (stages.error) throw stages.error;
  if (ruleRows.error) throw ruleRows.error;
  return { pipelines: pipelines.data ?? [], stages: (stages.data ?? []) as StageInfo[], rules: ruleRows.data ?? [] };
});

const pipelines = computed(() => payload.value?.pipelines ?? []);
const stages = computed(() => payload.value?.stages ?? []);

// See crm/leads/[id].vue for why this goes through useAsyncData's own `data`
// (via watchEffect) instead of only mutating `rules` inside the handler.
watchEffect(() => {
  if (!payload.value) return;
  rules.value = payload.value.rules.map((r) => ({
    _key: newKey(),
    id: r.id,
    name: r.name,
    pipeline_id: payload.value!.stages.find((s) => s.id === r.stage_id)?.pipeline_id ?? null,
    stage_id: r.stage_id,
    after_hours: r.after_hours,
    note_condition: r.note_condition,
    is_active: r.is_active,
  }));
});

const pipelineItems = computed(() => pipelines.value.map((p) => ({ label: p.name, value: p.id })));

// Only open stages are offered: a closed stage (won / competitor / archive)
// has nobody working it, so "unassign" there would be meaningless.
function stageItems(pipelineId: string | null) {
  return stages.value
    .filter((s) => s.pipeline_id === pipelineId && !s.is_closed)
    .map((s) => ({ label: s.name, value: s.id }));
}

function stageById(id: string | null) {
  return stages.value.find((s) => s.id === id);
}

function pipelineName(id: string | null) {
  return pipelines.value.find((p) => p.id === id)?.name ?? "";
}

function onPipelineChange(row: RuleRow) {
  row.stage_id = null;
}

function stayLimitHours(stageId: string | null): number | null {
  const s = stageById(stageId);
  if (!s) return null;
  const total = (s.max_stay_days ?? 0) * 24 + (s.max_stay_hours ?? 0);
  return total > 0 ? total : null;
}

function humanDuration(hours: number | null) {
  if (!hours || hours < 1) return "";
  const days = Math.floor(hours / 24);
  const rest = hours % 24;
  const parts: string[] = [];
  if (days) parts.push(`${days} ${t("admin.automation.daysShort")}`);
  if (rest) parts.push(`${rest} ${t("admin.automation.hoursShort")}`);
  return parts.join(" ");
}

const conditionItems = computed(() =>
  (["any", "no_note", "has_note"] as const).map((c) => ({ label: t(`admin.automation.conditions.${c}`), value: c })),
);

function ruleSummary(row: RuleRow) {
  const params = {
    pipeline: pipelineName(row.pipeline_id) || "…",
    stage: stageById(row.stage_id)?.name ?? "…",
    duration: humanDuration(row.after_hours) || "…",
  };
  return row.note_condition === "any"
    ? t("admin.automation.summary", params)
    : t("admin.automation.summaryWithNote", {
        ...params,
        note: t(`admin.automation.noteClause.${row.note_condition}`),
      });
}

function ruleLabel(row: RuleRow) {
  return row.name.trim() || t("admin.automation.unnamedRule");
}

// ---- Conflict detection -------------------------------------------------
// "error" blocks saving (it would make rules contradict each other or can't
// be stored); "warning" is allowed but called out.
interface Finding {
  level: "error" | "warning";
  keys: string[];
  message: string;
}

const findings = computed<Finding[]>(() => {
  const out: Finding[] = [];

  for (const row of rules.value) {
    if (!row.stage_id || !row.after_hours || row.after_hours < 1) {
      out.push({
        level: "error",
        keys: [row._key],
        message: t("admin.automation.conflicts.incomplete", { rule: ruleLabel(row) }),
      });
    }
  }

  // Rule A *covers* rule B when every deal matching B also matches A (A has
  // no note condition, or both share one). If A covers B and A's time is not
  // later than B's, A always acts first and B can never run. A more specific
  // rule with an EARLIER time (e.g. any @48h + "no note" @24h) is fine.
  const covers = (a: RuleRow, b: RuleRow) => a.note_condition === "any" || a.note_condition === b.note_condition;
  const active = rules.value.filter((r) => r.is_active && r.stage_id);
  const seen = new Set<string>();
  for (const a of active) {
    for (const b of active) {
      if (a === b || a.stage_id !== b.stage_id) continue;
      const aHours = a.after_hours ?? 0;
      const bHours = b.after_hours ?? 0;
      if (!covers(a, b) || aHours > bHours) continue;
      // Identical rules cover each other — report the pair once, blaming the later one.
      if (covers(b, a) && bHours === aHours && seen.has(`${b._key}|${a._key}`)) continue;
      seen.add(`${a._key}|${b._key}`);
      out.push({
        level: "error",
        keys: [a._key, b._key],
        message: t("admin.automation.conflicts.unreachable", {
          blocked: ruleLabel(b),
          by: ruleLabel(a),
          hours: aHours,
        }),
      });
    }
  }

  // The stage's own stay limit drives the red overdue alert. A rule that
  // fires before that limit removes the deal from the rep first, so the
  // alert would never show.
  for (const r of active) {
    const limit = stayLimitHours(r.stage_id);
    if (limit !== null && r.after_hours && r.after_hours < limit) {
      out.push({
        level: "warning",
        keys: [r._key],
        message: t("admin.automation.conflicts.beforeLimit", {
          rule: ruleLabel(r),
          hours: r.after_hours,
          limit,
          stage: stageById(r.stage_id)?.name ?? "",
        }),
      });
    }
  }

  return out;
});

const errors = computed(() => findings.value.filter((f) => f.level === "error"));
const warnings = computed(() => findings.value.filter((f) => f.level === "warning"));

function rowFinding(row: RuleRow) {
  const hit = findings.value.filter((f) => f.keys.includes(row._key));
  if (hit.some((f) => f.level === "error")) return "error";
  if (hit.length) return "warning";
  return null;
}

function addRule() {
  const firstPipeline = pipelines.value[0]?.id ?? null;
  rules.value.push({
    _key: newKey(),
    id: null,
    name: t("admin.automation.newRuleDefault"),
    pipeline_id: firstPipeline,
    stage_id: null,
    after_hours: 24,
    note_condition: "any",
    is_active: true,
  });
}

function removeRule(index: number) {
  const row = rules.value[index];
  if (!row) return;
  if (row.id) removedIds.value.push(row.id);
  rules.value.splice(index, 1);
}

async function save() {
  if (errors.value.length) return;
  saving.value = true;

  if (removedIds.value.length > 0) {
    const { error } = await supabase.from("automation_rules").delete().in("id", removedIds.value);
    if (error) {
      saving.value = false;
      toast.add({ title: t("admin.automation.saveFailed"), description: error.message, color: "error" });
      return;
    }
    removedIds.value = [];
  }

  // Deactivated rules first, so re-pointing an active rule at a stage another
  // rule is leaving can't trip the one-active-rule-per-stage index mid-save.
  const ordered = [...rules.value].sort((a, b) => Number(a.is_active) - Number(b.is_active));
  for (const row of ordered) {
    const body = {
      name: row.name.trim(),
      stage_id: row.stage_id!,
      after_hours: row.after_hours!,
      note_condition: row.note_condition,
      is_active: row.is_active,
    };
    const { data, error } = row.id
      ? await supabase.from("automation_rules").update(body).eq("id", row.id).select().single()
      : await supabase.from("automation_rules").insert(body).select().single();
    if (error) {
      saving.value = false;
      toast.add({ title: t("admin.automation.saveFailed"), description: error.message, color: "error" });
      return;
    }
    row.id = data.id;
  }

  saving.value = false;
  toast.add({ title: t("admin.automation.saved"), color: "success" });
}

async function runNow() {
  running.value = true;
  const { data, error } = await supabase.rpc("run_automation_rules");
  running.value = false;
  if (error) {
    toast.add({ title: t("admin.automation.runFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("admin.automation.runResult", { count: data ?? 0 }), color: "success" });
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="t('admin.automation.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>

      <div v-else class="max-w-3xl space-y-4">
        <UPageCard :description="t('admin.automation.description')">
          <div class="space-y-3">
            <UAlert
              v-if="errors.length"
              color="error"
              variant="subtle"
              icon="i-lucide-octagon-alert"
              :title="t('admin.automation.conflictsTitle')"
            >
              <template #description>
                <ul class="list-disc space-y-1 ps-4">
                  <li v-for="(f, i) in errors" :key="i">{{ f.message }}</li>
                </ul>
              </template>
            </UAlert>
            <UAlert
              v-if="warnings.length"
              color="warning"
              variant="subtle"
              icon="i-lucide-triangle-alert"
              :title="t('admin.automation.warningsTitle')"
            >
              <template #description>
                <ul class="list-disc space-y-1 ps-4">
                  <li v-for="(f, i) in warnings" :key="i">{{ f.message }}</li>
                </ul>
              </template>
            </UAlert>

            <p v-if="!rules.length" class="py-6 text-center text-sm text-muted">
              {{ t("admin.automation.noRules") }}
            </p>

            <div
              v-for="(row, index) in rules"
              :key="row._key"
              class="space-y-3 rounded-lg border p-4"
              :class="[
                rowFinding(row) === 'error'
                  ? 'border-error'
                  : rowFinding(row) === 'warning'
                    ? 'border-warning'
                    : 'border-default',
                !row.is_active && 'opacity-60',
              ]"
            >
              <div class="flex items-center gap-2">
                <UInput v-model="row.name" :placeholder="t('admin.automation.ruleName')" class="flex-1" />
                <USwitch v-model="row.is_active" :label="t('admin.automation.active')" />
                <UButton
                  icon="i-lucide-trash"
                  color="error"
                  variant="ghost"
                  size="sm"
                  :aria-label="t('common.delete')"
                  @click="removeRule(index)"
                />
              </div>

              <div class="grid gap-3 sm:grid-cols-[1fr_1fr_8rem]">
                <UFormField :label="t('admin.automation.when.pipeline')">
                  <USelect
                    v-model="row.pipeline_id"
                    :items="pipelineItems"
                    value-key="value"
                    class="w-full"
                    @update:model-value="onPipelineChange(row)"
                  />
                </UFormField>
                <UFormField :label="t('admin.automation.when.stage')">
                  <USelect
                    v-model="row.stage_id"
                    :items="stageItems(row.pipeline_id)"
                    value-key="value"
                    :placeholder="t('admin.automation.when.pickStage')"
                    class="w-full"
                  />
                </UFormField>
                <UFormField :label="t('admin.automation.when.afterHours')">
                  <UInputNumber v-model="row.after_hours" :min="1" class="w-full" />
                </UFormField>
              </div>

              <UFormField :label="t('admin.automation.noteCondition')">
                <USelect v-model="row.note_condition" :items="conditionItems" value-key="value" class="w-full" />
              </UFormField>

              <div class="flex flex-wrap items-center gap-2 text-sm text-muted">
                <UIcon name="i-lucide-zap" class="size-4 text-primary" />
                <span>
                  {{ ruleSummary(row) }}
                </span>
                <UBadge color="neutral" variant="subtle" class="cds-tag" :label="t('admin.automation.actionUnassign')" />
              </div>
            </div>

            <div class="flex flex-wrap items-center gap-2">
              <UButton icon="i-lucide-plus" :label="t('admin.automation.addRule')" variant="soft" @click="addRule" />
              <UButton
                :label="t('common.save')"
                :loading="saving"
                :disabled="errors.length > 0"
                @click="save"
              />
              <UButton
                icon="i-lucide-play"
                :label="t('admin.automation.runNow')"
                color="neutral"
                variant="outline"
                :loading="running"
                @click="runNow"
              />
            </div>
          </div>
        </UPageCard>

        <UAlert color="neutral" variant="subtle" icon="i-lucide-info" :description="t('admin.automation.howItWorks')" />
      </div>
    </template>
  </UDashboardPanel>
</template>
