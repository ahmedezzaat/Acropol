<script setup lang="ts">
definePageMeta({ layout: "dashboard" });

const { t } = useI18n();
const { hasPermission, loaded, load } = usePermissions();
if (!loaded.value) await load();

const available = computed(() => REPORTS.filter((r) => hasPermission("reports", r.key)));

// One report: go straight to it.
if (available.value.length === 0) await navigateTo("/403", { replace: true });
</script>

<template>
  <UDashboardPanel :ui="{ body: 'kords-canvas' }">
    <template #header>
      <UDashboardNavbar :title="t('reports.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <p class="mb-4 text-sm text-muted">{{ t("reports.subtitle") }}</p>
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <NuxtLink
          v-for="r in available"
          :key="r.key"
          :to="r.path"
          class="kords-card flex items-start gap-3 p-5 transition-colors hover:border-primary"
        >
          <span class="flex size-10 shrink-0 items-center justify-center rounded-[10px] bg-primary/10 text-primary">
            <UIcon :name="r.icon" class="size-5" />
          </span>
          <span class="min-w-0">
            <span class="block font-semibold text-highlighted">{{ t(r.titleKey) }}</span>
            <span class="mt-1 block text-sm text-muted">{{ t(r.descriptionKey) }}</span>
          </span>
        </NuxtLink>
      </div>
    </template>
  </UDashboardPanel>
</template>
