<script setup lang="ts">
import type { TableColumn } from "@nuxt/ui";
import { getPaginationRowModel } from "@tanstack/vue-table";

definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "cs_customers" },
});

useHead({ htmlAttrs: { class: "carbon" } });

const supabase = useSupabaseClient();
const { t } = useI18n();
const { hasPermission } = usePermissions();
const { areas, pipelines, stagesOf, stageName, stageColor, stageLimitDays, dateIndex, dateOf, daysSince, formatDate, loadAreas, loadPipelines, areaName } = useCs();

// The funnels (التركيبات and any others set up in Settings): every customer's
// product as a list, newest first.
const { data: products, refresh, status } = await useAsyncData<CsProduct[]>("cs-installations", async () => {
  const { data, error } = await supabase
    .from("customer_products")
    .select("*")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as CsProduct[];
});
const { data: stageDates, refresh: refreshDates } = await useAsyncData<CsStageDate[]>("cs-installations-dates", async () => {
  const { data, error } = await supabase.from("customer_product_stage_dates").select("product_id, stage_id, reached_on");
  if (error) throw error;
  return (data ?? []) as CsStageDate[];
});
const dates = computed(() => dateIndex(stageDates.value ?? []));

const { data: customers } = await useAsyncData<CsCustomer[]>("cs-installations-customers", async () => {
  const { data, error } = await supabase.from("customers").select("id, name, company, phone, email, address, area_id");
  if (error) throw error;
  return (data ?? []) as CsCustomer[];
});
const { data: categories } = await useAsyncData<{ id: string; name: string }[]>("cs-installations-categories", async () => {
  const { data } = await supabase.from("product_categories").select("id, name");
  return data ?? [];
});
await useAsyncData("cs-installations-meta", async () => {
  await Promise.all([loadAreas(true), loadPipelines(true)]);
  return true;
});

const activePipelineId = ref<string | undefined>(pipelines.value[0]?.id);
const pipelineTabs = computed(() => pipelines.value.map((p) => ({ label: p.name, value: p.id })));
const activeStages = computed(() => stagesOf(activePipelineId.value));

const search = ref("");
const areaFilter = ref<string | null>(null);
const stageFilter = ref<string | null>(null);
watch(activePipelineId, () => (stageFilter.value = null));
const stageItems = computed(() => [
  { label: t("cs.customers.allStages"), value: null },
  ...activeStages.value.map((s) => ({ label: s.name, value: s.id })),
]);
const areaItems = computed(() => [
  { label: t("cs.customers.allAreas"), value: null },
  ...areas.value.map((a) => ({ label: a.name, value: a.id })),
]);

function customerOf(id: string) {
  return customers.value?.find((c) => c.id === id);
}

// Product category chips (multi-select): none picked = every category. "none" is
// the products without a category.
const categoryFilter = ref<string[]>([]);
function toggleCategory(id: string) {
  categoryFilter.value = categoryFilter.value.includes(id) ? categoryFilter.value.filter((x) => x !== id) : [...categoryFilter.value, id];
}
watch(activePipelineId, () => (categoryFilter.value = []));

// Everything except the category filter, so each chip can show its own count.
const beforeCategory = computed(() =>
  (products.value ?? []).filter((p) => {
    if (p.pipeline_id !== activePipelineId.value) return false;
    const c = customerOf(p.customer_id);
    if (areaFilter.value && c?.area_id !== areaFilter.value) return false;
    if (viewMode.value === "list" && stageFilter.value && p.stage_id !== stageFilter.value) return false;
    if (search.value) {
      const q = search.value.toLowerCase();
      const hay = `${c?.name ?? ""} ${c?.company ?? ""} ${p.name} ${p.contract_code ?? ""} ${c?.phone ?? ""} ${c?.address ?? ""}`.toLowerCase();
      if (!hay.includes(q)) return false;
    }
    return true;
  }),
);
const filtered = computed(() =>
  categoryFilter.value.length ? beforeCategory.value.filter((p) => categoryFilter.value.includes(p.category_id ?? "none")) : beforeCategory.value,
);
const categoryChips = computed(() => {
  const all = (products.value ?? []).filter((p) => p.pipeline_id === activePipelineId.value);
  const ids = [...new Set(all.map((p) => p.category_id ?? "none"))];
  const named = ids
    .filter((id) => id !== "none")
    .map((id) => ({ id, label: categoryName(id) ?? "—" }))
    .sort((a, b) => a.label.localeCompare(b.label));
  const chips = [...named, ...(ids.includes("none") ? [{ id: "none", label: t("cs.profile.noCategory") }] : [])];
  return chips.map((c) => ({ ...c, count: beforeCategory.value.filter((p) => (p.category_id ?? "none") === c.id).length }));
});

