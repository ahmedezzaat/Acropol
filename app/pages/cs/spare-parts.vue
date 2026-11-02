<script setup lang="ts">
// Spare parts per product category: pick a category, then add its parts with a price. Prices are kept
// in price lists: the default one (individual customers) and any others, e.g. for companies.
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

interface PriceList {
  id: string;
  name: string;
  sort_order: number;
  is_default: boolean;
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

// ---- Price lists
const { data: listsData, refresh: refreshLists } = await useAsyncData<PriceList[]>("cs-spare-part-price-lists", async () => {
  const { data, error } = await supabase.from("spare_part_price_lists").select("id, name, sort_order, is_default").order("sort_order").order("created_at");
  if (error) throw error;
  return (data ?? []) as PriceList[];
});
const lists = computed(() => listsData.value ?? []);
// each part's price in every list but the default (which uses the part's own price)
const { data: overridesData, refresh: refreshOverrides } = await useAsyncData<{ price_list_id: string; spare_part_id: string; price: number }[]>("cs-spare-part-prices", async () => {
  const { data } = await supabase.from("spare_part_prices").select("price_list_id, spare_part_id, price");
  return (data ?? []).map((r) => ({ ...r, price: Number(r.price) }));
});
const listId = ref<string | null>(lists.value.find((l) => l.is_default)?.id ?? lists.value[0]?.id ?? null);
const currentList = computed(() => lists.value.find((l) => l.id === listId.value) ?? null);
const isDefaultList = computed(() => !currentList.value || currentList.value.is_default);
const ownPrice = (p: SparePart) => overridesData.value?.find((o) => o.price_list_id === listId.value && o.spare_part_id === p.id)?.price;
const priceOf = (p: SparePart) => (isDefaultList.value ? p.price : ownPrice(p) ?? p.price);
const listTabs = computed(() => lists.value.map((l) => ({ value: l.id, label: l.name })));
function setList(v: unknown) {
  if (typeof v === "string") listId.value = v;
}

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
// in a list other than the default one only the price is edited (the part itself is shared)
const priceOnly = computed(() => !isDefaultList.value);

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
  price.value = priceOf(p);
  notes.value = p.notes ?? "";
  formOpen.value = true;
}
const valid = computed(() => (priceOnly.value || !!name.value.trim()) && price.value !== null && price.value >= 0);

