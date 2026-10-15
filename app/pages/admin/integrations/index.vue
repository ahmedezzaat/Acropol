<script setup lang="ts">
definePageMeta({ layout: "dashboard" });

const toast = useToast();
const supabase = useSupabaseClient();
const { t, locale } = useI18n();
const origin = useRequestURL().origin;

interface ApiKey {
  id: string;
  name: string;
  key_prefix: string;
  default_assignee_id: string | null;
  is_active: boolean;
  last_used_at: string | null;
  created_at: string;
}

interface Profile {
  id: string;
  full_name: string | null;
  email: string;
}

// useFetch forwards the session cookie during SSR, which the admin-only
// server route needs.
const { data: keys, refresh, status } = await useFetch<ApiKey[]>("/api/admin/api-keys");

const { data: profiles } = await useAsyncData<Profile[]>("admin-integrations-profiles", async () => {
  const { data, error } = await supabase.from("profiles").select("id, full_name, email").eq("is_active", true);
  if (error) throw error;
  return data ?? [];
});

const assigneeOptions = computed(() => [
  { label: t("admin.integrations.noAssignee"), value: null },
  ...(profiles.value ?? []).map((p) => ({ label: p.full_name || p.email, value: p.id })),
]);

function profileLabel(id: string | null) {
  if (!id) return t("admin.integrations.noAssignee");
  const p = profiles.value?.find((p) => p.id === id);
  return p?.full_name || p?.email || "?";
}

function formatDate(value: string | null) {
  if (!value) return t("admin.integrations.neverUsed");
  return new Date(value).toLocaleString(locale.value === "ar" ? "ar" : "en", {
    dateStyle: "medium",
    timeStyle: "short",
  });
}

// --- WhatsApp webhook settings (saved on the server; the app secret is write-only)
// useFetch (not $fetch) so the session cookie is forwarded on a fresh page load.
const { data: wa, refresh: refreshWa } = await useFetch<{
  verifyToken: string;
  hasAppSecret: boolean;
  appSecretHint: string | null;
  defaultAssigneeId: string | null;
  appId: string;
  configId: string;
  sources: { verifyToken: string | null; appSecret: string | null; defaultAssigneeId: string | null };
}>("/api/admin/integrations-config");
const waVerifyToken = ref(wa.value?.verifyToken ?? "");
const waAppSecret = ref("");
const waAssignee = ref<string | null>(wa.value?.defaultAssigneeId ?? null);
watch(
  wa,
  (saved) => {
    waVerifyToken.value = saved?.verifyToken ?? "";
    waAssignee.value = saved?.defaultAssigneeId ?? null;
  },
  { immediate: true },
);
const savingWa = ref(false);

function generateToken() {
  waVerifyToken.value = crypto.randomUUID().replace(/-/g, "");
}
async function saveWa(extra: Record<string, unknown> = {}) {
  savingWa.value = true;
  try {
    await $fetch("/api/admin/integrations-config", {
      method: "POST",
      body: {
        verify_token: waVerifyToken.value,
        ...(waAppSecret.value ? { app_secret: waAppSecret.value } : {}),
        default_assignee_id: waAssignee.value,
        ...extra,
      },
    });
    waAppSecret.value = "";
    toast.add({ title: t("admin.integrations.waSaved"), color: "success" });
    await refreshWa();
  } catch (err: any) {
    toast.add({ title: t("admin.integrations.waSaveFailed"), description: err?.data?.statusMessage ?? err.message, color: "error" });
  } finally {
    savingWa.value = false;
  }
}
function removeSecret() {
  saveWa({ clear_app_secret: true });
}

