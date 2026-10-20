<script setup lang="ts">
// Spare parts per product category: pick a category, then add its parts with a price.
definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "cs_spare_parts" },
});

interface SparePart {
  id: string;
  category_id: string;
  name: string;
  price: number;
  notes: string | null;
}

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();
const { hasPermission } = usePermissions();

const canCreate = computed(() => hasPermission("cs_spare_parts", "create"));
const canEdit = computed(() => hasPermission("cs_spare_parts", "edit"));
const canDelete = computed(() => hasPermission("cs_spare_parts", "delete"));

const { data: categories } = await useAsyncData<{ id: string; name: string }[]>("cs-spare-parts-categories", async () => {
  const { data, error } = await supabase.from("product_categories").select("id, name").order("sort_order");
  if (error) throw error;
  return data ?? [];
});
const { data: partsData, refresh } = await useAsyncData<SparePart[]>("cs-spare-parts", async () => {
  const { data, error } = await supabase.from("spare_parts").select("id, category_id, name, price, notes").order("name");
  if (error) throw error;
  return (data ?? []).map((p) => ({ ...p, price: Number(p.price) }));
});
const parts = computed(() => partsData.value ?? []);

const categoryId = ref<string | null>(categories.value?.[0]?.id ?? null);
const search = ref("");

const categoryTabs = computed(() =>
  (categories.value ?? []).map((c) => ({
    value: c.id,
    label: `${c.name} (${parts.value.filter((p) => p.category_id === c.id).length})`,
  })),
);
const categoryName = computed(() => categories.value?.find((c) => c.id === categoryId.value)?.name ?? "");

const inCategory = computed(() => parts.value.filter((p) => p.category_id === categoryId.value));
const shown = computed(() => {
  const q = search.value.trim().toLowerCase();
  return q ? inCategory.value.filter((p) => p.name.toLowerCase().includes(q) || (p.notes ?? "").toLowerCase().includes(q)) : inCategory.value;
});

const money = (v: number) => `${v.toLocaleString("en-US")} ${t("common.currency")}`;

// ---- Add / edit
const formOpen = ref(false);
const editing = ref<SparePart | null>(null);
const name = ref("");
const price = ref<number | null>(null);
const notes = ref("");
const saving = ref(false);

function openAdd() {
  editing.value = null;
  name.value = "";
  price.value = null;
  notes.value = "";
  formOpen.value = true;
}
function openEdit(p: SparePart) {
  editing.value = p;
  name.value = p.name;
  price.value = p.price;
  notes.value = p.notes ?? "";
  formOpen.value = true;
}
const valid = computed(() => !!name.value.trim() && price.value !== null && price.value >= 0);

async function save() {
  if (!valid.value || !categoryId.value) return;
  saving.value = true;
  const row = { name: name.value.trim(), price: price.value ?? 0, notes: notes.value.trim() || null };
  const { error } = editing.value
    ? await supabase.from("spare_parts").update(row).eq("id", editing.value.id)
    : await supabase.from("spare_parts").insert({ ...row, category_id: categoryId.value });
  saving.value = false;
  if (error) {
    toast.add({ title: t("cs.spareParts.saveFailed"), description: error.message, color: "error" });
    return;
  }
  formOpen.value = false;
  toast.add({ title: t("cs.spareParts.saved"), color: "success" });
  await refresh();
}

// ---- Delete
const deleteTarget = ref<SparePart | null>(null);
const deleteOpen = computed({ get: () => !!deleteTarget.value, set: (v) => { if (!v) deleteTarget.value = null; } });
const deleting = ref(false);
function askDelete(p: SparePart) {
  deleteTarget.value = p;
}
function closeForm() {
  formOpen.value = false;
}
async function confirmDelete() {
  if (!deleteTarget.value) return;
  deleting.value = true;
  const { error } = await supabase.from("spare_parts").delete().eq("id", deleteTarget.value.id);
  deleting.value = false;
  if (error) {
    toast.add({ title: t("cs.spareParts.deleteFailed"), description: error.message, color: "error" });
    return;
  }
  deleteTarget.value = null;
  toast.add({ title: t("cs.spareParts.deleted"), color: "success" });
  await refresh();
}
function setCategory(v: unknown) {
  if (typeof v === "string") categoryId.value = v;
}
</script>

