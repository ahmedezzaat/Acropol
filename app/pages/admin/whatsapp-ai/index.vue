<script setup lang="ts">
// Settings -> WhatsApp assistant: turn the assistant on, say what the company does, choose what must be
// known before a chat becomes a contact, and set the safety limits.
definePageMeta({ layout: "dashboard" });

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

interface Settings {
  enabled: boolean; model: string; business_description: string; qualify_need: boolean; qualify_area: boolean; qualify_timing: boolean;
  qualify_budget: boolean; max_ai_replies: number; done_message: string; handover_message: string;
  waha_mode: "off" | "draft" | "auto"; playbook: string; playbook_built_at: string | null; deal_pipeline_id: string | null; deal_stage_id: string | null;
}
const s = reactive<Settings>({ enabled: false, model: "claude-sonnet-5-5", business_description: "", qualify_need: true, qualify_area: true, qualify_timing: true, qualify_budget: true, max_ai_replies: 12, done_message: "", handover_message: "", waha_mode: "off", playbook: "", playbook_built_at: null, deal_pipeline_id: null, deal_stage_id: null });
const { data } = await useAsyncData("wa-ai-settings", async () => (await supabase.from("whatsapp_ai_settings").select("*").eq("id", 1).maybeSingle()).data);
Object.assign(s, data.value ?? {});
const { locale } = useI18n();
const { data: dealSetup } = await useAsyncData("wa-ai-deal-setup", async () => {
  const [p, st] = await Promise.all([
    supabase.from("pipelines").select("id, name").order("sort_order"),
    supabase.from("pipeline_stages").select("id, pipeline_id, name, is_closed").order("sort_order"),
  ]);
  return { pipelines: p.data ?? [], stages: (st.data ?? []).filter((x: any) => !x.is_closed) };
});
const pipelineItems = computed(() => (dealSetup.value?.pipelines ?? []).map((p: any) => ({ label: p.name, value: p.id })));
const stageItems = computed(() => (dealSetup.value?.stages ?? []).filter((x: any) => x.pipeline_id === s.deal_pipeline_id).map((x: any) => ({ label: x.name, value: x.id })));
watch(() => s.deal_pipeline_id, (id, old) => {
  if (old !== undefined && id !== old) s.deal_stage_id = (dealSetup.value?.stages ?? []).find((x: any) => x.pipeline_id === id)?.id ?? null;
});
const modeItems = computed(() => (["off", "draft", "auto"] as const).map((m) => ({ label: t(`chats.agent.${m}`), value: m })));

// ---- learn from the chats on the phone (a few chats per request)
const learning = ref(false);
const progress = reactive({ done: 0, total: 0, phase: "" as "" | "read" | "build" });
const learnedCount = ref<number | null>(null);
async function learn(relearn: boolean) {
  learning.value = true;
  progress.done = 0;
  progress.phase = "read";
  try {
    const list = await $fetch<{ total: number; pending: string[]; learned: number }>("/api/admin/wa-agent-learn", { method: "POST", body: { step: "list", relearn } });
    progress.total = list.pending.length;
    for (let i = 0; i < list.pending.length; i += 4) {
      const r = await $fetch<{ learned: number }>("/api/admin/wa-agent-learn", { method: "POST", body: { step: "digest", chatIds: list.pending.slice(i, i + 4) } });
      learnedCount.value = r.learned;
      progress.done = Math.min(i + 4, list.pending.length);
    }
    progress.phase = "build";
    await $fetch("/api/admin/wa-agent-learn", { method: "POST", body: { step: "build" } });
    const fresh = (await supabase.from("whatsapp_ai_settings").select("playbook, playbook_built_at").eq("id", 1).maybeSingle()).data;
    if (fresh) Object.assign(s, fresh);
    toast.add({ title: t("chats.agent.saved"), color: "success" });
  } catch (err: any) {
    toast.add({ title: t("chats.agent.failed"), description: err?.data?.statusMessage ?? err.message, color: "error" });
  } finally {
    learning.value = false;
    progress.phase = "";
  }
}
const saving = ref(false);
async function save() {
  saving.value = true;
  const { error } = await supabase.from("whatsapp_ai_settings").update({ ...s }).eq("id", 1);
  saving.value = false;
  if (error) toast.add({ title: t("chats.settings.saveFailed"), description: error.message, color: "error" });
  else toast.add({ title: t("chats.settings.saved"), color: "success" });
}
</script>