// --- WhatsApp Coexistence: connect a number through Meta's Embedded Signup. The
// number keeps working in the WhatsApp Business app; Acropol receives its
// messages and makes a lead for every new person.
interface WaConnection {
  id: string;
  waba_id: string;
  phone_number_id: string;
  display_phone_number: string | null;
  verified_name: string | null;
  coexistence: boolean;
  subscribed: boolean;
  connected_at: string;
}
const { data: connections, refresh: refreshConnections } = await useFetch<WaConnection[]>("/api/admin/whatsapp/connections");
const coexAppId = ref(wa.value?.appId ?? "");
const coexConfigId = ref(wa.value?.configId ?? "");
watch(wa, (saved) => {
  coexAppId.value = saved?.appId ?? "";
  coexConfigId.value = saved?.configId ?? "";
});
const savingCoex = ref(false);
async function saveCoex() {
  savingCoex.value = true;
  try {
    await $fetch("/api/admin/integrations-config", { method: "POST", body: { app_id: coexAppId.value, config_id: coexConfigId.value } });
    toast.add({ title: t("admin.integrations.waSaved"), color: "success" });
    await refreshWa();
  } catch (err: any) {
    toast.add({ title: t("admin.integrations.waSaveFailed"), description: err?.data?.statusMessage ?? err.message, color: "error" });
  } finally {
    savingCoex.value = false;
  }
}
const coexReady = computed(() => !!wa.value?.appId && !!wa.value?.configId && !!wa.value?.hasAppSecret);

let sdkPromise: Promise<void> | null = null;
function loadFacebookSdk(appId: string) {
  if (sdkPromise) return sdkPromise;
  sdkPromise = new Promise<void>((resolve, reject) => {
    const w = window as any;
    w.fbAsyncInit = () => {
      w.FB.init({ appId, autoLogAppEvents: true, xfbml: false, version: "v23.0" });
      resolve();
    };
    const script = document.createElement("script");
    script.src = "https://connect.facebook.net/en_US/sdk.js";
    script.async = true;
    script.onerror = () => {
      sdkPromise = null;
      reject(new Error("Could not load the Facebook SDK"));
    };
    document.head.appendChild(script);
  });
  return sdkPromise;
}

const connecting = ref(false);
async function connectWhatsapp() {
  if (!coexReady.value || !wa.value) return;
  connecting.value = true;
  // The dialog reports the account and number it created through a window message.
  let signup: { waba_id?: string; phone_number_id?: string } = {};
  let cancelled = false;
  const onMessage = (e: MessageEvent) => {
    if (!/facebook\.com$/.test(new URL(e.origin).hostname)) return;
    try {
      const data = typeof e.data === "string" ? JSON.parse(e.data) : e.data;
      if (data?.type !== "WA_EMBEDDED_SIGNUP") return;
      if (data.event === "CANCEL") cancelled = true;
      else if (data.data?.waba_id || data.data?.phone_number_id) signup = { waba_id: data.data.waba_id, phone_number_id: data.data.phone_number_id };
    } catch {
      /* not ours */
    }
  };
  window.addEventListener("message", onMessage);
  try {
    await loadFacebookSdk(wa.value.appId);
    const code = await new Promise<string | null>((resolve) => {
      (window as any).FB.login(
        (response: any) => resolve(response?.authResponse?.code ?? null),
        {
          config_id: wa.value!.configId,
          response_type: "code",
          override_default_response_type: true,
          extras: { setup: {}, featureType: "whatsapp_business_app_onboarding", sessionInfoVersion: "3" },
        },
      );
    });
    if (!code || cancelled) {
      toast.add({ title: t("admin.integrations.coexCancelled"), color: "neutral" });
      return;
    }
    // the finish message can arrive just after the login callback
    await new Promise((r) => setTimeout(r, 1200));
    const result = await $fetch<{ subscribed: boolean }>("/api/admin/whatsapp/connect", {
      method: "POST",
      body: { code, ...(signup.waba_id ? { waba_id: signup.waba_id } : {}), ...(signup.phone_number_id ? { phone_number_id: signup.phone_number_id } : {}) },
    });
    toast.add({ title: t(result.subscribed ? "admin.integrations.coexConnected" : "admin.integrations.coexConnectedNoWebhook"), color: result.subscribed ? "success" : "warning" });
    await refreshConnections();
  } catch (err: any) {
    toast.add({ title: t("admin.integrations.coexFailed"), description: err?.data?.statusMessage ?? err.message, color: "error" });
  } finally {
    window.removeEventListener("message", onMessage);
    connecting.value = false;
  }
}