<template>
  <UDashboardPanel :ui="{ body: 'kords-canvas' }">
    <template #header>
      <UDashboardNavbar :title="t('cs.spareParts.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton v-if="canCreate && categoryId" icon="i-lucide-plus" :label="t('cs.spareParts.add')" @click="openAdd" />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <p v-if="!categories?.length" class="kords-card p-10 text-center text-sm text-muted">{{ t("cs.spareParts.noCategories") }}</p>
      <div v-else class="space-y-4">
        <p class="text-sm text-muted">{{ t("cs.spareParts.subtitle") }}</p>

        <div class="overflow-x-auto">
          <UTabs :model-value="categoryId ?? undefined" :items="categoryTabs" value-key="value" variant="link" :content="false" class="kords-pilltabs w-max min-w-full" @update:model-value="setCategory" />
        </div>

        <div class="kords-filterbar flex flex-wrap items-center gap-3 p-3">
          <UInput v-model="search" icon="i-lucide-search" :placeholder="t('cs.spareParts.search')" class="w-full sm:w-72" />
          <KBadge :label="`${categoryName} · ${t('cs.spareParts.parts', { count: inCategory.length })}`" tone="primary" />
        </div>

        <p v-if="!inCategory.length" class="kords-card p-10 text-center text-sm text-muted">{{ t("cs.spareParts.empty") }}</p>
        <p v-else-if="!shown.length" class="kords-card p-10 text-center text-sm text-muted">{{ t("cs.spareParts.emptySearch") }}</p>
        <div v-else class="kords-card overflow-x-auto">
          <table class="w-full min-w-[32rem] text-sm">
            <thead>
              <tr class="border-b border-default text-xs text-muted">
                <th class="px-4 py-3 text-start font-medium">{{ t("cs.spareParts.name") }}</th>
                <th class="px-4 py-3 text-start font-medium">{{ t("cs.spareParts.notes") }}</th>
                <th class="px-4 py-3 text-end font-medium">{{ t("cs.spareParts.price") }}</th>
                <th v-if="canEdit || canDelete" class="w-24 px-4 py-3" />
              </tr>
            </thead>
            <tbody class="divide-y divide-default">
              <tr v-for="p in shown" :key="p.id" class="hover:bg-elevated">
                <td class="px-4 py-3 font-medium text-highlighted">{{ p.name }}</td>
                <td class="px-4 py-3 text-toned">{{ p.notes || "—" }}</td>
                <td class="whitespace-nowrap px-4 py-3 text-end font-semibold">{{ money(p.price) }}</td>
                <td v-if="canEdit || canDelete" class="px-4 py-3">
                  <div class="flex items-center justify-end gap-1">
                    <UButton v-if="canEdit" icon="i-lucide-pencil" color="neutral" variant="ghost" size="xs" :aria-label="t('common.edit')" @click="openEdit(p)" />
                    <UButton v-if="canDelete" icon="i-lucide-trash-2" color="error" variant="ghost" size="xs" :aria-label="t('common.delete')" @click="askDelete(p)" />
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </template>
  </UDashboardPanel>

  <KDialog v-model:open="formOpen" :title="editing ? t('cs.spareParts.edit') : t('cs.spareParts.add')" :description="categoryName">
    <div class="space-y-4">
      <UFormField :label="t('cs.spareParts.name')" required>
        <UInput v-model="name" class="w-full" autofocus />
      </UFormField>
      <UFormField :label="t('cs.spareParts.price')" required>
        <UInputNumber v-model="price" :min="0" class="w-full" />
      </UFormField>
      <UFormField :label="t('cs.spareParts.notes')">
        <UTextarea v-model="notes" :rows="2" class="w-full" />
      </UFormField>
    </div>
    <template #actions>
      <UButton color="neutral" variant="outline" :label="t('common.cancel')" @click="closeForm" />
      <UButton :label="t('common.save')" :loading="saving" :disabled="!valid" @click="save" />
    </template>
  </KDialog>

  <KDeleteConfirmation
    v-model:open="deleteOpen"
    :title="t('cs.spareParts.deleteTitle')"
    :message="t('cs.spareParts.deleteBody', { name: deleteTarget?.name ?? '' })"
    :loading="deleting"
    @confirm="confirmDelete"
  />
</template>
