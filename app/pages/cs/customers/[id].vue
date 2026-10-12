<script setup lang="ts">
// One customer's record. The list (/cs/customers) is a full page; a customer opens here.
definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "cs_customers" },
});

useHead({ htmlAttrs: { class: "carbon" } });

const route = useRoute();
const { t } = useI18n();
const customerId = computed(() => route.params.id as string);

async function onDeleted() {
  await navigateTo("/cs/customers");
}
</script>

<template>
  <UDashboardPanel :ui="{ body: 'kords-canvas' }">
    <template #header>
      <UDashboardNavbar>
        <template #leading>
          <UDashboardSidebarCollapse />
          <UButton
            to="/cs/customers"
            icon="i-lucide-arrow-right"
            color="neutral"
            variant="ghost"
            class="rtl:rotate-0 ltr:rotate-180"
            :label="t('cs.profile.backToList')"
          />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <CsCustomerProfile :key="customerId" :customer-id="customerId" @deleted="onDeleted" />
    </template>
  </UDashboardPanel>
</template>