<template>
  <UDashboardPanel :ui="{ body: 'kords-canvas !p-3 sm:!p-6' }">
    <template #header>
      <UDashboardNavbar :title="t('admin.whatsappAi.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
      </UDashboardNavbar>
    </template>
    <template #body>
      <div class="mx-auto max-w-3xl space-y-5">
        <section class="kords-card space-y-3 p-4">
          <USwitch v-model="s.enabled" :label="t('chats.settings.enabled')" :description="t('chats.settings.enabledHint')" />
          <p class="rounded-[10px] bg-muted p-3 text-xs text-toned">{{ t("chats.settings.setupNote") }}</p>
        </section>

        <!-- The agent for the chats on the phone (WAHA) -->
        <section class="kords-card space-y-4 p-4">
          <h3 class="flex items-center gap-2 font-semibold text-highlighted"><UIcon name="i-lucide-smartphone" class="size-4 text-primary" />{{ t("chats.agent.title") }}</h3>
          <UFormField :label="t('chats.agent.mode')" :help="t('chats.agent.modeHint')">
            <USelect v-model="s.waha_mode" :items="modeItems" value-key="value" class="w-full sm:w-80" />
          </UFormField>
          <UFormField :label="t('chats.agent.dealWhere')" :help="t('chats.agent.dealHint')">
            <div class="grid gap-3 sm:grid-cols-2">
              <USelect v-model="s.deal_pipeline_id" :items="pipelineItems" value-key="value" :placeholder="t('chats.agent.pipeline')" class="w-full" />
              <USelect v-model="s.deal_stage_id" :items="stageItems" value-key="value" :placeholder="t('chats.agent.stage')" :disabled="!s.deal_pipeline_id" class="w-full" />
            </div>
          </UFormField>
          <div class="space-y-2 rounded-[10px] bg-muted p-3">
            <p class="text-sm font-medium text-highlighted">{{ t("chats.agent.learnTitle") }}</p>
            <p class="text-xs text-toned">{{ t("chats.agent.learnHint") }}</p>
            <p class="text-xs text-muted">{{ s.playbook_built_at ? t("chats.agent.builtAt", { d: formatDMYTime(s.playbook_built_at, locale) }) : t("chats.agent.none") }}</p>
            <div class="flex flex-wrap items-center gap-2">
              <UButton icon="i-lucide-graduation-cap" :label="t('chats.agent.learn')" :loading="learning" @click="learn(false)" />
              <UButton color="neutral" variant="outline" size="sm" :label="t('chats.agent.relearn')" :disabled="learning" @click="learn(true)" />
              <span v-if="learning" class="text-xs text-muted">{{ progress.phase === "build" ? t("chats.agent.building") : t("chats.agent.learning", { done: progress.done, total: progress.total }) }}</span>
            </div>
          </div>
          <UFormField :label="t('chats.agent.playbook')" :help="t('chats.agent.playbookHint')">
            <UTextarea v-model="s.playbook" :rows="14" class="w-full" />
          </UFormField>
          <UButton :label="t('common.save')" :loading="saving" @click="save" />
        </section>

        <section class="kords-card space-y-4 p-4">
          <UFormField :label="t('chats.settings.business')" :help="t('chats.settings.businessHint')">
            <UTextarea v-model="s.business_description" :rows="5" class="w-full" />
          </UFormField>
          <UFormField :label="t('chats.settings.qualifyOn')" :help="t('chats.settings.qualifyOnHint')">
            <div class="flex flex-wrap gap-x-5 gap-y-2">
              <UCheckbox v-model="s.qualify_need" :label="t('chats.fields.need')" />
              <UCheckbox v-model="s.qualify_area" :label="t('chats.fields.area')" />
              <UCheckbox v-model="s.qualify_timing" :label="t('chats.fields.timing')" />
              <UCheckbox v-model="s.qualify_budget" :label="t('chats.fields.budget')" />
            </div>
          </UFormField>
        </section>

        <section class="kords-card space-y-4 p-4">
          <div class="grid gap-4 sm:grid-cols-2">
            <UFormField :label="t('chats.settings.maxReplies')" :help="t('chats.settings.maxRepliesHint')">
              <UInputNumber v-model="s.max_ai_replies" :min="1" class="w-full" />
            </UFormField>
            <UFormField :label="t('chats.settings.model')" :help="t('chats.settings.modelHint')">
              <UInput v-model="s.model" dir="ltr" class="w-full" />
            </UFormField>
          </div>
          <UFormField :label="t('chats.settings.doneMessage')"><UTextarea v-model="s.done_message" :rows="2" class="w-full" /></UFormField>
          <UFormField :label="t('chats.settings.handoverMessage')"><UTextarea v-model="s.handover_message" :rows="2" class="w-full" /></UFormField>
          <UButton :label="t('common.save')" :loading="saving" @click="save" />
        </section>
      </div>
    </template>
  </UDashboardPanel>
</template>
