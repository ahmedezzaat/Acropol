<script setup lang="ts">
definePageMeta({ layout: "dashboard", crmPermission: { module: "crm_work" } });

const { hasPermission, loaded, load } = usePermissions();
if (!loaded.value) await load();

// The Technical office opens on the first board the user may see.
const { data } = await useSupabaseClient().from("work_pipelines").select("id").order("sort_order");
const board = (data ?? []).find((b) => hasPermission("crm_work", "view") || hasPermission("crm_work", b.id));
await navigateTo(board ? `/technical-office/${board.id}` : "/403", { replace: true });
</script>

<template>
  <div />
</template>
