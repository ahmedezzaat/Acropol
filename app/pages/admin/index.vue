<script setup lang="ts">
definePageMeta({ layout: "dashboard" });

const { t } = useI18n();

const { hasPermission } = usePermissions();

// crm-permission.global.ts only lets in administrators and roles granted at
// least one Settings page; each person sees just the pages they can manage.
const sections = computed(() =>
  SETTINGS_ITEMS.filter((i) => hasPermission("settings", i.key)).map((i) => ({ titleKey: i.titleKey, icon: i.icon, to: i.path })),
);
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="t('nav.settings')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <div class="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4">
        <ULink
          v-for="section in sections"
          :key="section.to"
          :to="section.to"
          class="flex flex-col items-center gap-3 rounded-lg border border-default p-6 text-center transition hover:border-primary hover:bg-elevated"
        >
          <UIcon :name="section.icon" class="size-8 text-primary" />
          <span class="font-medium text-highlighted">{{ t(section.titleKey) }}</span>
        </ULink>
      </div>
    </template>
  </UDashboardPanel>
</template>
