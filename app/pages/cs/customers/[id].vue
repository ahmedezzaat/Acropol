<script setup lang="ts">
// Old links to a customer open the customers list with that customer selected.
definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "cs_customers" },
});

const route = useRoute();
await navigateTo({ path: "/cs/customers", query: { id: route.params.id as string } }, { replace: true });
</script>

<template>
  <div />
</template>