const disconnectTarget = ref<WaConnection | null>(null);
const disconnectOpen = ref(false);
const disconnecting = ref(false);
function askDisconnect(c: WaConnection) {
  disconnectTarget.value = c;
  disconnectOpen.value = true;
}
async function confirmDisconnect() {
  if (!disconnectTarget.value) return;
  disconnecting.value = true;
  try {
    await $fetch(`/api/admin/whatsapp/connections/${disconnectTarget.value.id}`, { method: "DELETE" });
    disconnectOpen.value = false;
    await refreshConnections();
  } catch (err: any) {
    toast.add({ title: t("admin.integrations.coexFailed"), description: err?.data?.statusMessage ?? err.message, color: "error" });
  } finally {
    disconnecting.value = false;
  }
}

// --- Create key ---
const createOpen = ref(false);
const creating = ref(false);
const newName = ref("");
const newAssignee = ref<string | null>(null);
const revealedKey = ref<string | null>(null);
const revealOpen = ref(false);

function openCreate() {
  newName.value = "";
  newAssignee.value = null;
  createOpen.value = true;
}

async function createKey() {
  if (!newName.value.trim()) return;
  creating.value = true;
  try {
    const created = await $fetch<ApiKey & { key: string }>("/api/admin/api-keys", {
      method: "POST",
      body: { name: newName.value.trim(), default_assignee_id: newAssignee.value },
    });
    createOpen.value = false;
    revealedKey.value = created.key;
    revealOpen.value = true;
    refresh();
  } catch (e) {
    toast.add({
      title: t("admin.integrations.createFailed"),
      description: (e as { statusMessage?: string }).statusMessage,
      color: "error",
    });
  } finally {
    creating.value = false;
  }
}

async function copy(text: string) {
  try {
    await navigator.clipboard.writeText(text);
    toast.add({ title: t("admin.integrations.copied"), color: "success" });
  } catch {
    toast.add({ title: t("admin.integrations.copyFailed"), color: "error" });
  }
}

function copyRevealed() {
  if (revealedKey.value) copy(revealedKey.value);
}
function closeReveal() {
  revealOpen.value = false;
  revealedKey.value = null;
}

// --- Toggle / delete ---
async function setActive(key: ApiKey, value: boolean) {
  try {
    await $fetch(`/api/admin/api-keys/${key.id}/update`, { method: "POST", body: { is_active: value } });
    key.is_active = value;
  } catch (e) {
    toast.add({
      title: t("admin.integrations.saveFailed"),
      description: (e as { statusMessage?: string }).statusMessage,
      color: "error",
    });
    refresh();
  }
}

const deleteTarget = ref<ApiKey | null>(null);
function closeDelete() {
  deleteOpen.value = false;
}
const deleteOpen = ref(false);
const deleting = ref(false);
function askDelete(key: ApiKey) {
  deleteTarget.value = key;
  deleteOpen.value = true;
}
async function confirmDelete() {
  if (!deleteTarget.value) return;
  deleting.value = true;
  try {
    await $fetch(`/api/admin/api-keys/${deleteTarget.value.id}/delete`, { method: "POST" });
    deleteOpen.value = false;
    refresh();
  } catch (e) {
    toast.add({
      title: t("admin.integrations.saveFailed"),
      description: (e as { statusMessage?: string }).statusMessage,
      color: "error",
    });
  } finally {
    deleting.value = false;
  }
}

