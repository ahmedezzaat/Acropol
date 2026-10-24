<script setup lang="ts">
// Confirmed visits. Someone who sees every confirmed visit (the office) gets the
// table with its filters and the calendar; a technician — who sees only the visits
// assigned to them — gets phone-sized cards for yesterday, today and tomorrow.
definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "cs_maintenance", anyAction: CONFIRMED_VISIT_ACTIONS },
});

const { hasPermission } = usePermissions();
const seesAll = computed(() => hasPermission("cs_maintenance", "view_confirmed_all"));
</script>

<template>
  <ConfirmedVisitsAdmin v-if="seesAll" />
  <TechnicianVisits v-else />
</template>
