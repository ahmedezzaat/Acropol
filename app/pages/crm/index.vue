<script setup lang="ts">
definePageMeta({ layout: "dashboard" });

const { t } = useI18n();
const { hasAnyModulePermission, loaded, load } = usePermissions();
if (!loaded.value) await load();

const routeByResource: Record<string, string> = {
  crm_leads: "/crm/leads",
  crm_deals: "/crm/deals",
  crm_quotes: "/crm/quotes",
  crm_customers: "/crm/customers",
};

const crmModule = findModule("crm")!;
const firstAccessible = crmModule.resources.find((r) => hasAnyModulePermission(r.key));

if (firstAccessible) {
  await navigateTo(routeByResource[firstAccessible.key], { replace: true });
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="t('modules.crm.label')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
      </UDashboardNavbar>
    </template>
    <template #body>
      <div class="py-16 text-center text-muted">
        {{ t("crm.noAccess") }}
      </div>
    </template>
  </UDashboardPanel>
</template>
