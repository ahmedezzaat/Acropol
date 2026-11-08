<script setup lang="ts">
// Settings -> Integrations -> WAHA: the address, session and API key of the WAHA server that carries the
// WhatsApp inbox, a test of the connection, and the webhook to set in the WAHA session.
const toast = useToast();
const { t } = useI18n();
const origin = useRequestURL().origin;

const { data: cfg, refresh } = await useFetch<{ url: string; session: string; hasApiKey: boolean; apiKeyHint: string | null; sources: { apiKey: "settings" | "env" | null } }>("/api/admin/waha-config");
const url = ref(cfg.value?.url ?? "https://waha.sirmatechnology.com");
const session = ref(cfg.value?.session ?? "default");
const apiKey = ref("");
const saving = ref(false);
async function save() {
  saving.value = true;
  try {
    await $fetch("/api/admin/waha-config", { method: "POST", body: { url: url.value, session: session.value, ...(apiKey.value ? { api_key: apiKey.value } : {}) } });
    apiKey.value = "";
    await refresh();
    toast.add({ title: t("waha.saved"), color: "success" });
  } catch (err: any) {
    toast.add({ title: t("waha.saveFailed"), description: err?.data?.statusMessage ?? err.message, color: "error" });
  } finally {
    saving.value = false;
  }
}

const testing = ref(false);
const result = ref<{ status: string; number: string | null; pushName: string | null } | null>(null);
const testError = ref<string | null>(null);
async function test() {
  testing.value = true;
  result.value = null;
  testError.value = null;
  try {
    result.value = await $fetch("/api/admin/waha-test", { method: "POST" });
  } catch (err: any) {
    testError.value = err?.data?.statusMessage ?? err.message;
  } finally {
    testing.value = false;
  }
}

// what to paste in the WAHA session settings
const webhookJson = computed(() =>
  JSON.stringify({ webhooks: [{ url: `${origin}/api/webhooks/whatsapp`, events: ["message", "message.any"], hmac: { key: "<WAHA_WEBHOOK_HMAC_KEY>" } }] }, null, 2),
);
async function copy(text: string) {
  await navigator.clipboard.writeText(text);
  toast.add({ title: t("admin.integrations.copied"), color: "success" });
}
</script>

<template>
  <UPageCard :title="t('waha.title')" :description="t('waha.description')">
    <div class="space-y-4 text-sm">
      <div class="grid gap-3 sm:grid-cols-2">
        <UFormField :label="t('waha.url')"><UInput v-model="url" dir="ltr" class="w-full" /></UFormField>
        <UFormField :label="t('waha.session')" :help="t('waha.sessionHint')"><UInput v-model="session" dir="ltr" class="w-full" /></UFormField>
      </div>
      <UFormField :label="t('waha.apiKey')" :help="cfg?.hasApiKey ? t('waha.keySaved', { hint: cfg.apiKeyHint ?? '' }) : t('waha.keyMissing')">
        <UInput v-model="apiKey" type="password" autocomplete="off" dir="ltr" :placeholder="cfg?.hasApiKey ? '••••••••' : ''" class="w-full" />
      </UFormField>
      <div class="flex flex-wrap items-center gap-2">
        <UButton :label="t('common.save')" :loading="saving" @click="save" />
        <UButton color="neutral" variant="outline" icon="i-lucide-plug-zap" :label="t('waha.test')" :loading="testing" :disabled="!cfg?.hasApiKey && !apiKey" @click="test" />
        <span v-if="result" class="flex items-center gap-1.5 text-xs" :class="result.status === 'WORKING' ? 'text-success' : 'text-warning'">
          <UIcon :name="result.status === 'WORKING' ? 'i-lucide-circle-check' : 'i-lucide-triangle-alert'" class="size-4" />
          {{ result.status }}<template v-if="result.number"> · +{{ result.number }}</template><template v-if="result.pushName"> · {{ result.pushName }}</template>
        </span>
        <span v-if="testError" class="text-xs text-error">{{ testError }}</span>
      </div>

      <div class="space-y-2 border-t border-default pt-4">
        <p class="font-medium text-highlighted">{{ t("waha.webhookTitle") }}</p>
        <p class="text-xs text-muted">{{ t("waha.webhookHint") }}</p>
        <div class="relative">
          <pre class="overflow-x-auto rounded-[10px] bg-muted p-3 text-xs" dir="ltr">{{ webhookJson }}</pre>
          <UButton icon="i-lucide-copy" color="neutral" variant="ghost" size="xs" class="absolute end-2 top-2" :aria-label="t('admin.integrations.copy')" @click="copy(webhookJson)" />
        </div>
      </div>
    </div>
  </UPageCard>
</template>
