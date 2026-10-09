<script setup lang="ts">
definePageMeta({ layout: "dashboard" });

const { hasAnyModulePermission, isAdmin, loaded, loadFailed } = usePermissions();
const supabase = useSupabaseClient();

async function signInAgain() {
  await supabase.auth.signOut();
  await navigateTo("/login");
}
const { t } = useI18n();

const visibleModules = computed(() =>
  MODULES.filter((m) => m.resources.some((r) => hasAnyModulePermission(r.key))),
);
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="t('home.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <div v-if="!loaded" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>

      <!-- The lookup itself failed (usually an expired session) — different from
      having no role, so say so and offer the fix. -->
      <div v-else-if="loadFailed" class="mx-auto max-w-md space-y-4 py-16 text-center">
        <p class="text-muted">{{ t("home.loadFailed") }}</p>
        <UButton icon="i-lucide-log-in" :label="t('home.signInAgain')" @click="signInAgain" />
      </div>

      <div v-else-if="visibleModules.length === 0 && !isAdmin" class="py-16 text-center text-muted">
        {{ t("home.noAccess") }}
      </div>

      <div v-else class="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4">
        <ULink
          v-for="module in visibleModules"
          :key="module.key"
          :to="module.route"
          class="flex flex-col items-center gap-3 rounded-lg border border-default p-6 text-center transition hover:border-primary hover:bg-elevated"
        >
          <UIcon :name="module.icon" class="size-8 text-primary" />
          <span class="font-medium text-highlighted">{{ t(module.labelKey) }}</span>
        </ULink>
        <ULink
          v-if="isAdmin"
          to="/admin"
          class="flex flex-col items-center gap-3 rounded-lg border border-default p-6 text-center transition hover:border-primary hover:bg-elevated"
        >
          <UIcon name="i-lucide-settings" class="size-8 text-primary" />
          <span class="font-medium text-highlighted">{{ t("nav.settings") }}</span>
        </ULink>
      </div>
    </template>
  </UDashboardPanel>
</template>
