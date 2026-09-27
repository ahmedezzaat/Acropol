<script setup lang="ts">
definePageMeta({ layout: "dashboard" });

const { t } = useI18n();

// crm-permission.global.ts already redirects any non-admin away from any
// /admin/** route, so this page is reached only by admins.
const sections = [
  { titleKey: "admin.users.title", icon: "i-lucide-users", to: "/admin/users" },
  { titleKey: "admin.roles.title", icon: "i-lucide-shield", to: "/admin/roles" },
  { titleKey: "admin.pipelines.title", icon: "i-lucide-git-branch", to: "/admin/pipelines" },
  { titleKey: "admin.activityTypes.title", icon: "i-lucide-list-checks", to: "/admin/activity-types" },
  { titleKey: "admin.teams.title", icon: "i-lucide-users-round", to: "/admin/teams" },
];
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
