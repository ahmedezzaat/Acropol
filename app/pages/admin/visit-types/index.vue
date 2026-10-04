<script setup lang="ts">
definePageMeta({ layout: "dashboard" });

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();
const { loadTypes } = useVisits();

interface TypeRow {
  _key: string;
  id: string | null;
  key: string | null;
  name: string;
  requires_deal: boolean;
  inUse: number;
}

const rows = ref<TypeRow[]>([]);
const removed = ref<TypeRow[]>([]);
const saving = ref(false);

function newKey() {
  return crypto.randomUUID();
}

// See crm/leads/[id].vue for why this goes through useAsyncData's own `data`
// (via watchEffect) instead of only mutating `rows` inside the handler.
const { data: payload, status } = await useAsyncData("admin-visit-types", async () => {
  const [types, visits] = await Promise.all([
    supabase.from("visit_types").select("*").order("sort_order"),
    supabase.from("field_visits").select("kind"),
  ]);
  if (types.error) throw types.error;
  const counts = new Map<string, number>();
  for (const v of visits.data ?? []) counts.set(v.kind, (counts.get(v.kind) ?? 0) + 1);
  return { types: types.data ?? [], counts };
});
watchEffect(() => {
  if (!payload.value) return;
  rows.value = payload.value.types.map((x) => ({
    _key: newKey(),
    id: x.id,
    key: x.key,
    name: x.name,
    requires_deal: x.requires_deal,
    inUse: payload.value!.counts.get(x.key) ?? 0,
  }));
});

function addType() {
  rows.value.push({
    _key: newKey(),
    id: null,
    key: null,
    name: t("admin.visitTypes.newTypeDefault"),
    requires_deal: true,
    inUse: 0,
  });
}

function removeType(index: number) {
  const row = rows.value[index];
  if (!row) return;
  // A type that already has requests can't be deleted (they would lose their
  // type) — it can still be renamed.
  if (row.inUse > 0) {
    toast.add({ title: t("admin.visitTypes.inUseTitle"), description: t("admin.visitTypes.inUseHint", { count: row.inUse }), color: "warning" });
    return;
  }
  if (row.id) removed.value.push(row);
  rows.value.splice(index, 1);
}

function move(index: number, direction: -1 | 1) {
  const target = index + direction;
  if (target < 0 || target >= rows.value.length) return;
  const [moved] = rows.value.splice(index, 1);
  if (moved) rows.value.splice(target, 0, moved);
}

const valid = computed(() => rows.value.every((r) => r.name.trim().length > 0));

async function save() {
  if (!valid.value) return;
  saving.value = true;

  if (removed.value.length) {
    const { error } = await supabase.from("visit_types").delete().in("id", removed.value.map((r) => r.id!));
    if (error) {
      saving.value = false;
      toast.add({ title: t("admin.visitTypes.saveFailed"), description: error.message, color: "error" });
      return;
    }
    removed.value = [];
  }

  for (const [index, row] of rows.value.entries()) {
    const body = { name: row.name.trim(), requires_deal: row.requires_deal, sort_order: index + 1 };
    const { data, error } = row.id
      ? await supabase.from("visit_types").update(body).eq("id", row.id).select().single()
      : await supabase
          .from("visit_types")
          .insert({ ...body, key: `type_${crypto.randomUUID().slice(0, 8)}` })
          .select()
          .single();
    if (error) {
      saving.value = false;
      toast.add({ title: t("admin.visitTypes.saveFailed"), description: error.message, color: "error" });
      return;
    }
    row.id = data.id;
    row.key = data.key;
  }

  saving.value = false;
  await loadTypes(true);
  toast.add({ title: t("admin.visitTypes.saved"), color: "success" });
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="t('admin.visitTypes.title')">
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
        <UPageCard :description="t('admin.visitTypes.description')">
          <div class="space-y-3">
            <div
              v-for="(row, index) in rows"
              :key="row._key"
              class="space-y-2 border border-default p-3"
            >
              <div class="flex items-center gap-2">
                <div class="flex flex-col">
                  <UButton icon="i-lucide-chevron-up" color="neutral" variant="ghost" size="xs" :disabled="index === 0" @click="move(index, -1)" />
                  <UButton
                    icon="i-lucide-chevron-down"
                    color="neutral"
                    variant="ghost"
                    size="xs"
                    :disabled="index === rows.length - 1"
                    @click="move(index, 1)"
                  />
                </div>
                <UInput v-model="row.name" :placeholder="t('admin.visitTypes.name')" class="min-w-40 flex-1" />
                <UButton icon="i-lucide-trash" color="error" variant="ghost" size="sm" :aria-label="t('common.delete')" @click="removeType(index)" />
              </div>
              <div class="flex flex-wrap items-center justify-between gap-2 ps-9">
                <USwitch
                  v-model="row.requires_deal"
                  :label="t('admin.visitTypes.requiresDeal')"
                  :disabled="row.inUse > 0"
                />
                <span v-if="row.inUse > 0" class="text-xs text-muted">
                  {{ t("admin.visitTypes.usedBy", { count: row.inUse }) }}
                </span>
              </div>
            </div>

            <UButton icon="i-lucide-plus" :label="t('admin.visitTypes.addType')" variant="soft" @click="addType" />
            <div>
              <UButton :label="t('common.save')" :loading="saving" :disabled="!valid" @click="save" />
            </div>
          </div>
        </UPageCard>
      </div>
    </template>
  </UDashboardPanel>
</template>
