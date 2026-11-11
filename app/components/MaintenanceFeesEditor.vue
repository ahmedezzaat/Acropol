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
  // the discount set when the visit was confirmed
  initialDiscount?: number | null;
  // whether it was chosen as a tax invoice when the visit was confirmed
  initialTaxInvoice?: boolean;
  // mark the parts and the fee as required (the dialog will not save without them)
  required?: boolean;
  // the visit fee is entered once per visit: off for the visit's other products
  showFee?: boolean;
  // before the visit (at confirmation): parts are what should be replaced, the total is an estimate
  planning?: boolean;
  // the price list the parts are priced from (none: the default list, the individual customers')
  priceListId?: string | null;
  // the price of each part can be changed here (for this order only)
  editablePrices?: boolean;
}>(), { showFee: true });
const model = defineModel<FeesState>({ required: true });

const supabase = useSupabaseClient();
const { t } = useI18n();

const lines = ref<FeePart[]>([]);
const fee = ref<number | null>(null);
// a discount on the total: typed as money or as a percentage of the total before it
const discountInput = ref<number | null>(null);
const discountMode = ref<"amount" | "percent">("amount");
const taxInvoice = ref(false);
const feeFromArea = ref(false);
const noParts = ref(false);
const search = ref("");
const loaded = ref(false);
// the parts' prices in the chosen list (parts it does not price use their own default price)
const basePrice = new Map<string, number>();
const listPrices = ref<Map<string, number>>(new Map());
async function loadListPrices() {
  listPrices.value = new Map();
  const id = props.priceListId;
  if (!id) return;
  const { data: list } = await supabase.from("spare_part_price_lists").select("is_default").eq("id", id).maybeSingle();
  if (list?.is_default) return;
  const { data } = await supabase.from("spare_part_prices").select("spare_part_id, price").eq("price_list_id", id);
  listPrices.value = new Map((data ?? []).map((r) => [r.spare_part_id as string, Number(r.price)]));
}
const listPriceOf = (id: string) => listPrices.value.get(id) ?? basePrice.get(id) ?? 0;
const isEdited = (p: FeePart) => basePrice.has(p.id) && p.price !== listPriceOf(p.id);
function setPrice(p: FeePart, v: number | null) {
  p.price = v ?? 0;
}
// another list was chosen: every part takes that list's price
watch(
  () => props.priceListId,
  async () => {
    if (!loaded.value) return;
    await loadListPrices();
    for (const l of lines.value) if (basePrice.has(l.id)) l.price = listPriceOf(l.id);
  },
);

const money = (v: number) => `${v.toLocaleString("en-US")} ${t("common.currency")}`;

watch(
  () => props.active,
  (isActive) => {
    if (!isActive) return;
    lines.value = [];
    fee.value = props.initialFee ?? null;
    discountInput.value = props.initialDiscount ?? null;
    discountMode.value = "amount";
    taxInvoice.value = props.initialTaxInvoice ?? false;
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
  basePrice.clear();
  await loadListPrices();
  if (product.category_id) {
    const { data } = await supabase.from("spare_parts").select("id, name, price").eq("category_id", product.category_id).order("name");
    for (const p of data ?? []) basePrice.set(p.id, Number(p.price));
    // a price set when the visit was confirmed (maybe changed by hand) is kept; otherwise the list's price
    catalog = (data ?? []).map((p) => ({ id: p.id, name: p.name, price: stored.get(p.id)?.price ?? listPriceOf(p.id), qty: stored.get(p.id)?.qty ?? 0 }));
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
const subtotal = computed(() => partsTotal.value + (fee.value ?? 0));
// never more than the total itself
const discount = computed(() => {
  const typed = Math.max(0, discountInput.value ?? 0);
  const amount = discountMode.value === "percent" ? Math.round(subtotal.value * Math.min(100, typed)) / 100 : typed;
  return Math.min(subtotal.value, amount);
});
const net = computed(() => Math.max(0, subtotal.value - discount.value));
// a tax invoice adds the tax on what is left after the discount
const tax = computed(() => (taxInvoice.value ? Math.round(net.value * TAX_RATE * 100) / 100 : 0));
const total = computed(() => net.value + tax.value);
const discountItems = computed(() => [
  { label: t("common.currency"), value: "amount" },
  { label: "%", value: "percent" },
]);

watch(used, (list) => {
  if (list.length) noParts.value = false;
});

watch(
  [used, fee, total, discount, taxInvoice, noParts, loaded, lines],
  () => {
    model.value = {
      parts: used.value.map((p) => ({ ...p })),
      fee: fee.value,
      discount: discount.value > 0 ? discount.value : null,
      taxInvoice: taxInvoice.value,
      tax: tax.value,
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
              <div v-if="editablePrices" class="mt-1 flex items-center gap-1.5">
                <UInputNumber :model-value="p.price" :min="0" size="xs" :aria-label="t('cs.maintenance.partPrice')" class="w-28" @update:model-value="(v: number | null) => setPrice(p, v)" />
                <span class="text-xs text-muted">{{ t("common.currency") }}</span>
                <KBadge v-if="isEdited(p)" :label="t('cs.maintenance.priceEdited')" tone="warning" />
              </div>
              <div v-else class="text-xs text-muted">{{ money(p.price) }}</div>
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

    <!-- A discount on the total (entered once per visit, with the visit fee) -->
    <UFormField v-if="showFee" :label="t('cs.maintenance.discount')" :help="discountMode === 'percent' && discount > 0 ? money(discount) : undefined">
      <div class="flex items-center gap-2">
        <UInputNumber v-model="discountInput" :min="0" :max="discountMode === 'percent' ? 100 : undefined" class="flex-1" />
        <USelect v-model="discountMode" :items="discountItems" value-key="value" class="w-28" />
      </div>
    </UFormField>

    <!-- فاتورة ضريبية: adds the tax to the total (chosen once per visit) -->
    <UCheckbox v-if="showFee" v-model="taxInvoice" :label="t('cs.maintenance.taxInvoice', { rate: Math.round(TAX_RATE * 100) })" />

    <dl class="space-y-1 rounded-[10px] bg-muted p-3 text-sm">
      <div v-if="showFee" class="flex justify-between"><dt class="text-muted">{{ t("cs.maintenance.visitCost") }}</dt><dd>{{ money(fee ?? 0) }}</dd></div>
      <div class="flex justify-between"><dt class="text-muted">{{ t("cs.maintenance.partsTotal") }}</dt><dd>{{ money(partsTotal) }}</dd></div>
      <div v-if="discount > 0" class="flex justify-between"><dt class="text-muted">{{ t("cs.maintenance.beforeDiscount") }}</dt><dd>{{ money(subtotal) }}</dd></div>
      <div v-if="discount > 0" class="flex justify-between text-success"><dt>{{ t("cs.maintenance.discount") }}</dt><dd>− {{ money(discount) }}</dd></div>
      <div v-if="tax > 0" class="flex justify-between"><dt class="text-muted">{{ t("cs.maintenance.taxLine", { rate: Math.round(TAX_RATE * 100) }) }}</dt><dd>+ {{ money(tax) }}</dd></div>
      <div class="flex justify-between border-t border-default pt-1 text-base font-semibold text-highlighted"><dt>{{ t(planning ? "cs.maintenance.finalFeesPlanned" : "cs.maintenance.finalFees") }}</dt><dd>{{ money(total) }}</dd></div>
    </dl>
  </div>
</template>
