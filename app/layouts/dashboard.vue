<script setup lang="ts">
import type { NavigationMenuItem } from "@nuxt/ui";

const supabase = useSupabaseClient();
const user = useSupabaseUser();
const { isAdmin, hasAnyModulePermission } = usePermissions();
const { t } = useI18n();

const resourceRoutes: Record<string, string> = {
  crm_leads: "/crm/leads",
  crm_deals: "/crm/deals",
  crm_quotes: "/crm/quotes",
  crm_customers: "/crm/customers",
};

const items = computed<NavigationMenuItem[][]>(() => {
  const moduleItems: NavigationMenuItem[] = MODULES.filter((m) =>
    m.resources.some((r) => hasAnyModulePermission(r.key)),
  ).map((m) => {
    const accessibleResources = m.resources.filter((r) => hasAnyModulePermission(r.key));
    // The CRM dashboard is always offered alongside whatever resources the
    // user has, so it always has at least one sibling — never collapse it
    // into a single direct link the way a lone resource otherwise would.
    const isCrm = m.key === "crm";
    const hasChildren = isCrm || accessibleResources.length > 1;
    const resourceChildren = accessibleResources.map((r) => ({
      label: t(r.labelKey),
      to: resourceRoutes[r.key],
    }));
    return {
      label: t(m.labelKey),
      icon: m.icon,
      to: hasChildren ? undefined : m.route,
      type: hasChildren ? "trigger" : "link",
      defaultOpen: true,
      children: hasChildren
        ? isCrm
          ? [
              { label: t("crm.dashboard.title"), to: "/crm/dashboard" },
              ...resourceChildren,
              ...(hasAnyModulePermission("crm_deals")
                ? [{ label: t("crm.calendar.title"), to: "/crm/calendar" }]
                : []),
            ]
          : resourceChildren
        : undefined,
    };
  });

  const groups: NavigationMenuItem[][] = [
    [{ label: t("nav.home"), icon: "i-lucide-house", to: "/" }, ...moduleItems],
  ];

  if (isAdmin.value) {
    groups.push([
      {
        label: t("nav.settings"),
        icon: "i-lucide-settings",
        type: "trigger",
        defaultOpen: true,
        children: [
          { label: t("admin.users.title"), icon: "i-lucide-users", to: "/admin/users" },
          { label: t("admin.roles.title"), icon: "i-lucide-shield", to: "/admin/roles" },
          { label: t("admin.pipelines.title"), icon: "i-lucide-git-branch", to: "/admin/pipelines" },
          { label: t("admin.activityTypes.title"), icon: "i-lucide-list-checks", to: "/admin/activity-types" },
          { label: t("admin.teams.title"), icon: "i-lucide-users-round", to: "/admin/teams" },
        ],
      },
    ]);
  }

  return groups;
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
          <span class="truncate font-semibold text-highlighted">
            {{ collapsed ? t("nav.appName").charAt(0) : t("nav.appName") }}
          </span>
          <UButton
            v-if="!collapsed && hasAnyModulePermission('crm_deals')"
            icon="i-lucide-calendar"
            :aria-label="t('crm.calendar.title')"
            color="neutral"
            variant="ghost"
            size="sm"
            to="/crm/calendar"
          />
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
  </UDashboardGroup>
</template>
