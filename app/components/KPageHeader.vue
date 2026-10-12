<script setup lang="ts">
// The page header: sidebar toggle, the title with an optional count, and the
// page's actions on the end side (#right).
defineProps<{ title: string; count?: number | string }>();
</script>

<template>
  <UDashboardNavbar>
    <template #leading>
      <UDashboardSidebarCollapse />
    </template>
    <template #title>
      <span class="flex items-center gap-2">
        {{ title }}
        <UBadge v-if="count !== undefined" :label="String(count)" color="neutral" variant="subtle" class="cds-tag" />
      </span>
    </template>
    <template #right>
      <slot name="right" />
    </template>
  </UDashboardNavbar>
</template>
