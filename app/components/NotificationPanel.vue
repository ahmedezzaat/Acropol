<script setup lang="ts">
const { t, locale, localeProperties } = useI18n();
const { items, open, unreadCount, describe, markRead, markAllRead } = useNotifications();

// The sidebar sits on the reading-start side, so the panel opens from the
// opposite edge.
const side = computed(() => (localeProperties.value.dir === "rtl" ? "left" : "right"));

const canEnableDesktop = ref(false);
onMounted(() => {
  canEnableDesktop.value = "Notification" in window && Notification.permission === "default";
});
async function enableDesktop() {
  const result = await Notification.requestPermission();
  canEnableDesktop.value = result === "default";
}

const rtf = computed(() => new Intl.RelativeTimeFormat(locale.value === "ar" ? "ar" : "en", { numeric: "auto" }));
function ago(value: string) {
  const seconds = Math.round((new Date(value).getTime() - Date.now()) / 1000);
  const abs = Math.abs(seconds);
  if (abs < 60) return rtf.value.format(Math.round(seconds), "second");
  if (abs < 3600) return rtf.value.format(Math.round(seconds / 60), "minute");
  if (abs < 86400) return rtf.value.format(Math.round(seconds / 3600), "hour");
  return rtf.value.format(Math.round(seconds / 86400), "day");
}

const rows = computed(() => items.value.map((n) => ({ n, d: describe(n) })));

async function openNotification(row: (typeof rows.value)[number]) {
  markRead(row.n);
  open.value = false;
  await navigateTo(row.d.link);
}
</script>

<template>
  <USlideover v-model:open="open" :side="side" :title="t('notifications.title')">
    <template #body>
      <div class="-mx-1 space-y-3">
        <div class="flex flex-wrap items-center gap-2 px-1">
          <UButton
            v-if="unreadCount > 0"
            icon="i-lucide-check-check"
            size="sm"
            color="neutral"
            variant="outline"
            :label="t('notifications.markAllRead')"
            @click="markAllRead"
          />
          <UButton
            v-if="canEnableDesktop"
            icon="i-lucide-bell-ring"
            size="sm"
            color="neutral"
            variant="ghost"
            :label="t('notifications.enableDesktop')"
            @click="enableDesktop"
          />
        </div>

        <p v-if="!rows.length" class="py-10 text-center text-sm text-muted">{{ t("notifications.empty") }}</p>

        <ul v-else class="divide-y divide-default border border-default">
          <li v-for="row in rows" :key="row.n.id">
            <button
              type="button"
              class="flex w-full items-start gap-3 p-3 text-start transition-colors hover:bg-elevated"
              :class="!row.n.is_read && 'bg-primary/5'"
              @click="openNotification(row)"
            >
              <span class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-elevated">
                <UIcon :name="row.d.icon" class="size-4" :class="`text-${row.d.color}`" />
              </span>
              <span class="min-w-0 flex-1">
                <span class="block text-sm" :class="row.n.is_read ? 'text-toned' : 'font-medium text-highlighted'">
                  {{ row.d.text }}
                </span>
                <span class="mt-0.5 block text-xs text-muted">{{ ago(row.n.created_at) }}</span>
              </span>
              <span v-if="!row.n.is_read" class="mt-2 size-2 shrink-0 rounded-full bg-primary" />
            </button>
          </li>
        </ul>
      </div>
    </template>
  </USlideover>
</template>
