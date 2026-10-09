<script setup lang="ts">
import type { NavigationMenuItem } from "@nuxt/ui";

const supabase = useSupabaseClient();
const user = useSupabaseUser();
const { isAdmin, hasAnyModulePermission, loaded } = usePermissions();
const { t } = useI18n();

const resourceRoutes: Record<string, string> = {
  crm_leads: "/crm/leads",
  crm_deals: "/crm/deals",
  crm_quotes: "/crm/quotes",
  crm_customers: "/crm/customers",
  crm_visits: "/crm/visits",
  cs_customers: "/cs/customers",
};

const route = useRoute();

// Loads this user's notifications and listens for new ones (toasts + panel).
useNotificationsRealtime();

// The sidebar is contextual: inside /crm it lists only CRM's pages, inside
// /admin only the settings pages, and on the home hub one link per area.
// The way back to Home is the app name in the sidebar header.
const accessibleModules = computed(() =>
  MODULES.filter((m) => m.resources.some((r) => hasAnyModulePermission(r.key))),
);

function moduleLinks(m: (typeof MODULES)[number]): NavigationMenuItem[] {
  // Quotes is temporarily hidden from navigation — see crm/deals/[id].vue
  // for the matching hide on the deal page.
  const resourceLinks = m.resources
    .filter((r) => hasAnyModulePermission(r.key) && r.key !== "crm_quotes")
    .map((r) => ({ label: t(r.labelKey), to: resourceRoutes[r.key] }));
  if (m.key === "customer_service") {
    return [
      { label: t("crm.dashboard.title"), to: "/cs/dashboard" },
      { label: t("cs.customers.title"), to: "/cs/customers" },
      { label: t("cs.installations.title"), to: "/cs/installations" },
      { label: t("cs.maintenance.title"), to: "/cs/maintenance" },
    ];
  }
  if (m.key !== "crm") return resourceLinks;
  return [
    { label: t("crm.dashboard.title"), to: "/crm/dashboard" },
    ...resourceLinks,
    ...(hasAnyModulePermission("crm_deals") ? [{ label: t("crm.calendar.title"), to: "/crm/calendar" }] : []),
  ];
}

const settingsLinks = computed<NavigationMenuItem[]>(() => [
  { label: t("admin.users.title"), icon: "i-lucide-users", to: "/admin/users" },
  { label: t("admin.roles.title"), icon: "i-lucide-shield", to: "/admin/roles" },
  { label: t("admin.pipelines.title"), icon: "i-lucide-git-branch", to: "/admin/pipelines" },
  { label: t("admin.activityTypes.title"), icon: "i-lucide-list-checks", to: "/admin/activity-types" },
  { label: t("admin.productCategories.title"), icon: "i-lucide-tags", to: "/admin/product-categories" },
  { label: t("admin.teams.title"), icon: "i-lucide-users-round", to: "/admin/teams" },
  { label: t("admin.automation.title"), icon: "i-lucide-zap", to: "/admin/automation" },
  { label: t("admin.serviceAreas.title"), icon: "i-lucide-map", to: "/admin/service-areas" },
  { label: t("admin.csPipelines.title"), icon: "i-lucide-workflow", to: "/admin/cs-pipelines" },
  { label: t("admin.visitTypes.title"), icon: "i-lucide-map-pinned", to: "/admin/visit-types" },
  { label: t("admin.integrations.title"), icon: "i-lucide-plug", to: "/admin/integrations" },
]);

const items = computed<NavigationMenuItem[][]>(() => {
  // Permissions load asynchronously — render nothing until they have, so the
  // home-hub fallback below doesn't flash on a hard load of a CRM page.
  if (!loaded.value) return [[]];
  const path = route.path;

  if (path === "/admin" || path.startsWith("/admin/")) return [settingsLinks.value];

  const activeModule = accessibleModules.value.find((m) => path === m.route || path.startsWith(`${m.route}/`));
  if (activeModule) return [moduleLinks(activeModule)];

  return [
    [
      { label: t("nav.home"), icon: "i-lucide-house", to: "/" },
      ...accessibleModules.value.map((m) => ({ label: t(m.labelKey), icon: m.icon, to: m.route })),
      ...(isAdmin.value ? [{ label: t("nav.settings"), icon: "i-lucide-settings", to: "/admin" }] : []),
    ],
  ];
});

async function signOut() {
  await supabase.auth.signOut();
  await navigateTo("/login");
}
</script>

<template>
  <UDashboardGroup>
    <UDashboardSidebar collapsible resizable>
      <template #header="{ collapsed }">
        <div class="flex w-full items-center justify-between gap-2">
          <NuxtLink to="/" class="truncate font-semibold text-highlighted">
            {{ collapsed ? t("nav.appName").charAt(0) : t("nav.appName") }}
          </NuxtLink>
          <div v-if="!collapsed" class="flex items-center">
            <NotificationBell />
            <UButton
              v-if="hasAnyModulePermission('crm_deals')"
              icon="i-lucide-calendar"
              :aria-label="t('crm.calendar.title')"
              color="neutral"
              variant="ghost"
              to="/crm/calendar"
            />
          </div>
        </div>
      </template>

      <template #default="{ collapsed }">
        <UNavigationMenu
          :collapsed="collapsed"
          :items="items"
          orientation="vertical"
        />
      </template>

      <template #footer="{ collapsed }">
        <div class="flex w-full items-center gap-2" :class="collapsed && 'justify-center'">
          <UAvatar :alt="user?.email ?? ''" size="sm" />
          <span v-if="!collapsed" class="truncate text-sm text-muted">{{ user?.email }}</span>
        </div>
        <UButton
          :icon="collapsed ? 'i-lucide-log-out' : undefined"
          :label="collapsed ? undefined : t('nav.signOut')"
          color="neutral"
          variant="ghost"
          block
          class="mt-2"
          @click="signOut"
        />
      </template>
    </UDashboardSidebar>

    <slot />

    <!-- On phones the sidebar is tucked behind the menu button, so the bell
    also floats in the corner. -->
    <div class="fixed bottom-4 end-4 z-40 border border-default bg-default shadow-md lg:hidden">
      <NotificationBell />
    </div>
    <NotificationPanel />
  </UDashboardGroup>
</template>
