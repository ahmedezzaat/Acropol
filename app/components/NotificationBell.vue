<script setup lang="ts">
// A bell with an unread badge; opens the notification panel (rendered once in
// the dashboard layout). Used both in the sidebar header and, on phones, as a
// floating button.
const { t } = useI18n();
const { open, unreadCount } = useNotifications();
function openPanel() {
  open.value = true;
}
</script>

<template>
  <UChip :show="unreadCount > 0" :text="unreadCount > 9 ? '9+' : String(unreadCount)" size="2xl" color="error">
    <UButton
      icon="i-lucide-bell"
      color="neutral"
      variant="ghost"
      :aria-label="t('notifications.title')"
      @click="openPanel"
    />
  </UChip>
</template>
