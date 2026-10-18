<script setup lang="ts">
definePageMeta({ layout: "dashboard" });

const { hasAnyModulePermission, hasPermission, loaded, load } = usePermissions();
if (!loaded.value) await load();

// Customers is the landing page of Customer Service.
if (hasAnyModulePermission("cs_customers")) {
  await navigateTo("/cs/customers", { replace: true });
} else if (MAINTENANCE_FULL_ACTIONS.some((a) => hasPermission("cs_maintenance", a))) {
  await navigateTo("/cs/maintenance", { replace: true });
} else if (CONFIRMED_VISIT_ACTIONS.some((a) => hasPermission("cs_maintenance", a))) {
  await navigateTo("/cs/confirmed-visits", { replace: true });
} else {
  await navigateTo("/403", { replace: true });
}
</script>

<template>
  <div />
</template>
