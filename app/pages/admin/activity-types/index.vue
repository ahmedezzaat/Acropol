<script setup lang="ts">
definePageMeta({ layout: "dashboard" });

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

interface TypeRow {
  _key: string;
  id: string | null;
  key: string | null;
  name: string;
  icon: string;
}

const types = ref<TypeRow[]>([]);
const removedIds = ref<string[]>([]);
const saving = ref(false);

function newKey() {
  return crypto.randomUUID();
}

function slugify(name: string) {
  return (
    name
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "_")
      .replace(/^_+|_+$/g, "") || newKey()
  );
}

// See crm/leads/[id].vue for why this goes through useAsyncData's own
// `data` (via watchEffect) instead of only mutating `types` inside the
// handler.
const { data: typesPayload, status } = await useAsyncData("admin-activity-types", async () => {
  const { data, error } = await supabase.from("activity_types").select("*").order("sort_order");
  if (error) throw error;
  return data ?? [];
});
watchEffect(() => {
  if (!typesPayload.value) return;
  types.value = typesPayload.value.map((t) => ({
    _key: newKey(),
    id: t.id,
    key: t.key,
    name: t.name,
    icon: t.icon,
  }));
});

function addType() {
  types.value.push({
    _key: newKey(),
    id: null,
    key: null,
    name: t("admin.activityTypes.newTypeDefault"),
    icon: "i-lucide-circle",
  });
}

function removeType(index: number) {
  const row = types.value[index];
  if (row.id) removedIds.value.push(row.id);
  types.value.splice(index, 1);
}

function moveType(index: number, direction: -1 | 1) {
  const target = index + direction;
  if (target < 0 || target >= types.value.length) return;
  const [moved] = types.value.splice(index, 1);
  types.value.splice(target, 0, moved);
}

async function save() {
  saving.value = true;

  if (removedIds.value.length > 0) {
    const { error } = await supabase.from("activity_types").delete().in("id", removedIds.value);
    if (error) {
      saving.value = false;
      toast.add({ title: t("admin.activityTypes.saveFailed"), description: error.message, color: "error" });
      return;
    }
    removedIds.value = [];
  }

  for (const [index, row] of types.value.entries()) {
    const payload = {
      key: row.key ?? slugify(row.name),
      name: row.name,
      icon: row.icon || "i-lucide-circle",
      sort_order: index + 1,
    };

    const { data, error } = row.id
      ? await supabase.from("activity_types").update(payload).eq("id", row.id).select().single()
      : await supabase.from("activity_types").insert(payload).select().single();

    if (error) {
      saving.value = false;
      toast.add({ title: t("admin.activityTypes.saveFailed"), description: error.message, color: "error" });
      return;
    }
    row.id = data.id;
    row.key = data.key;
  }

  saving.value = false;
  toast.add({ title: t("admin.activityTypes.typesSaved"), color: "success" });
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="t('admin.activityTypes.title')">
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
        <UPageCard :description="t('admin.activityTypes.description')">
          <div class="space-y-3">
            <div
              v-for="(row, index) in types"
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
                  @click="moveType(index, -1)"
                />
                <UButton
                  icon="i-lucide-chevron-down"
                  color="neutral"
                  variant="ghost"
                  size="xs"
                  :disabled="index === types.length - 1"
                  @click="moveType(index, 1)"
                />
              </div>
              <UIcon :name="row.icon || 'i-lucide-circle'" class="size-5 shrink-0 text-muted" />
              <UInput v-model="row.name" :placeholder="t('admin.activityTypes.name')" class="min-w-40 flex-1" />
              <UInput v-model="row.icon" placeholder="i-lucide-phone" class="w-40" />
              <UButton icon="i-lucide-trash" color="error" variant="ghost" size="sm" @click="removeType(index)" />
            </div>

            <UButton icon="i-lucide-plus" :label="t('admin.activityTypes.addType')" variant="soft" @click="addType" />
            <div>
              <UButton :label="t('common.save')" :loading="saving" @click="save" />
            </div>
          </div>
        </UPageCard>
      </div>
    </template>
  </UDashboardPanel>
</template>
