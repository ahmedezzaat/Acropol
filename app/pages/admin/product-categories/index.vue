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
  warranty_policies: WarrantyPolicy[];
  maintenance_tasks: MaintenanceTask[];
  open: boolean; // details panel expanded
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
  categories.value = categoriesPayload.value.map((c) => ({
    _key: newKey(),
    id: c.id,
    name: c.name,
    maintenance_interval_months: c.maintenance_interval_months,
    warranty_policies: (c.warranty_policies ?? []).map((x) => ({ ...x })),
    maintenance_tasks: (c.maintenance_tasks ?? []).map((x) => ({ ...x })),
    open: false,
  }));
});

function addCategory() {
  categories.value.push({
    _key: newKey(),
    id: null,
    name: t("admin.productCategories.newCategoryDefault"),
    maintenance_interval_months: null,
    warranty_policies: [],
    maintenance_tasks: [],
    open: true,
  });
}

function addPolicy(row: CategoryRow) {
  row.warranty_policies.push({ name: "", text: "" });
}
function removePolicy(row: CategoryRow, index: number) {
  row.warranty_policies.splice(index, 1);
}

function addTask(row: CategoryRow) {
  row.maintenance_tasks.push({ every_months: row.maintenance_interval_months ?? 12, title: "", replace: "" });
}
function removeTask(row: CategoryRow, index: number) {
  row.maintenance_tasks.splice(index, 1);
}
function toggleOpen(row: CategoryRow) {
  row.open = !row.open;
}
// A task is only part of the visits that fall on its interval, so it must be a
// whole multiple of the visit interval.
function taskNote(row: CategoryRow, task: MaintenanceTask) {
  const base = row.maintenance_interval_months;
  if (!base || !task.every_months) return null;
  return task.every_months % base === 0 ? null : t("admin.productCategories.taskMultiple", { months: base });
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
    const payload = {
      name: row.name,
      sort_order: index + 1,
      maintenance_interval_months: row.maintenance_interval_months,
      warranty_policies: row.warranty_policies
        .filter((x) => x.text.trim())
        .map((x, i) => ({ name: x.name.trim() || `${t('admin.productCategories.policyDefault')} ${i + 1}`, text: x.text.trim() })),
      maintenance_tasks: row.maintenance_tasks
        .filter((x) => x.title.trim() || x.replace.trim())
        .map((x) => ({ every_months: x.every_months, title: x.title.trim(), replace: x.replace.trim() })),
    };

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
            <div v-for="(row, index) in categories" :key="row._key" class="rounded-lg border border-default">
              <div class="flex flex-wrap items-center gap-2 p-3">
                <div class="flex flex-col">
                  <UButton icon="i-lucide-chevron-up" color="neutral" variant="ghost" size="xs" :disabled="index === 0" @click="moveCategory(index, -1)" />
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
                <UButton
                  :icon="row.open ? 'i-lucide-chevron-up' : 'i-lucide-settings-2'"
                  color="neutral"
                  :variant="row.open ? 'soft' : 'outline'"
                  size="sm"
                  :label="t('admin.productCategories.policies')"
                  @click="toggleOpen(row)"
                />
                <UButton icon="i-lucide-trash" color="error" variant="ghost" size="sm" @click="removeCategory(index)" />
              </div>

              <!-- Warranty and maintenance policies of the category -->
              <div v-if="row.open" class="space-y-5 border-t border-default bg-muted/30 p-3">
                <div class="space-y-2">
                  <div class="text-sm font-medium text-highlighted">{{ t("admin.productCategories.warrantyPolicy") }}</div>
                  <p class="text-xs text-muted">{{ t("admin.productCategories.warrantyPolicyHint") }}</p>
                  <div v-for="(policy, pi) in row.warranty_policies" :key="pi" class="space-y-2 border border-default bg-default p-2.5">
                    <div class="flex items-center gap-2">
                      <UInput v-model="policy.name" :placeholder="t('admin.productCategories.policyName')" class="flex-1" />
                      <UButton icon="i-lucide-trash" color="error" variant="ghost" size="xs" @click="removePolicy(row, pi)" />
                    </div>
                    <UTextarea v-model="policy.text" :rows="3" :placeholder="t('admin.productCategories.policyText')" class="w-full" />
                  </div>
                  <UButton icon="i-lucide-plus" size="sm" color="neutral" variant="soft" :label="t('admin.productCategories.addPolicy')" @click="addPolicy(row)" />
                </div>

                <div class="space-y-2">
                  <div class="text-sm font-medium text-highlighted">{{ t("admin.productCategories.maintenancePolicy") }}</div>
                  <p class="text-xs text-muted">
                    {{ row.maintenance_interval_months
                      ? t("admin.productCategories.maintenancePolicyHint", { months: row.maintenance_interval_months })
                      : t("admin.productCategories.maintenanceNeedsInterval") }}
                  </p>
                  <div v-for="(task, ti) in row.maintenance_tasks" :key="ti" class="space-y-2 border border-default bg-default p-2.5">
                    <div class="flex flex-wrap items-center gap-2">
                      <span class="text-xs text-muted">{{ t("admin.productCategories.every") }}</span>
                      <UInputNumber v-model="task.every_months" :min="1" class="w-24" />
                      <span class="text-xs text-muted">{{ t("admin.productCategories.months") }}</span>
                      <UButton class="ms-auto" icon="i-lucide-trash" color="error" variant="ghost" size="xs" @click="removeTask(row, ti)" />
                    </div>
                    <p v-if="taskNote(row, task)" class="text-xs text-warning">{{ taskNote(row, task) }}</p>
                    <UFormField :label="t('admin.productCategories.taskTitle')">
                      <UTextarea v-model="task.title" :rows="2" class="w-full" />
                    </UFormField>
                    <UFormField :label="t('admin.productCategories.taskReplace')">
                      <UTextarea v-model="task.replace" :rows="2" class="w-full" />
                    </UFormField>
                  </div>
                  <UButton icon="i-lucide-plus" size="sm" color="neutral" variant="soft" :label="t('admin.productCategories.addTask')" @click="addTask(row)" />
                </div>
              </div>
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
