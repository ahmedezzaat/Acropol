<script setup lang="ts">
// Blocks the app until the browser's notification permission is granted:
// assignments and reminders only reach people who have it on, so it is not
// optional here. Browsers that have no Notification API at all (some mobile
// browsers) can't be asked, so they are let through rather than locked out.
const { t } = useI18n();
const supabase = useSupabaseClient();
const { permission, ready, request, recheck, watchChanges } = useNotificationPermission();

const needed = computed(() => ready.value && permission.value !== "unsupported" && permission.value !== "granted");
const denied = computed(() => permission.value === "denied");

onMounted(() => {
  watchChanges();
  // Any first click/keypress unlocks sound (browsers require a gesture).
  window.addEventListener("pointerdown", unlockAudio, { once: true });
  window.addEventListener("keydown", unlockAudio, { once: true });
  // Re-read when the tab regains focus — the user may have just changed the
  // permission in browser settings.
  window.addEventListener("focus", recheck);
});
onBeforeUnmount(() => {
  window.removeEventListener("focus", recheck);
});

async function signOut() {
  await supabase.auth.signOut();
  await navigateTo("/login");
}
</script>

<template>
  <UModal :open="needed" :dismissible="false" :close="false" :title="t('notifications.gate.title')">
    <template #body>
      <div class="space-y-4">
        <div class="flex items-start gap-3">
          <span class="flex size-10 shrink-0 items-center justify-center rounded-full bg-primary/10">
            <UIcon name="i-lucide-bell-ring" class="size-5 text-primary" />
          </span>
          <p class="text-sm text-toned">{{ t("notifications.gate.description") }}</p>
        </div>

        <template v-if="!denied">
          <UButton
            icon="i-lucide-bell-ring"
            :label="t('notifications.gate.enable')"
            size="lg"
            block
            @click="request"
          />
          <p class="text-xs text-muted">{{ t("notifications.gate.promptHint") }}</p>
        </template>

        <template v-else>
          <UAlert
            color="warning"
            variant="subtle"
            icon="i-lucide-triangle-alert"
            :title="t('notifications.gate.blockedTitle')"
            :description="t('notifications.gate.blockedSteps')"
          />
          <UButton
            icon="i-lucide-refresh-cw"
            :label="t('notifications.gate.checkAgain')"
            size="lg"
            block
            @click="recheck"
          />
        </template>

        <UButton
          color="neutral"
          variant="link"
          size="sm"
          :label="t('nav.signOut')"
          class="px-0"
          @click="signOut"
        />
      </div>
    </template>
  </UModal>
</template>
