<script setup lang="ts">
definePageMeta({ layout: "dashboard" });

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

interface Recipient {
  id: string;
  email: string;
  label: string | null;
  is_active: boolean;
}

const { data: recipients, refresh, status } = await useAsyncData<Recipient[]>("admin-notification-emails", async () => {
  const { data, error } = await supabase.from("notification_emails").select("*").order("created_at");
  if (error) throw error;
  return (data ?? []) as Recipient[];
});

// ---- Recipients
const newEmail = ref("");
const newLabel = ref("");
const adding = ref(false);
const emailValid = computed(() => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(newEmail.value.trim()));

async function add() {
  if (!emailValid.value) return;
  adding.value = true;
  const { error } = await supabase
    .from("notification_emails")
    .insert({ email: newEmail.value.trim().toLowerCase(), label: newLabel.value.trim() || null });
  adding.value = false;
  if (error) {
    const duplicate = error.message.includes("notification_emails_email");
    toast.add({ title: t("admin.notificationEmails.addFailed"), description: duplicate ? t("admin.notificationEmails.duplicate") : error.message, color: "error" });
    return;
  }
  newEmail.value = "";
  newLabel.value = "";
  await refresh();
}
async function toggle(r: Recipient, value: boolean) {
  const { error } = await supabase.from("notification_emails").update({ is_active: value }).eq("id", r.id);
  if (error) {
    toast.add({ title: t("admin.notificationEmails.saveFailed"), description: error.message, color: "error" });
    return;
  }
  r.is_active = value;
}
async function remove(r: Recipient) {
  const { error } = await supabase.from("notification_emails").delete().eq("id", r.id);
  if (error) {
    toast.add({ title: t("admin.notificationEmails.saveFailed"), description: error.message, color: "error" });
    return;
  }
  await refresh();
}

// ---- Email service (Resend): key and sender address. The key is write-only:
// the server only says whether one is set and its last characters.
// useFetch (not $fetch) so the session cookie is forwarded on a fresh page load.
const { data: config, refresh: refreshConfig } = await useFetch<{
  hasKey: boolean;
  keyHint: string | null;
  keySource: "settings" | "env" | null;
  from: string;
  fromSource: "settings" | "env" | null;
}>("/api/admin/notification-emails/config");
const apiKey = ref("");
const from = ref(config.value?.from ?? "");
// Fill the saved sender address in whenever the settings arrive or reload.
watch(
  () => config.value?.from,
  (saved) => {
    from.value = saved ?? "";
  },
  { immediate: true },
);
const savingConfig = ref(false);

async function saveConfig(extra: Record<string, unknown> = {}) {
  savingConfig.value = true;
  try {
    await $fetch("/api/admin/notification-emails/config", {
      method: "POST",
      body: { ...(apiKey.value ? { api_key: apiKey.value } : {}), from: from.value, ...extra },
    });
    apiKey.value = "";
    toast.add({ title: t("admin.notificationEmails.configSaved"), color: "success" });
    await refreshConfig();
  } catch (err: any) {
    toast.add({ title: t("admin.notificationEmails.saveFailed"), description: err?.data?.statusMessage ?? err.message, color: "error" });
  } finally {
    savingConfig.value = false;
  }
}
function clearKey() {
  saveConfig({ clear_key: true });
}

