<script setup lang="ts">
// The CRM's customers list became the contracts page (العقود); old links land there.
definePageMeta({ layout: "dashboard", crmPermission: { module: "crm_customers" } });
await navigateTo("/crm/contracts", { replace: true });
</script>

<template>
  <div />
</template>