function categoryName(id: string | null) {
  return id ? (categories.value?.find((c) => c.id === id)?.name ?? null) : null;
}

// Days in the current stage, and whether that is past the stage's limit.
function stageDays(p: CsProduct) {
  return daysSince(dateOf(dates.value, p.id, p.stage_id) ?? p.contract_date);
}
function overdue(p: CsProduct) {
  const limit = stageLimitDays(activeStages.value.find((s) => s.id === p.stage_id));
  const days = stageDays(p);
  return limit !== null && days !== null && days > limit;
}

const stageModalOpen = ref(false);
const stageProduct = ref<CsProduct | null>(null);
const stageTarget = ref<string | null>(null);
function openStage(p: CsProduct, targetStageId: string | null = null) {
  stageProduct.value = p;
  stageTarget.value = targetStageId;
  stageModalOpen.value = true;
}

// ---- Drag and drop: drop a card on another stage to move it. The same dialog as
// the Update button opens with that stage chosen, since a stage needs its date.
const canMove = computed(() => hasPermission("cs_customers", "edit"));
const dragId = ref<string | null>(null);
const overStage = ref<string | null>(null);
function onDragStart(e: DragEvent, p: CsProduct) {
  if (!canMove.value) return e.preventDefault();
  dragId.value = p.id;
  e.dataTransfer?.setData("text/plain", p.id);
  if (e.dataTransfer) e.dataTransfer.effectAllowed = "move";
}
function onDragEnd() {
  dragId.value = null;
  overStage.value = null;
}
function onDrop(stageId: string) {
  const p = (products.value ?? []).find((x) => x.id === dragId.value);
  onDragEnd();
  if (p && p.stage_id !== stageId) openStage(p, stageId);
}
async function onStageSaved() {
  await Promise.all([refresh(), refreshDates()]);
}
function openCustomer(id: string) {
  navigateTo(`/cs/customers/${id}`);
}

// ---- View: the list (a table) or the Kanban board (a column per stage).
// Remembered per browser.
const viewMode = ref<"list" | "kanban">("kanban");
onMounted(() => {
  try {
    const saved = localStorage.getItem("cs-installations-view");
    if (saved === "list" || saved === "kanban") viewMode.value = saved;
  } catch {
    /* storage unavailable: keep the default */
  }
});
function setView(mode: "list" | "kanban") {
  viewMode.value = mode;
  try {
    localStorage.setItem("cs-installations-view", mode);
  } catch {
    /* ignore */
  }
}

// ---- Kanban
// Literal class names (not built from a variable) so Tailwind generates them.
const borderByColor = {
  neutral: "border-t-accented",
  info: "border-t-info",
  warning: "border-t-warning",
  primary: "border-t-primary",
  success: "border-t-success",
} as const;
function inStage(stageId: string) {
  return filtered.value.filter((p) => p.stage_id === stageId);
}

function createdOn(p: CsProduct) {
  return formatDate(p.created_at.slice(0, 10));
}

// ---- List
const columns = computed<TableColumn<CsProduct>[]>(() => [
  { id: "customer", header: t("cs.installations.customer") },
  { id: "product", header: t("cs.installations.product") },
  { id: "area", header: t("cs.customers.area") },
  { id: "stage", header: t("cs.installations.stage") },
  { id: "since", header: t("cs.installations.since") },
  { id: "created", header: t("cs.installations.created") },
  { id: "actions", header: "" },
]);
const pagination = ref({ pageIndex: 0, pageSize: 25 });
watch([search, areaFilter, stageFilter, activePipelineId, categoryFilter], () => {
  pagination.value = { ...pagination.value, pageIndex: 0 };
});
const pagedCards = computed(() =>
  filtered.value.slice(pagination.value.pageIndex * pagination.value.pageSize, (pagination.value.pageIndex + 1) * pagination.value.pageSize),
);
</script>

