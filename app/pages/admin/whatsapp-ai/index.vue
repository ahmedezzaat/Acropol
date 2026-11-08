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
}
const s = reactive<Settings>({ enabled: false, model: "claude-sonnet-5-5", business_description: "", qualify_need: true, qualify_area: true, qualify_timing: true, qualify_budget: true, max_ai_replies: 12, done_message: "", handover_message: "" });
const { data } = await useAsyncData("wa-ai-settings", async () => (await supabase.from("whatsapp_ai_settings").select("*").eq("id", 1).maybeSingle()).data);
Object.assign(s, data.value ?? {});
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