const curlExample = computed(
  () => `curl -X POST ${origin}/api/v1/leads \\
  -H "Authorization: Bearer YOUR_API_KEY" \\
  -H "Content-Type: application/json" \\
  -d '{
    "name": "Ahmed Ali",
    "phone": "+201001234567",
    "email": "ahmed@example.com",
    "source": "website",
    "notes": "Wants a solar water heater"
  }'`,
);
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="t('admin.integrations.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <div class="max-w-3xl space-y-4">
        <!-- API keys -->
        <UPageCard :title="t('admin.integrations.keysTitle')" :description="t('admin.integrations.keysDescription')">
          <div v-if="status === 'pending'" class="flex justify-center py-6">
            <UIcon name="i-lucide-loader-2" class="size-5 animate-spin text-muted" />
          </div>
          <div v-else class="space-y-3">
            <p v-if="!keys?.length" class="py-4 text-center text-sm text-muted">
              {{ t("admin.integrations.noKeys") }}
            </p>
            <div
              v-for="key in keys"
              :key="key.id"
              class="flex flex-wrap items-center gap-3 border border-default p-3"
              :class="!key.is_active && 'opacity-60'"
            >
              <div class="min-w-0 flex-1 basis-48">
                <div class="font-medium text-highlighted">{{ key.name }}</div>
                <div class="mt-0.5 text-xs text-muted">
                  <span dir="ltr" class="font-mono">{{ key.key_prefix }}…</span>
                  · {{ t("admin.integrations.assignTo") }}: {{ profileLabel(key.default_assignee_id) }}
                </div>
                <div class="text-xs text-muted">
                  {{ t("admin.integrations.lastUsed") }}: {{ formatDate(key.last_used_at) }}
                </div>
              </div>
              <USwitch
                :model-value="key.is_active"
                :label="t('admin.integrations.active')"
                @update:model-value="(v: boolean) => setActive(key, v)"
              />
              <UButton
                icon="i-lucide-trash"
                color="error"
                variant="ghost"
                size="sm"
                :aria-label="t('common.delete')"
                @click="askDelete(key)"
              />
            </div>
            <UButton icon="i-lucide-plus" :label="t('admin.integrations.newKey')" variant="soft" @click="openCreate" />
          </div>
        </UPageCard>

        <!-- Leads API -->
        <UPageCard :title="t('admin.integrations.apiTitle')" :description="t('admin.integrations.apiDescription')">
          <div class="space-y-3 text-sm">
            <div class="flex flex-wrap items-center gap-2">
              <UBadge label="POST" color="primary" variant="subtle" class="cds-tag" />
              <code dir="ltr" class="break-all">{{ origin }}/api/v1/leads</code>
              <UButton
                icon="i-lucide-copy"
                size="xs"
                color="neutral"
                variant="ghost"
                :aria-label="t('admin.integrations.copy')"
                @click="copy(`${origin}/api/v1/leads`)"
              />
            </div>
            <p class="text-muted">{{ t("admin.integrations.apiAuth") }}</p>
            <ul class="list-disc space-y-1 ps-5 text-muted">
              <li><code>name</code> — {{ t("admin.integrations.fieldName") }}</li>
              <li><code>phone</code> / <code>email</code> — {{ t("admin.integrations.fieldContact") }}</li>
              <li><code>phone2</code>, <code>notes</code>, <code>company_name</code>, <code>lead_type</code> (individual | company)</li>
              <li>
                <code>source</code> — external_client, facebook, instagram, meta, google, website, event, referral, whatsapp,
                api ({{ t("admin.integrations.fieldSource") }})
              </li>
            </ul>
            <div class="relative">
              <pre dir="ltr" class="overflow-x-auto bg-muted p-3 pr-10 text-xs">{{ curlExample }}</pre>
              <UButton
                icon="i-lucide-copy"
                size="xs"
                color="neutral"
                variant="ghost"
                class="absolute right-1 top-1"
                :aria-label="t('admin.integrations.copy')"
                @click="copy(curlExample)"
              />
            </div>
            <p class="text-muted">{{ t("admin.integrations.apiResponses") }}</p>
          </div>
        </UPageCard>

        <!-- WhatsApp -->
        <UPageCard
          :title="t('admin.integrations.whatsappTitle')"
          :description="t('admin.integrations.whatsappDescription')"
        >
          <div class="space-y-3 text-sm">
            <div class="flex flex-wrap items-center gap-2">
              <UBadge label="Callback URL" color="neutral" variant="subtle" class="cds-tag" />
              <code dir="ltr" class="break-all">{{ origin }}/api/webhooks/whatsapp</code>
              <UButton
                icon="i-lucide-copy"
                size="xs"
                color="neutral"
                variant="ghost"
                :aria-label="t('admin.integrations.copy')"
                @click="copy(`${origin}/api/webhooks/whatsapp`)"
              />
            </div>
            <ol class="list-decimal space-y-1 ps-5 text-muted">
              <li>{{ t("admin.integrations.waStep1") }}</li>
              <li>{{ t("admin.integrations.waStep2") }}</li>
              <li>{{ t("admin.integrations.waStep3") }}</li>
            </ol>
            <div class="space-y-4 border-t border-default pt-4">
              <UBadge
                :label="wa?.verifyToken && wa?.hasAppSecret ? t('admin.integrations.waReady') : t('admin.integrations.waNotReady')"
                :color="wa?.verifyToken && wa?.hasAppSecret ? 'success' : 'warning'"
                variant="subtle"
              />
              <UFormField :label="t('admin.integrations.waVerifyToken')" :help="t('admin.integrations.waVerifyTokenHint')">
                <div class="flex gap-2">
                  <UInput v-model="waVerifyToken" dir="ltr" class="min-w-0 flex-1" />
                  <UButton color="neutral" variant="outline" icon="i-lucide-wand-sparkles" :label="t('admin.integrations.waGenerate')" @click="generateToken" />
                </div>
              </UFormField>
              <UFormField :label="t('admin.integrations.waAppSecret')">
                <UInput
                  v-model="waAppSecret"
                  type="password"
                  autocomplete="off"
                  dir="ltr"
                  class="w-full"
                  :placeholder="wa?.hasAppSecret ? `•••••••• ${wa.appSecretHint ?? ''}` : ''"
                />
                <p v-if="wa?.hasAppSecret" class="mt-1 text-xs text-muted">
                  {{ wa.sources.appSecret === "env" ? t("admin.integrations.waSecretFromEnv") : t("admin.integrations.waSecretSaved") }}
                </p>
              </UFormField>
              <UFormField :label="t('admin.integrations.assignTo')" :help="t('admin.integrations.assignToHint')">
                <USelect v-model="waAssignee" :items="assigneeOptions" value-key="value" class="w-full" />
              </UFormField>
              <div class="flex flex-wrap items-center gap-2">
                <UButton :label="t('common.save')" :loading="savingWa" @click="saveWa()" />
                <UButton
                  v-if="wa?.hasAppSecret && wa.sources.appSecret === 'settings'"
                  color="error"
                  variant="ghost"
                  :label="t('admin.integrations.waRemoveSecret')"
                  @click="removeSecret"
                />
              </div>
            </div>
            <p class="text-muted">{{ t("admin.integrations.waBehaviour") }}</p>
          </div>
        </UPageCard>

        <!-- WhatsApp Coexistence (Embedded Signup) -->
        <UPageCard :title="t('admin.integrations.coexTitle')" :description="t('admin.integrations.coexDescription')">
          <div class="space-y-4 text-sm">
            <ol class="list-decimal space-y-1 ps-5 text-muted">
              <li>{{ t("admin.integrations.coexStep1") }}</li>
              <li>{{ t("admin.integrations.coexStep2") }}</li>
              <li>{{ t("admin.integrations.coexStep3") }}</li>
            </ol>

            <div class="grid gap-3 sm:grid-cols-2">
              <UFormField :label="t('admin.integrations.coexAppId')">
                <UInput v-model="coexAppId" dir="ltr" class="w-full" />
              </UFormField>
              <UFormField :label="t('admin.integrations.coexConfigId')">
                <UInput v-model="coexConfigId" dir="ltr" class="w-full" />
              </UFormField>
            </div>
            <p v-if="!wa?.hasAppSecret" class="text-xs text-warning">{{ t("admin.integrations.coexNeedSecret") }}</p>
            <div class="flex flex-wrap items-center gap-2">
              <UButton color="neutral" variant="outline" :label="t('common.save')" :loading="savingCoex" @click="saveCoex" />
              <UButton
                icon="i-simple-icons-whatsapp"
                :label="t('admin.integrations.coexConnect')"
                :loading="connecting"
                :disabled="!coexReady"
                @click="connectWhatsapp"
              />
            </div>

            <div class="space-y-2 border-t border-default pt-4">
              <h4 class="font-medium text-highlighted">{{ t("admin.integrations.coexConnected2") }}</h4>
              <p v-if="!connections?.length" class="text-muted">{{ t("admin.integrations.coexNone") }}</p>
              <div
                v-for="c in connections"
                :key="c.id"
                class="flex flex-wrap items-center justify-between gap-2 rounded-[10px] border border-default p-3"
              >
                <div class="min-w-0">
                  <div class="flex flex-wrap items-center gap-2">
                    <bdi dir="ltr" class="font-medium text-highlighted">{{ c.display_phone_number || c.phone_number_id }}</bdi>
                    <KBadge v-if="c.verified_name" :label="c.verified_name" tone="neutral" />
                    <KBadge v-if="c.coexistence" :label="t('admin.integrations.coexBadge')" tone="info" />
                    <KBadge
                      :label="c.subscribed ? t('admin.integrations.coexReceiving') : t('admin.integrations.coexNotReceiving')"
                      :tone="c.subscribed ? 'success' : 'warning'"
                    />
                  </div>
                  <div class="text-xs text-muted">{{ formatDate(c.connected_at) }}</div>
                </div>
                <UButton color="error" variant="ghost" size="sm" icon="i-lucide-unplug" :label="t('admin.integrations.coexDisconnect')" @click="askDisconnect(c)" />
              </div>
            </div>
          </div>
        </UPageCard>
      </div>
    </template>
  </UDashboardPanel>

  <KDeleteConfirmation
    v-model:open="disconnectOpen"
    :title="t('admin.integrations.coexDisconnect')"
    :message="t('admin.integrations.coexDisconnectConfirm', { number: disconnectTarget?.display_phone_number || disconnectTarget?.phone_number_id || '' })"
    :loading="disconnecting"
    @confirm="confirmDisconnect"
  />

  <UModal v-model:open="createOpen" :title="t('admin.integrations.newKey')">
    <template #body>
      <div class="space-y-4">
        <UFormField :label="t('admin.integrations.keyName')" :help="t('admin.integrations.keyNameHint')">
          <UInput v-model="newName" class="w-full" @keydown.enter="createKey" />
        </UFormField>
        <UFormField :label="t('admin.integrations.assignTo')" :help="t('admin.integrations.assignToHint')">
          <USelect v-model="newAssignee" :items="assigneeOptions" value-key="value" class="w-full" />
        </UFormField>
        <UButton
          :label="t('admin.integrations.createKey')"
          :loading="creating"
          :disabled="!newName.trim()"
          block
          @click="createKey"
        />
      </div>
    </template>
  </UModal>

  <UModal v-model:open="revealOpen" :title="t('admin.integrations.keyCreated')" :dismissible="false">
    <template #body>
      <div class="space-y-4">
        <UAlert
          color="warning"
          variant="subtle"
          icon="i-lucide-triangle-alert"
          :description="t('admin.integrations.keyOnce')"
        />
        <div class="flex items-center gap-2">
          <code dir="ltr" class="min-w-0 flex-1 break-all bg-muted p-3 text-sm">{{ revealedKey }}</code>
          <UButton
            icon="i-lucide-copy"
            color="neutral"
            variant="outline"
            :aria-label="t('admin.integrations.copy')"
            @click="copyRevealed"
          />
        </div>
        <UButton :label="t('common.done')" block @click="closeReveal" />
      </div>
    </template>
  </UModal>

  <UModal v-model:open="deleteOpen" :title="t('admin.integrations.deleteTitle')">
    <template #body>
      <div class="space-y-4">
        <p class="text-sm text-muted">
          {{ t("admin.integrations.deleteConfirm", { name: deleteTarget?.name ?? "" }) }}
        </p>
        <div class="flex gap-2">
          <UButton
            color="neutral"
            variant="outline"
            :label="t('common.cancel')"
            class="flex-1 justify-center"
            @click="closeDelete"
          />
          <UButton
            color="error"
            :label="t('common.delete')"
            :loading="deleting"
            class="flex-1 justify-center"
            @click="confirmDelete"
          />
        </div>
      </div>
    </template>
  </UModal>
</template>
