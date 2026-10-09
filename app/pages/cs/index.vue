<script setup lang="ts">
definePageMeta({ layout: "dashboard" });

const { hasAnyModulePermission, loaded, load } = usePermissions();
if (!loaded.value) await load();

// Customers is the landing page of Customer Service.
if (hasAnyModulePermission("cs_customers")) {
  await navigateTo("/cs/customers", { replace: true });
} else {
  await navigateTo("/403", { replace: true });
}
</script>

<template>
  <div />
</template>
