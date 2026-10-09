<script setup lang="ts">
definePageMeta({ layout: "dashboard" });

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

interface AreaRow {
  _key: string;
  id: string | null;
  name: string;
}

const areas = ref<AreaRow[]>([]);
const removedIds = ref<string[]>([]);
const saving = ref(false);

function newKey() {
  return crypto.randomUUID();
}

// See crm/leads/[id].vue for why this goes through useAsyncData's own
// `data` (via watchEffect) instead of only mutating `areas` inside the
// handler.
const { data: areasPayload, status } = await useAsyncData("admin-service-areas", async () => {
  const { data, error } = await supabase.from("service_areas").select("*").order("sort_order");
  if (error) throw error;
  return data ?? [];
});
watchEffect(() => {
  if (!areasPayload.value) return;
  areas.value = areasPayload.value.map((c) => ({ _key: newKey(), id: c.id, name: c.name }));
});

function addArea() {
  areas.value.push({ _key: newKey(), id: null, name: t("admin.serviceAreas.newAreaDefault") });
}

function removeArea(index: number) {
  const row = areas.value[index];
  if (!row) return;
  if (row.id) removedIds.value.push(row.id);
  areas.value.splice(index, 1);
}

function moveArea(index: number, direction: -1 | 1) {
  const target = index + direction;
  if (target < 0 || target >= areas.value.length) return;
  const [moved] = areas.value.splice(index, 1);
  if (moved) areas.value.splice(target, 0, moved);
}

async function save() {
  saving.value = true;

  if (removedIds.value.length > 0) {
    const { error } = await supabase.from("service_areas").delete().in("id", removedIds.value);
    if (error) {
      saving.value = false;
      toast.add({ title: t("admin.serviceAreas.saveFailed"), description: error.message, color: "error" });
      return;
    }
    removedIds.value = [];
  }

  for (const [index, row] of areas.value.entries()) {
    const payload = { name: row.name, sort_order: index + 1 };

    const { data, error } = row.id
      ? await supabase.from("service_areas").update(payload).eq("id", row.id).select().single()
      : await supabase.from("service_areas").insert(payload).select().single();

    if (error) {
      saving.value = false;
      toast.add({ title: t("admin.serviceAreas.saveFailed"), description: error.message, color: "error" });
      return;
    }
    row.id = data.id;
  }

  saving.value = false;
  toast.add({ title: t("admin.serviceAreas.areasSaved"), color: "success" });
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="t('admin.serviceAreas.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>

      <div v-else class="max-w-2xl">
        <UPageCard :description="t('admin.serviceAreas.description')">
          <div class="space-y-3">
            <div
              v-for="(row, index) in areas"
              :key="row._key"
              class="flex flex-wrap items-center gap-2 rounded-lg border border-default p-3"
            >
              <div class="flex flex-col">
                <UButton
                  icon="i-lucide-chevron-up"
                  color="neutral"
                  variant="ghost"
                  size="xs"
                  :disabled="index === 0"
                  @click="moveArea(index, -1)"
                />
                <UButton
                  icon="i-lucide-chevron-down"
                  color="neutral"
                  variant="ghost"
                  size="xs"
                  :disabled="index === areas.length - 1"
                  @click="moveArea(index, 1)"
                />
              </div>
              <UInput v-model="row.name" :placeholder="t('admin.serviceAreas.name')" class="min-w-40 flex-1" />
              <UButton icon="i-lucide-trash" color="error" variant="ghost" size="sm" @click="removeArea(index)" />
            </div>

            <UButton
              icon="i-lucide-plus"
              :label="t('admin.serviceAreas.addArea')"
              variant="soft"
              @click="addArea"
            />
            <div>
              <UButton :label="t('common.save')" :loading="saving" @click="save" />
            </div>
          </div>
        </UPageCard>
      </div>
    </template>
  </UDashboardPanel>
</template>
