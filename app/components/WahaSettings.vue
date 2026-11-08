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

// ---- Connect the number: start the session, show the QR code, watch until it works
const sessionStatus = ref<string>("");
const linkedNumber = ref<string | null>(null);
const linkedName = ref<string | null>(null);
const qr = ref<string | null>(null);
const connecting = ref(false);
const connectNote = ref<string | null>(null);
const connectError = ref<string | null>(null);
let poll: ReturnType<typeof setInterval> | undefined;
let lastQr = 0;

async function loadStatus() {
  try {
    const s = await $fetch<{ status: string; number: string | null; pushName: string | null }>("/api/admin/waha-session");
    sessionStatus.value = s.status;
    linkedNumber.value = s.number;
    linkedName.value = s.pushName;
    connectError.value = null;
    if (s.status === "SCAN_QR_CODE") {
      // the code expires after about 20 seconds: ask for a fresh one
      if (!qr.value || Date.now() - lastQr > 15_000) await loadQr();
    } else {
      qr.value = null;
    }
    if (s.status === "WORKING") stopPolling();
  } catch (err: any) {
    connectError.value = err?.data?.statusMessage ?? err.message;
  }
}
async function loadQr() {
  try {
    const r = await $fetch<{ mimetype: string; data: string }>("/api/admin/waha-qr");
    qr.value = `data:${r.mimetype};base64,${r.data}`;
    lastQr = Date.now();
  } catch {
    qr.value = null;
  }
}
function startPolling() {
  stopPolling();
  poll = setInterval(loadStatus, 3000);
}
function stopPolling() {
  if (poll) clearInterval(poll);
  poll = undefined;
}
async function connect() {
  connecting.value = true;
  connectNote.value = null;
  connectError.value = null;
  try {
    const r = await $fetch<{ webhook: string }>("/api/admin/waha-session-start", { method: "POST" });
    if (r.webhook === "not_configured") connectNote.value = t("waha.webhookNotSet");
    await loadStatus();
    startPolling();
  } catch (err: any) {
    connectError.value = err?.data?.statusMessage ?? err.message;
  } finally {
    connecting.value = false;
  }
}
const disconnecting = ref(false);
async function disconnect() {
  disconnecting.value = true;
  try {
    await $fetch("/api/admin/waha-session-logout", { method: "POST" });
    await loadStatus();
  } catch (err: any) {
    connectError.value = err?.data?.statusMessage ?? err.message;
  } finally {
    disconnecting.value = false;
  }
}
onMounted(async () => {
  if (cfg.value?.hasApiKey) {
    await loadStatus();
    if (["STARTING", "SCAN_QR_CODE"].includes(sessionStatus.value)) startPolling();
  }
});
onBeforeUnmount(stopPolling);

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

      <!-- Connect the number: scan the QR code with the phone -->
      <div class="space-y-3 border-t border-default pt-4">
        <p class="font-medium text-highlighted">{{ t("waha.connectTitle") }}</p>
        <div class="flex flex-wrap items-center gap-2">
          <KBadge v-if="sessionStatus" :label="t(`waha.status.${sessionStatus}`)" :tone="sessionStatus === 'WORKING' ? 'success' : sessionStatus === 'FAILED' ? 'error' : 'warning'" />
          <span v-if="linkedNumber" class="text-xs text-muted" dir="ltr">+{{ linkedNumber }}<template v-if="linkedName"> · {{ linkedName }}</template></span>
          <UButton v-if="sessionStatus !== 'WORKING'" icon="i-simple-icons-whatsapp" :label="t('waha.connect')" :loading="connecting" :disabled="!cfg?.hasApiKey" @click="connect" />
          <UButton v-else color="neutral" variant="outline" icon="i-lucide-unplug" :label="t('waha.disconnect')" :loading="disconnecting" @click="disconnect" />
        </div>
        <p v-if="!cfg?.hasApiKey" class="text-xs text-muted">{{ t("waha.saveKeyFirst") }}</p>
        <p v-if="connectNote" class="rounded-[10px] bg-warning/10 p-3 text-xs text-warning">{{ connectNote }}</p>
        <p v-if="connectError" class="text-xs text-error">{{ connectError }}</p>
        <div v-if="sessionStatus === 'SCAN_QR_CODE'" class="flex flex-wrap items-start gap-4">
          <div class="flex size-56 items-center justify-center rounded-[12px] border border-default bg-white p-2">
            <img v-if="qr" :src="qr" alt="QR" class="size-full object-contain" />
            <UIcon v-else name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
          </div>
          <ol class="list-decimal space-y-1 ps-5 text-xs text-muted">
            <li>{{ t("waha.scan1") }}</li>
            <li>{{ t("waha.scan2") }}</li>
            <li>{{ t("waha.scan3") }}</li>
          </ol>
        </div>
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
