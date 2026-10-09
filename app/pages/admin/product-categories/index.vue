<script setup lang="ts">
definePageMeta({ layout: "dashboard" });

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

interface CategoryRow {
  _key: string;
  id: string | null;
  name: string;
  maintenance_interval_months: number | null;
}

const categories = ref<CategoryRow[]>([]);
const removedIds = ref<string[]>([]);
const saving = ref(false);

function newKey() {
  return crypto.randomUUID();
}

// See crm/leads/[id].vue for why this goes through useAsyncData's own
// `data` (via watchEffect) instead of only mutating `categories` inside the
// handler.
const { data: categoriesPayload, status } = await useAsyncData("admin-product-categories", async () => {
  const { data, error } = await supabase.from("product_categories").select("*").order("sort_order");
  if (error) throw error;
  return data ?? [];
});
watchEffect(() => {
  if (!categoriesPayload.value) return;
  categories.value = categoriesPayload.value.map((c) => ({ _key: newKey(), id: c.id, name: c.name, maintenance_interval_months: c.maintenance_interval_months }));
});

function addCategory() {
  categories.value.push({ _key: newKey(), id: null, name: t("admin.productCategories.newCategoryDefault"), maintenance_interval_months: null });
}

function removeCategory(index: number) {
  const row = categories.value[index];
  if (row.id) removedIds.value.push(row.id);
  categories.value.splice(index, 1);
}

function moveCategory(index: number, direction: -1 | 1) {
  const target = index + direction;
  if (target < 0 || target >= categories.value.length) return;
  const [moved] = categories.value.splice(index, 1);
  categories.value.splice(target, 0, moved);
}

async function save() {
  saving.value = true;

  if (removedIds.value.length > 0) {
    const { error } = await supabase.from("product_categories").delete().in("id", removedIds.value);
    if (error) {
      saving.value = false;
      toast.add({ title: t("admin.productCategories.saveFailed"), description: error.message, color: "error" });
      return;
    }
    removedIds.value = [];
  }

  for (const [index, row] of categories.value.entries()) {
    const payload = { name: row.name, sort_order: index + 1, maintenance_interval_months: row.maintenance_interval_months };

    const { data, error } = row.id
      ? await supabase.from("product_categories").update(payload).eq("id", row.id).select().single()
      : await supabase.from("product_categories").insert(payload).select().single();

    if (error) {
      saving.value = false;
      toast.add({ title: t("admin.productCategories.saveFailed"), description: error.message, color: "error" });
      return;
    }
    row.id = data.id;
  }

  saving.value = false;
  toast.add({ title: t("admin.productCategories.categoriesSaved"), color: "success" });
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="t('admin.productCategories.title')">
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
        <UPageCard :description="t('admin.productCategories.description') + ' ' + t('admin.productCategories.maintenanceHint')">
          <div class="space-y-3">
            <div
              v-for="(row, index) in categories"
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
                  @click="moveCategory(index, -1)"
                />
                <UButton
                  icon="i-lucide-chevron-down"
                  color="neutral"
                  variant="ghost"
                  size="xs"
                  :disabled="index === categories.length - 1"
                  @click="moveCategory(index, 1)"
                />
              </div>
              <UInput v-model="row.name" :placeholder="t('admin.productCategories.name')" class="min-w-40 flex-1" />
              <div class="flex items-center gap-1.5">
                <UInputNumber
                  v-model="row.maintenance_interval_months"
                  :min="1"
                  :placeholder="t('admin.productCategories.noMaintenance')"
                  class="w-28"
                />
                <span class="text-xs text-muted">{{ t("admin.productCategories.months") }}</span>
              </div>
              <UButton icon="i-lucide-trash" color="error" variant="ghost" size="sm" @click="removeCategory(index)" />
            </div>

            <UButton
              icon="i-lucide-plus"
              :label="t('admin.productCategories.addCategory')"
              variant="soft"
              @click="addCategory"
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
