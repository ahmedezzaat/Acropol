<script setup lang="ts">
definePageMeta({ layout: "dashboard" });

const { hasAnyModulePermission, hasPermission, isAdmin, loaded, loadFailed } = usePermissions();
const supabase = useSupabaseClient();

async function signInAgain() {
  await supabase.auth.signOut();
  await navigateTo("/login");
}
const { t } = useI18n();

const visibleModules = computed(() =>
  MODULES.filter((m) => m.key !== "settings" && m.resources.some((r) => hasAnyModulePermission(r.key))),
);
// A technician lands straight on their work orders instead of the module picker.
const me = useSupabaseUser();
const hasWorkOrders = computed(() => CONFIRMED_VISIT_ACTIONS.some((a) => hasPermission("cs_maintenance", a)));
watch(
  loaded,
  async (isLoaded) => {
    if (!isLoaded || !me.value || isAdmin.value || !hasWorkOrders.value) return;
    const { data } = await supabase.from("profiles").select("is_technician").eq("id", me.value.sub).maybeSingle();
    if (data?.is_technician) await navigateTo("/cs/confirmed-visits", { replace: true });
  },
  { immediate: true },
);
const canSettings = computed(() => isAdmin.value || hasAnyModulePermission("settings"));
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

      <div v-else-if="visibleModules.length === 0 && !canSettings" class="py-16 text-center text-muted">
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
          v-if="canSettings"
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
