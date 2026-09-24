<script setup lang="ts">
definePageMeta({ layout: "dashboard" });

const { hasAnyModulePermission, loaded } = usePermissions();

const visibleModules = computed(() =>
  MODULES.filter((m) => m.resources.some((r) => hasAnyModulePermission(r.key))),
);
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar title="Home">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <div v-if="!loaded" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>

      <div v-else-if="visibleModules.length === 0" class="py-16 text-center text-muted">
        You don't have access to any modules yet. Ask an administrator to
        grant you a role.
      </div>

      <div v-else class="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4">
        <ULink
          v-for="module in visibleModules"
          :key="module.key"
          :to="module.route"
          class="flex flex-col items-center gap-3 rounded-lg border border-default p-6 text-center transition hover:border-primary hover:bg-elevated"
        >
          <UIcon :name="module.icon" class="size-8 text-primary" />
          <span class="font-medium text-highlighted">{{ module.label }}</span>
        </ULink>
      </div>
    </template>
  </UDashboardPanel>
</template>