async function save() {
  if (!valid.value || !categoryId.value) return;
  saving.value = true;
  if (priceOnly.value && editing.value && listId.value) {
    const { error: priceError } = await supabase
      .from("spare_part_prices")
      .upsert({ price_list_id: listId.value, spare_part_id: editing.value.id, price: price.value ?? 0 }, { onConflict: "price_list_id,spare_part_id" });
    saving.value = false;
    if (priceError) {
      toast.add({ title: t("cs.spareParts.saveFailed"), description: priceError.message, color: "error" });
      return;
    }
    formOpen.value = false;
    toast.add({ title: t("cs.spareParts.saved"), color: "success" });
    await refreshOverrides();
    return;
  }
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

// A part with no price of its own in this list goes back to its default price.
async function useDefaultPrice() {
  if (!editing.value || !listId.value) return;
  saving.value = true;
  const { error } = await supabase.from("spare_part_prices").delete().eq("price_list_id", listId.value).eq("spare_part_id", editing.value.id);
  saving.value = false;
  if (error) {
    toast.add({ title: t("cs.spareParts.saveFailed"), description: error.message, color: "error" });
    return;
  }
  formOpen.value = false;
  await refreshOverrides();
}

// ---- Manage the price lists
const listsOpen = ref(false);
const newListName = ref("");
const listBusy = ref(false);
const renaming = reactive<Record<string, string>>({});
async function addList() {
  const name = newListName.value.trim();
  if (!name) return;
  listBusy.value = true;
  const { data, error } = await supabase.from("spare_part_price_lists").insert({ name, sort_order: lists.value.length }).select("id").single();
  listBusy.value = false;
  if (error || !data) {
    toast.add({ title: t("cs.spareParts.listFailed"), description: error?.message, color: "error" });
    return;
  }
  newListName.value = "";
  await refreshLists();
  listId.value = data.id;
}
async function renameList(l: PriceList) {
  const name = (renaming[l.id] ?? l.name).trim();
  if (!name || name === l.name) return;
  const { error } = await supabase.from("spare_part_price_lists").update({ name }).eq("id", l.id);
  if (error) toast.add({ title: t("cs.spareParts.listFailed"), description: error.message, color: "error" });
  await refreshLists();
}
async function deleteList(l: PriceList) {
  const { error } = await supabase.from("spare_part_price_lists").delete().eq("id", l.id);
  if (error) {
    toast.add({ title: t("cs.spareParts.listFailed"), description: error.message, color: "error" });
    return;
  }
  if (listId.value === l.id) listId.value = lists.value.find((x) => x.is_default)?.id ?? null;
  await Promise.all([refreshLists(), refreshOverrides()]);
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
          <UButton v-if="canCreate && categoryId && isDefaultList" icon="i-lucide-plus" :label="t('cs.spareParts.add')" @click="openAdd" />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <p v-if="!categories?.length" class="kords-card p-10 text-center text-sm text-muted">{{ t("cs.spareParts.noCategories") }}</p>
      <div v-else class="space-y-4">
        <p class="text-sm text-muted">{{ t("cs.spareParts.subtitle") }}</p>

        <!-- Price lists: the default one is the individual customers' -->
        <div class="flex flex-wrap items-center gap-2">
          <span class="flex items-center gap-1 text-xs font-medium text-muted"><UIcon name="i-lucide-tags" class="size-4" />{{ t("cs.spareParts.priceLists") }}</span>
          <div class="min-w-0 overflow-x-auto">
            <UTabs :model-value="listId ?? undefined" :items="listTabs" value-key="value" variant="pill" size="sm" :content="false" class="w-max" @update:model-value="setList" />
          </div>
          <UButton v-if="canCreate || canEdit || canDelete" icon="i-lucide-settings-2" size="xs" color="neutral" variant="outline" :label="t('cs.spareParts.manageLists')" @click="listsOpen = true" />
        </div>

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
                <td class="whitespace-nowrap px-4 py-3 text-end font-semibold">
                  {{ money(priceOf(p)) }}
                  <KBadge v-if="!isDefaultList && ownPrice(p) === undefined" :label="t('cs.spareParts.defaultPrice')" tone="neutral" class="ms-1" />
                </td>
                <td v-if="canEdit || canDelete" class="px-4 py-3">
                  <div class="flex items-center justify-end gap-1">
                    <UButton v-if="canEdit" icon="i-lucide-pencil" color="neutral" variant="ghost" size="xs" :aria-label="t('common.edit')" @click="openEdit(p)" />
                    <UButton v-if="canDelete && isDefaultList" icon="i-lucide-trash-2" color="error" variant="ghost" size="xs" :aria-label="t('common.delete')" @click="askDelete(p)" />
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
      <UFormField v-if="!priceOnly" :label="t('cs.spareParts.name')" required>
        <UInput v-model="name" class="w-full" autofocus />
      </UFormField>
      <p v-else class="text-sm font-medium text-highlighted">{{ editing?.name }} <span class="text-muted">· {{ currentList?.name }}</span></p>
      <UFormField :label="t('cs.spareParts.price')" required>
        <UInputNumber v-model="price" :min="0" class="w-full" />
      </UFormField>
      <UFormField v-if="!priceOnly" :label="t('cs.spareParts.notes')">
        <UTextarea v-model="notes" :rows="2" class="w-full" />
      </UFormField>
    </div>
    <template #actions>
      <UButton v-if="priceOnly && editing && ownPrice(editing) !== undefined" color="neutral" variant="ghost" :label="t('cs.spareParts.useDefaultPrice')" :loading="saving" @click="useDefaultPrice" />
      <UButton color="neutral" variant="outline" :label="t('common.cancel')" @click="closeForm" />
      <UButton :label="t('common.save')" :loading="saving" :disabled="!valid" @click="save" />
    </template>
  </KDialog>

  <KDialog v-model:open="listsOpen" :title="t('cs.spareParts.manageLists')">
    <div class="space-y-3">
      <ul class="space-y-2">
        <li v-for="l in lists" :key="l.id" class="flex items-center gap-2">
          <UInput :model-value="renaming[l.id] ?? l.name" :disabled="!canEdit" class="min-w-0 flex-1" @update:model-value="(v: string | number) => (renaming[l.id] = String(v))" @blur="renameList(l)" @keydown.enter="renameList(l)" />
          <KBadge v-if="l.is_default" :label="t('cs.spareParts.defaultList')" tone="primary" />
          <UButton v-else-if="canDelete" icon="i-lucide-trash-2" color="error" variant="ghost" size="xs" :aria-label="t('common.delete')" @click="deleteList(l)" />
        </li>
      </ul>
      <div v-if="canCreate" class="flex items-center gap-2 border-t border-default pt-3">
        <UInput v-model="newListName" :placeholder="t('cs.spareParts.newListName')" class="min-w-0 flex-1" @keydown.enter="addList" />
        <UButton icon="i-lucide-plus" :label="t('cs.spareParts.add')" :loading="listBusy" :disabled="!newListName.trim()" @click="addList" />
      </div>
      <p class="text-xs text-muted">{{ t("cs.spareParts.listsHint") }}</p>
    </div>
    <template #actions>
      <UButton color="neutral" variant="outline" :label="t('common.close')" @click="listsOpen = false" />
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