// ---- Test
const testing = ref(false);
async function sendTest() {
  testing.value = true;
  try {
    const res = await $fetch<{ sent: number; reason: string | null; detail: string | null }>("/api/admin/notification-emails/test", { method: "POST" });
    if (res.sent) toast.add({ title: t("admin.notificationEmails.testSent", { count: res.sent }), color: "success" });
    else if (res.reason === "no_recipients") toast.add({ title: t("admin.notificationEmails.testNoRecipients"), color: "warning" });
    else if (res.reason === "not_configured") toast.add({ title: t("admin.notificationEmails.testNotConfigured"), color: "warning" });
    else toast.add({ title: t("admin.notificationEmails.testFailed"), description: res.detail ?? undefined, color: "error" });
  } catch (err: any) {
    toast.add({ title: t("admin.notificationEmails.testFailed"), description: err?.data?.statusMessage ?? err.message, color: "error" });
  } finally {
    testing.value = false;
  }
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="t('admin.notificationEmails.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton icon="i-lucide-send" color="neutral" variant="outline" :label="t('admin.notificationEmails.sendTest')" :loading="testing" @click="sendTest" />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <div class="max-w-2xl space-y-6">
        <!-- Email service -->
        <UPageCard :title="t('admin.notificationEmails.serviceTitle')" :description="t('admin.notificationEmails.serviceHint')">
          <div class="space-y-4">
            <UBadge
              :label="config?.hasKey && config?.from ? t('admin.notificationEmails.ready') : t('admin.notificationEmails.notReady')"
              :color="config?.hasKey && config?.from ? 'success' : 'warning'"
              variant="subtle"
            />
            <UFormField :label="t('admin.notificationEmails.apiKey')">
              <UInput
                v-model="apiKey"
                type="password"
                autocomplete="off"
                :placeholder="config?.hasKey ? `•••••••• ${config.keyHint ?? ''}` : 're_…'"
                class="w-full"
                dir="ltr"
              />
              <p v-if="config?.hasKey" class="mt-1 text-xs text-muted">
                {{ config.keySource === "env" ? t("admin.notificationEmails.keyFromEnv") : t("admin.notificationEmails.keySaved") }}
              </p>
            </UFormField>
            <UFormField :label="t('admin.notificationEmails.fromAddress')" :help="t('admin.notificationEmails.fromHint')">
              <UInput v-model="from" placeholder="Acropol <crm@acropol-eg.com>" class="w-full" dir="ltr" />
            </UFormField>
            <div class="flex flex-wrap items-center gap-2">
              <UButton :label="t('common.save')" :loading="savingConfig" @click="saveConfig()" />
              <UButton
                v-if="config?.hasKey && config.keySource === 'settings'"
                color="error"
                variant="ghost"
                :label="t('admin.notificationEmails.removeKey')"
                @click="clearKey"
              />
            </div>
          </div>
        </UPageCard>

        <!-- Recipients -->
        <UPageCard :title="t('admin.notificationEmails.recipientsTitle')" :description="t('admin.notificationEmails.description')">
          <div class="space-y-3">
            <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-4">
              <UIcon name="i-lucide-loader-2" class="size-5 animate-spin text-muted" />
            </div>
            <p v-else-if="!recipients?.length" class="text-sm text-muted">{{ t("admin.notificationEmails.noEmails") }}</p>
            <ul v-else class="divide-y divide-default border border-default">
              <li v-for="r in recipients" :key="r.id" class="flex flex-wrap items-center justify-between gap-3 px-3 py-2.5" :class="!r.is_active && 'opacity-60'">
                <span class="min-w-0">
                  <bdi dir="ltr" class="block truncate font-medium text-highlighted">{{ r.email }}</bdi>
                  <span v-if="r.label" class="block truncate text-xs text-muted">{{ r.label }}</span>
                </span>
                <span class="flex shrink-0 items-center gap-2">
                  <USwitch :model-value="r.is_active" @update:model-value="(v: boolean) => toggle(r, v)" />
                  <UButton icon="i-lucide-trash" size="sm" color="error" variant="ghost" :aria-label="t('common.delete')" @click="remove(r)" />
                </span>
              </li>
            </ul>

            <div class="flex flex-wrap items-end gap-2 border-t border-default pt-3">
              <UFormField :label="t('common.email')" class="min-w-48 flex-1">
                <UInput v-model="newEmail" type="email" dir="ltr" class="w-full" @keydown.enter.prevent="add" />
              </UFormField>
              <UFormField :label="t('admin.notificationEmails.label')" class="min-w-40 flex-1">
                <UInput v-model="newLabel" class="w-full" @keydown.enter.prevent="add" />
              </UFormField>
              <UButton icon="i-lucide-plus" :label="t('admin.notificationEmails.add')" :loading="adding" :disabled="!emailValid" @click="add" />
            </div>
          </div>
        </UPageCard>
      </div>
    </template>
  </UDashboardPanel>
</template>
