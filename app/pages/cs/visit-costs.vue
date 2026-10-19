<script setup lang="ts">
// What a maintenance visit costs in each area. The cost is offered when a visit is
// recorded as done (the customer's area decides which one).
definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "cs_visit_costs" },
});

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();
const { hasPermission } = usePermissions();
const canEdit = computed(() => hasPermission("cs_visit_costs", "edit"));

const { data: areas } = await useAsyncData<{ id: string; name: string }[]>("cs-visit-costs-areas", async () => {
  const { data, error } = await supabase.from("service_areas").select("id, name").order("sort_order");
  if (error) throw error;
  return data ?? [];
});
const { data: saved, refresh } = await useAsyncData<Record<string, number>>("cs-visit-costs", async () => {
  const { data, error } = await supabase.from("area_visit_costs").select("area_id, cost");
  if (error) throw error;
  return Object.fromEntries((data ?? []).map((r) => [r.area_id, Number(r.cost)]));
});

// What is typed in each row (null = no cost set); a row is "dirty" when it differs from what is saved.
const draft = reactive<Record<string, number | null>>({});
watch(
  [areas, saved],
  () => {
    for (const a of areas.value ?? []) draft[a.id] = saved.value?.[a.id] ?? null;
  },
  { immediate: true },
);
const dirty = (id: string) => (draft[id] ?? null) !== (saved.value?.[id] ?? null);
const setCount = computed(() => Object.keys(saved.value ?? {}).length);

const savingId = ref<string | null>(null);
async function save(areaId: string) {
  const value = draft[areaId] ?? null;
  if (value !== null && value < 0) return;
  savingId.value = areaId;
  const { error } =
    value === null
      ? await supabase.from("area_visit_costs").delete().eq("area_id", areaId)
      : await supabase.from("area_visit_costs").upsert({ area_id: areaId, cost: value, updated_at: new Date().toISOString() });
  savingId.value = null;
  if (error) {
    toast.add({ title: t("cs.visitCosts.saveFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t(value === null ? "cs.visitCosts.cleared" : "cs.visitCosts.saved"), color: "success" });
  await refresh();
}
</script>

<template>
  <UDashboardPanel :ui="{ body: 'kords-canvas' }">
    <template #header>
      <UDashboardNavbar :title="t('cs.visitCosts.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <p v-if="!areas?.length" class="kords-card p-10 text-center text-sm text-muted">{{ t("cs.visitCosts.noAreas") }}</p>
      <div v-else class="space-y-4">
        <p class="text-sm text-muted">{{ t("cs.visitCosts.subtitle") }}</p>
        <KBadge :label="t('cs.visitCosts.set', { count: setCount, total: areas.length })" tone="primary" />

        <div class="kords-card overflow-x-auto">
          <table class="w-full min-w-[28rem] text-sm">
            <thead>
              <tr class="border-b border-default text-xs text-muted">
                <th class="px-4 py-3 text-start font-medium">{{ t("cs.visitCosts.area") }}</th>
                <th class="px-4 py-3 text-start font-medium">{{ t("cs.visitCosts.cost") }}</th>
                <th v-if="canEdit" class="w-28 px-4 py-3" />
              </tr>
            </thead>
            <tbody class="divide-y divide-default">
              <tr v-for="a in areas" :key="a.id">
                <td class="px-4 py-3 font-medium text-highlighted">{{ a.name }}</td>
                <td class="px-4 py-3">
                  <UInputNumber v-if="canEdit" v-model="draft[a.id]" :min="0" :placeholder="t('cs.visitCosts.none')" class="w-48" @keyup.enter="save(a.id)" />
                  <span v-else-if="saved?.[a.id] !== undefined" class="font-semibold">{{ saved[a.id]!.toLocaleString("en-US") }} {{ t("common.currency") }}</span>
                  <span v-else class="text-muted">{{ t("cs.visitCosts.none") }}</span>
                </td>
                <td v-if="canEdit" class="px-4 py-3 text-end">
                  <UButton :label="t('cs.visitCosts.save')" size="sm" :disabled="!dirty(a.id)" :loading="savingId === a.id" @click="save(a.id)" />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </template>
  </UDashboardPanel>
</template>
