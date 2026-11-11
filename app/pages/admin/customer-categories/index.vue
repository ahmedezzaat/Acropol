<script setup lang="ts">
// The classification of customers and contacts (فرد، فنادق، شركات ومصانع، مكاتب هندسة...): add, rename, reorder or remove.
definePageMeta({ layout: "dashboard" });

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();
const { loadCategories } = useCustomerCategories();

interface Row { _key: string; id: string | null; name: string; oneVisit: boolean }
const rows = ref<Row[]>([]);
const removedIds = ref<string[]>([]);
const saving = ref(false);

const { data: payload, status } = await useAsyncData("admin-customer-categories", async () => {
  const { data, error } = await supabase.from("customer_categories").select("id, name, sort_order, one_visit_per_customer").order("sort_order");
  if (error) throw error;
  return data ?? [];
});
watchEffect(() => {
  if (payload.value) rows.value = payload.value.map((c) => ({ _key: crypto.randomUUID(), id: c.id as string, name: c.name as string, oneVisit: !!(c as { one_visit_per_customer?: boolean }).one_visit_per_customer }));
});

function add() {
  rows.value.push({ _key: crypto.randomUUID(), id: null, name: "", oneVisit: false });
}
function remove(i: number) {
  const r = rows.value[i]!;
  if (r.id) removedIds.value.push(r.id);
  rows.value.splice(i, 1);
}
function move(i: number, d: -1 | 1) {
  const j = i + d;
  if (j < 0 || j >= rows.value.length) return;
  const [m] = rows.value.splice(i, 1);
  rows.value.splice(j, 0, m!);
}

async function save() {
  const names = rows.value.map((r) => r.name.trim());
  if (names.some((n) => !n) || new Set(names).size !== names.length) {
    toast.add({ title: t("admin.customerCategories.invalid"), color: "error" });
    return;
  }
  saving.value = true;
  if (removedIds.value.length) {
    const { error } = await supabase.from("customer_categories").delete().in("id", removedIds.value);
    if (error) {
      saving.value = false;
      toast.add({ title: t("admin.customerCategories.saveFailed"), description: error.message, color: "error" });
      return;
    }
    removedIds.value = [];
  }
  for (const [index, row] of rows.value.entries()) {
    const body = { name: row.name.trim(), sort_order: index + 1, one_visit_per_customer: row.oneVisit };
    const { data, error } = row.id
      ? await supabase.from("customer_categories").update(body).eq("id", row.id).select("id").single()
      : await supabase.from("customer_categories").insert(body).select("id").single();
    if (error) {
      saving.value = false;
      toast.add({ title: t("admin.customerCategories.saveFailed"), description: error.message, color: "error" });
      return;
    }
    row.id = data.id as string;
  }
  saving.value = false;
  await loadCategories(true);
  toast.add({ title: t("admin.customerCategories.saved"), color: "success" });
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="t('admin.customerCategories.title')">
        <template #leading><UDashboardSidebarCollapse /></template>
      </UDashboardNavbar>
    </template>
    <template #body>
      <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-16"><UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" /></div>
      <div v-else class="max-w-xl">
        <UPageCard :description="t('admin.customerCategories.description')">
          <div class="space-y-2">
            <div v-for="(row, i) in rows" :key="row._key" class="flex items-center gap-2">
              <div class="flex flex-col">
                <UButton icon="i-lucide-chevron-up" color="neutral" variant="ghost" size="xs" :disabled="i === 0" @click="move(i, -1)" />
                <UButton icon="i-lucide-chevron-down" color="neutral" variant="ghost" size="xs" :disabled="i === rows.length - 1" @click="move(i, 1)" />
              </div>
              <UInput v-model="row.name" :placeholder="t('admin.customerCategories.name')" class="flex-1" />
              <USwitch v-model="row.oneVisit" :label="t('admin.customerCategories.oneVisit')" size="sm" />
              <UButton icon="i-lucide-trash" color="error" variant="ghost" size="sm" @click="remove(i)" />
            </div>
            <p class="text-xs text-muted">{{ t("admin.customerCategories.oneVisitHint") }}</p>
            <p class="text-xs text-muted">{{ t("admin.customerCategories.removeHint") }}</p>
            <UButton icon="i-lucide-plus" :label="t('admin.customerCategories.add')" variant="soft" @click="add" />
            <div><UButton :label="t('common.save')" :loading="saving" @click="save" /></div>
          </div>
        </UPageCard>
      </div>
    </template>
  </UDashboardPanel>
</template>