<template>
  <!-- The board is one screen tall so every stage column scrolls on its own. -->
  <UDashboardPanel :ui="viewMode === 'kanban' ? { root: 'h-svh', body: 'kords-canvas' } : { body: 'kords-canvas' }">
    <template #header>
      <KPageHeader :title="t('cs.installations.title')" :count="filtered.length" />

      <div class="kords-filterbar w-full space-y-3 border-b border-default px-4 py-3 sm:px-6">
        <div v-if="pipelines.length > 1" class="-mx-4 overflow-x-auto overflow-y-hidden px-4 [scrollbar-width:none] sm:mx-0 sm:px-0 [&::-webkit-scrollbar]:hidden">
          <UTabs v-model="activePipelineId" :items="pipelineTabs" value-key="value" variant="link" :content="false" class="kords-pilltabs w-max min-w-full" />
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <UInput
            v-model="search"
            icon="i-lucide-search"
            :placeholder="t('cs.installations.search')"
            class="min-w-0 flex-1 basis-56"
          />
          <USelect v-model="areaFilter" :items="areaItems" value-key="value" icon="i-lucide-map-pin" class="w-44" />
          <USelect v-if="viewMode === 'list'" v-model="stageFilter" :items="stageItems" value-key="value" icon="i-lucide-workflow" class="w-44" />
          <UButtonGroup class="ms-auto">
            <UButton
              icon="i-lucide-list"
              :color="viewMode === 'list' ? 'primary' : 'neutral'"
              :variant="viewMode === 'list' ? 'solid' : 'outline'"
              :aria-label="t('cs.installations.listView')"
              @click="setView('list')"
            />
            <UButton
              icon="i-lucide-columns-3"
              :color="viewMode === 'kanban' ? 'primary' : 'neutral'"
              :variant="viewMode === 'kanban' ? 'solid' : 'outline'"
              :aria-label="t('cs.installations.kanbanView')"
              @click="setView('kanban')"
            />
          </UButtonGroup>
        </div>

        <!-- Product category: pick one or several -->
        <div v-if="categoryChips.length" class="-mx-4 flex items-center gap-2 overflow-x-auto px-4 pb-0.5 [scrollbar-width:none] sm:mx-0 sm:px-0 [&::-webkit-scrollbar]:hidden">
          <button type="button" class="kords-chip" :class="!categoryFilter.length && 'kords-chip-on'" @click="categoryFilter = []">
            {{ t("cs.customers.allCategories") }}
          </button>
          <button
            v-for="c in categoryChips"
            :key="c.id"
            type="button"
            class="kords-chip"
            :class="categoryFilter.includes(c.id) && 'kords-chip-on'"
            :aria-pressed="categoryFilter.includes(c.id)"
            @click="toggleCategory(c.id)"
          >
            <UIcon v-if="categoryFilter.includes(c.id)" name="i-lucide-check" class="size-3.5" />
            {{ c.label }}
            <span class="kords-chip-count">{{ c.count }}</span>
          </button>
        </div>
      </div>
    </template>

    <template #body>
      <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>

      <p v-else-if="!filtered.length" class="py-16 text-center text-sm text-muted">{{ t("cs.customers.empty") }}</p>

      <!-- Kanban: a column per stage of the chosen funnel -->
      <div
        v-else-if="viewMode === 'kanban'"
        class="-mx-4 flex min-h-0 flex-1 snap-x snap-mandatory gap-3 overflow-x-auto overflow-y-hidden px-4 pb-2 sm:mx-0 sm:snap-none sm:gap-4 sm:px-0"
      >
        <div
          v-for="stage in activeStages"
          :key="stage.id"
          class="kords-lane flex min-h-0 w-[85vw] shrink-0 snap-center flex-col border border-t-4 border-default bg-muted sm:w-72 sm:snap-align-none"
          :class="[borderByColor[stageColor(stage.id)], dragId && overStage === stage.id && 'ring-2 ring-primary']"
          @dragover.prevent="overStage = stage.id"
          @dragleave="overStage === stage.id && (overStage = null)"
          @drop.prevent="onDrop(stage.id)"
        >
          <div class="flex shrink-0 items-center justify-between gap-2 border-b border-default p-3">
            <span class="truncate font-medium text-highlighted">{{ stage.name }}</span>
            <KBadge :label="String(inStage(stage.id).length)" tone="neutral" />
          </div>

          <div class="min-h-0 flex-1 space-y-2 overflow-y-auto overscroll-contain p-2">
            <div
              v-for="p in inStage(stage.id)"
              :key="p.id"
              class="kords-kcard cursor-pointer border border-default bg-default p-3 text-sm"
              :class="[overdue(p) && 'kords-kcard-late', canMove && 'cursor-grab active:cursor-grabbing', dragId === p.id && 'opacity-50']"
              :draggable="canMove"
              @dragstart="onDragStart($event, p)"
              @dragend="onDragEnd"
              @click="openCustomer(p.customer_id)"
            >
              <div class="truncate font-semibold text-highlighted">{{ customerOf(p.customer_id) ? customerTitle(customerOf(p.customer_id)!) : "—" }}</div>
              <div class="mt-0.5 truncate text-xs text-toned">{{ p.name }}<template v-if="(p.quantity ?? 1) > 1"> × {{ p.quantity }}</template></div>
              <div class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted">
                <span v-if="areaName(customerOf(p.customer_id)?.area_id)" class="flex items-center gap-1">
                  <UIcon name="i-lucide-map-pin" class="size-3.5" />{{ areaName(customerOf(p.customer_id)?.area_id) }}
                </span>
              </div>
              <div class="mt-2 flex items-center justify-between gap-2 text-xs">
                <span class="flex items-center gap-1" :class="overdue(p) ? 'font-medium text-error' : 'text-muted'">
                  <UIcon :name="overdue(p) ? 'i-lucide-triangle-alert' : 'i-lucide-calendar'" class="size-3.5" />
                  {{ formatDate(dateOf(dates, p.id, stage.id)) }}
                  <template v-if="overdue(p)">· {{ t("cs.dashboard.days", { count: stageDays(p) ?? 0 }) }}</template>
                </span>
                <UButton
                  v-if="hasPermission('cs_customers', 'edit')"
                  icon="i-lucide-arrow-left-right"
                  size="xs"
                  color="neutral"
                  variant="soft"
                  :label="t('cs.installations.move')"
                  @click.stop="openStage(p)"
                />
              </div>
            </div>
            <p v-if="!inStage(stage.id).length" class="border border-dashed border-default py-6 text-center text-xs text-muted">
              {{ t("cs.installations.emptyStage") }}
            </p>
          </div>
        </div>
      </div>

      <template v-else>
        <UTable
          v-model:pagination="pagination"
          :data="filtered"
          :columns="columns"
          :pagination-options="{ getPaginationRowModel: getPaginationRowModel() }"
          :ui="{ root: 'kords-card hidden shrink-0 overflow-hidden md:block [&_tbody_tr]:cursor-pointer' }"
          @select="(_e, row) => openCustomer(row.original.customer_id)"
        >
          <template #customer-cell="{ row }">
            <div class="min-w-0">
              <div class="truncate font-medium text-highlighted">
                {{ customerOf(row.original.customer_id) ? customerTitle(customerOf(row.original.customer_id)!) : "—" }}
              </div>
              <bdi v-if="customerOf(row.original.customer_id)?.phone" dir="ltr" class="text-xs text-toned">{{ customerOf(row.original.customer_id)?.phone }}</bdi>
            </div>
          </template>
          <template #product-cell="{ row }">
            <div class="min-w-0">
              <div class="truncate text-sm">{{ row.original.name }}<template v-if="(row.original.quantity ?? 1) > 1"> × {{ row.original.quantity }}</template></div>
              <div class="flex flex-wrap items-center gap-x-2 text-xs text-muted">
                <span v-if="categoryName(row.original.category_id)">{{ categoryName(row.original.category_id) }}</span>
                <bdi v-if="row.original.contract_code" dir="ltr">#{{ row.original.contract_code }}</bdi>
              </div>
            </div>
          </template>
          <template #area-cell="{ row }">
            <span class="text-sm">{{ areaName(customerOf(row.original.customer_id)?.area_id) || "—" }}</span>
          </template>
          <template #stage-cell="{ row }">
            <KBadge :label="stageName(row.original.stage_id)" :tone="stageColor(row.original.stage_id)" />
          </template>
          <template #since-cell="{ row }">
            <span class="flex items-center gap-1 text-sm" :class="overdue(row.original) ? 'font-medium text-error' : 'text-muted'">
              <UIcon v-if="overdue(row.original)" name="i-lucide-triangle-alert" class="size-3.5" />
              {{ formatDate(dateOf(dates, row.original.id, row.original.stage_id)) }}
              <template v-if="overdue(row.original)">· {{ t("cs.dashboard.days", { count: stageDays(row.original) ?? 0 }) }}</template>
            </span>
          </template>
          <template #created-cell="{ row }">
            <span class="text-sm text-muted">{{ createdOn(row.original) }}</span>
          </template>
          <template #actions-cell="{ row }">
            <UButton
              v-if="hasPermission('cs_customers', 'edit')"
              icon="i-lucide-arrow-left-right"
              size="xs"
              color="neutral"
              variant="soft"
              :label="t('cs.installations.move')"
              @click.stop="openStage(row.original)"
            />
          </template>
        </UTable>

        <!-- Phones -->
        <div class="space-y-2 md:hidden">
          <div
            v-for="p in pagedCards"
            :key="p.id"
            class="kords-kcard cursor-pointer border border-default bg-default p-3 text-sm"
            :class="overdue(p) && 'kords-kcard-late'"
            @click="openCustomer(p.customer_id)"
          >
            <div class="flex items-start justify-between gap-2">
              <div class="min-w-0">
                <div class="truncate font-semibold text-highlighted">{{ customerOf(p.customer_id) ? customerTitle(customerOf(p.customer_id)!) : "—" }}</div>
                <div class="mt-0.5 truncate text-xs text-toned">{{ p.name }}<template v-if="(p.quantity ?? 1) > 1"> × {{ p.quantity }}</template></div>
              </div>
              <KBadge :label="stageName(p.stage_id)" :tone="stageColor(p.stage_id)" class="shrink-0" />
            </div>
            <div class="mt-2 flex flex-wrap items-center justify-between gap-2 text-xs">
              <span class="flex items-center gap-1" :class="overdue(p) ? 'font-medium text-error' : 'text-muted'">
                <UIcon :name="overdue(p) ? 'i-lucide-triangle-alert' : 'i-lucide-calendar'" class="size-3.5" />
                {{ formatDate(dateOf(dates, p.id, p.stage_id)) }}
                <template v-if="overdue(p)">· {{ t("cs.dashboard.days", { count: stageDays(p) ?? 0 }) }}</template>
              </span>
              <UButton
                v-if="hasPermission('cs_customers', 'edit')"
                icon="i-lucide-arrow-left-right"
                size="xs"
                color="neutral"
                variant="soft"
                :label="t('cs.installations.move')"
                @click.stop="openStage(p)"
              />
            </div>
          </div>
        </div>

        <div class="mt-3 flex flex-wrap items-center justify-between gap-2 border-t border-default pt-3">
          <span class="text-sm text-muted">{{ t("cs.installations.total", { count: filtered.length }) }}</span>
          <UPagination
            :page="pagination.pageIndex + 1"
            :items-per-page="pagination.pageSize"
            :total="filtered.length"
            :sibling-count="1"
            @update:page="(p: number) => (pagination = { ...pagination, pageIndex: p - 1 })"
          />
        </div>
      </template>
    </template>
  </UDashboardPanel>

  <ProductStageModal v-model:open="stageModalOpen" :product="stageProduct" :initial-stage="stageTarget" @saved="onStageSaved" />
</template>
