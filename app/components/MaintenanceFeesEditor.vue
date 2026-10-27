<script setup lang="ts">
// The spare parts (with quantity and the price as set), the visit fee and the total
// of a maintenance visit. Used when a visit is confirmed and again when it is marked
// done: the second time it starts from what was set at confirmation, and can be changed.
const props = withDefaults(defineProps<{
  product: CsProduct | null;
  // loads (and resets) when it turns true — the dialog opening
  active: boolean;
  initialParts?: FeePart[] | null;
  initialFee?: number | null;
  // mark the parts and the fee as required (the dialog will not save without them)
  required?: boolean;
  // the visit fee is entered once per visit: off for the visit's other products
  showFee?: boolean;
  // before the visit (at confirmation): parts are what should be replaced, the total is an estimate
  planning?: boolean;
}>(), { showFee: true });
const model = defineModel<FeesState>({ required: true });

const supabase = useSupabaseClient();
const { t } = useI18n();

const lines = ref<FeePart[]>([]);
const fee = ref<number | null>(null);
const feeFromArea = ref(false);
const noParts = ref(false);
const search = ref("");
const loaded = ref(false);

const money = (v: number) => `${v.toLocaleString("en-US")} ${t("common.currency")}`;

watch(
  () => props.active,
  (isActive) => {
    if (!isActive) return;
    lines.value = [];
    fee.value = props.initialFee ?? null;
    feeFromArea.value = false;
    noParts.value = false;
    search.value = "";
    loaded.value = false;
    load();
  },
  { immediate: true },
);

async function load() {
  const product = props.product;
  if (!product) return;
  const stored = new Map((props.initialParts ?? []).map((p) => [p.id, p]));
  let catalog: FeePart[] = [];
  if (product.category_id) {
    const { data } = await supabase.from("spare_parts").select("id, name, price").eq("category_id", product.category_id).order("name");
    catalog = (data ?? []).map((p) => ({ id: p.id, name: p.name, price: Number(p.price), qty: stored.get(p.id)?.qty ?? 0 }));
  }
  // a part set at confirmation that no longer exists in the list stays, as it was set
  for (const p of stored.values()) if (!catalog.some((c) => c.id === p.id)) catalog.push({ ...p });
  lines.value = catalog;
  loaded.value = true;

  if (props.showFee && fee.value === null) {
    const { data: customer } = await supabase.from("customers").select("area_id").eq("id", product.customer_id).maybeSingle();
    if (customer?.area_id) {
      const { data } = await supabase.from("area_visit_costs").select("cost").eq("area_id", customer.area_id).maybeSingle();
      // only when the person hasn't typed a fee in the meantime
      if (data && fee.value === null) {
        fee.value = Number(data.cost);
        feeFromArea.value = true;
      }
    }
  }
}

const shown = computed(() => {
  const q = search.value.trim().toLowerCase();
  return q ? lines.value.filter((p) => p.name.toLowerCase().includes(q) || p.qty > 0) : lines.value;
});
const used = computed(() => lines.value.filter((p) => p.qty > 0));
const partsTotal = computed(() => used.value.reduce((n, p) => n + p.price * p.qty, 0));
const total = computed(() => partsTotal.value + (fee.value ?? 0));

watch(used, (list) => {
  if (list.length) noParts.value = false;
});

watch(
  [used, fee, total, noParts, loaded, lines],
  () => {
    model.value = {
      parts: used.value.map((p) => ({ ...p })),
      fee: fee.value,
      total: total.value,
      checked: loaded.value && (!lines.value.length || used.value.length > 0 || noParts.value),
      loaded: loaded.value,
    };
  },
  { immediate: true, deep: true },
);

function setQty(p: FeePart, v: number | null) {
  p.qty = v ?? 0;
}
</script>

<template>
  <div class="space-y-4">
    <!-- Spare parts -->
    <div class="space-y-2">
      <div class="flex items-center justify-between gap-2">
        <p class="text-sm font-medium text-highlighted">{{ t(planning ? "cs.maintenance.sparePartsPlanned" : "cs.maintenance.sparePartsUsed") }} <span v-if="required" class="text-error">*</span></p>
        <UInput v-if="lines.length > 8" v-model="search" icon="i-lucide-search" size="sm" :placeholder="t('cs.maintenance.filterParts')" class="w-44" />
      </div>
      <p v-if="loaded && !lines.length" class="text-xs text-muted">{{ t("cs.maintenance.noSparePartsDefined") }}</p>
      <template v-else>
        <ul class="max-h-64 divide-y divide-default overflow-y-auto border border-default">
          <li v-for="p in shown" :key="p.id" class="flex items-center justify-between gap-3 px-3 py-2">
            <div class="min-w-0">
              <div class="truncate text-sm font-medium text-highlighted">{{ p.name }}</div>
              <div class="text-xs text-muted">{{ money(p.price) }}</div>
            </div>
            <UInputNumber :model-value="p.qty" :min="0" size="sm" :aria-label="t('cs.maintenance.partQty')" class="w-28 shrink-0" @update:model-value="(v: number | null) => setQty(p, v)" />
          </li>
        </ul>
        <UCheckbox v-if="!planning" v-model="noParts" :disabled="used.length > 0" :label="t('cs.maintenance.noPartsUsed')" />
      </template>
    </div>

    <UFormField v-if="showFee" :label="t('cs.maintenance.visitCost')" :help="feeFromArea ? t('cs.visitCosts.applied') : undefined" :required="required">
      <UInputNumber v-model="fee" :min="0" class="w-full" />
    </UFormField>

    <dl class="space-y-1 rounded-[10px] bg-muted p-3 text-sm">
      <div v-if="showFee" class="flex justify-between"><dt class="text-muted">{{ t("cs.maintenance.visitCost") }}</dt><dd>{{ money(fee ?? 0) }}</dd></div>
      <div class="flex justify-between"><dt class="text-muted">{{ t("cs.maintenance.partsTotal") }}</dt><dd>{{ money(partsTotal) }}</dd></div>
      <div class="flex justify-between border-t border-default pt-1 text-base font-semibold text-highlighted"><dt>{{ t(planning ? "cs.maintenance.finalFeesPlanned" : "cs.maintenance.finalFees") }}</dt><dd>{{ money(total) }}</dd></div>
    </dl>
  </div>
</template>
