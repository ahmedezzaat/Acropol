<script setup lang="ts">
// One quotation (عرض سعر), new (/cs/quotations/new, optionally ?customer=<id>) or existing: the customer, the price
// list the parts are priced from, the lines (spare parts and free lines), discount, tax invoice, dates, notes, status.
definePageMeta({ layout: "dashboard", crmPermission: { module: "cs_customers" } });
useHead({ htmlAttrs: { class: "carbon kords" } });

const route = useRoute();
const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

const routeId = route.params.id as string;
const isNew = routeId === "new";
const quotationId = ref<string | null>(isNew ? null : routeId);

// ---- what can be picked: price lists and spare parts (with each list's prices)
interface Part { id: string; name: string; price: number; category_id: string | null }
const { data: lists } = await useAsyncData("cs-quotation-lists", async () => {
  const { data } = await supabase.from("spare_part_price_lists").select("id, name, is_default").order("sort_order").order("created_at");
  return (data ?? []) as { id: string; name: string; is_default: boolean }[];
});
const { data: parts } = await useAsyncData("cs-quotation-parts", async () => {
  const { data } = await supabase.from("spare_parts").select("id, name, price, category_id").order("name");
  return ((data ?? []) as Part[]).map((p) => ({ ...p, price: Number(p.price) }));
});
const { data: listPrices } = await useAsyncData("cs-quotation-prices", async () => {
  const { data } = await supabase.from("spare_part_prices").select("price_list_id, spare_part_id, price");
  return (data ?? []).map((r) => ({ list: r.price_list_id as string, part: r.spare_part_id as string, price: Number(r.price) }));
});
const { data: categories } = await useAsyncData("cs-quotation-categories", async () => {
  const { data } = await supabase.from("product_categories").select("id, name");
  return Object.fromEntries((data ?? []).map((c) => [c.id as string, c.name as string]));
});
const defaultListId = computed(() => lists.value?.find((l) => l.is_default)?.id ?? lists.value?.[0]?.id ?? null);
// a part's price in the chosen list (the default list, or a list without its own price, uses the part's price)
function priceOf(partId: string, listId: string | null) {
  const part = parts.value?.find((p) => p.id === partId);
  const own = listId ? listPrices.value?.find((x) => x.list === listId && x.part === partId)?.price : undefined;
  return own ?? part?.price ?? 0;
}

// ---- the customer: found by name, company or phone
interface Option { label: string; value: string }
const customerOptions = ref<Option[]>([]);
const customerSearch = ref("");
function customerLabel(c: { name: string; company: string | null; phone: string | null }) {
  return [c.company, c.name, c.phone].filter(Boolean).join(" · ");
}
// ---- the quotation
const customerId = ref<string | null>(null);
const statusValue = ref<QuotationStatus>("draft");
const priceListId = ref<string | null>(null);
const issueDate = ref(new Date().toISOString().slice(0, 10));
const validUntil = ref("");
const notes = ref("");
const taxInvoice = ref(false);
const discountInput = ref<number | null>(null);
const discountMode = ref<"amount" | "percent">("amount");
const lines = ref<QuotationLine[]>([]);
const number = ref("");
const loaded = ref(isNew);

if (!isNew) {
  const { data: q } = await supabase.from("cs_quotations").select("*, customer:customers(id, name, company, phone)").eq("id", routeId).maybeSingle();
  const { data: items } = await supabase.from("cs_quotation_items").select("spare_part_id, description, qty, unit_price").eq("quotation_id", routeId).order("sort_order");
  if (q) {
    number.value = q.number as string;
    customerId.value = q.customer_id as string;
    statusValue.value = q.status as QuotationStatus;
    priceListId.value = (q.price_list_id as string | null) ?? null;
    issueDate.value = q.issue_date as string;
    validUntil.value = (q.valid_until as string | null) ?? "";
    notes.value = (q.notes as string | null) ?? "";
    taxInvoice.value = !!q.tax_invoice;
    discountInput.value = Number(q.discount) || null;
    lines.value = (items ?? []).map((i) => ({ spare_part_id: i.spare_part_id as string | null, description: i.description as string, qty: Number(i.qty), unit_price: Number(i.unit_price) }));
    const c = q.customer as { id: string; name: string; company: string | null; phone: string | null } | null;
    if (c) customerOptions.value = [{ label: customerLabel(c), value: c.id }];
    loaded.value = true;
  }
} else {
  // valid for two weeks by default
  const d = new Date();
  d.setDate(d.getDate() + 14);
  validUntil.value = d.toISOString().slice(0, 10);
  priceListId.value = defaultListId.value;
}

let timer: ReturnType<typeof setTimeout> | undefined;
watch(customerSearch, (q) => {
  clearTimeout(timer);
  timer = setTimeout(async () => {
    const term = q.trim();
    let query = supabase.from("customers").select("id, name, company, phone").eq("cs_pending", false).order("created_at", { ascending: false }).limit(20);
    if (term) query = query.or(`name.ilike.%${term}%,company.ilike.%${term}%,phone.ilike.%${term}%`);
    const { data } = await query;
    const found = (data ?? []).map((c) => ({ label: customerLabel(c as never), value: c.id as string }));
    const chosen = customerOptions.value.find((o) => o.value === customerId.value);
    customerOptions.value = chosen && !found.some((o) => o.value === chosen.value) ? [chosen, ...found] : found;
  }, 250);
});
onMounted(async () => {
  customerSearch.value = " ";
  customerSearch.value = "";
  // arriving from a customer (?customer=<id>)
  const pre = typeof route.query.customer === "string" ? route.query.customer : null;
  if (isNew && pre) {
    const { data: c } = await supabase.from("customers").select("id, name, company, phone, price_list_id").eq("id", pre).maybeSingle();
    if (c) {
      customerOptions.value = [{ label: customerLabel(c as never), value: c.id as string }];
      customerId.value = c.id as string;
    }
  }
});
// a new quotation takes the customer's own price list
watch(customerId, async (id, before) => {
  if (!isNew || !id || id === before) return;
  const { data } = await supabase.from("customers").select("price_list_id").eq("id", id).maybeSingle();
  const own = (data as { price_list_id?: string | null } | null)?.price_list_id;
  if (own) priceListId.value = own;
});
// Choosing a price list puts every spare part of that list on the quotation (at the list's price): the default
// list has all the parts, another list the parts it prices. The free lines stay; parts can then be removed.
function partsOfList(listId: string | null) {
  const list = lists.value?.find((l) => l.id === listId);
  if (!list || list.is_default) return parts.value ?? [];
  const priced = new Set((listPrices.value ?? []).filter((x) => x.list === listId).map((x) => x.part));
  return (parts.value ?? []).filter((p) => priced.has(p.id));
}
function fillFromList(listId: string | null) {
  const free = lines.value.filter((l) => !l.spare_part_id);
  lines.value = [...partsOfList(listId).map((p) => ({ spare_part_id: p.id, description: p.name, qty: 1, unit_price: priceOf(p.id, listId) })), ...free];
}
watch(priceListId, (listId, before) => {
  if (!loaded.value || listId === before) return;
  fillFromList(listId);
});
// a new quotation starts with the parts of its list
onMounted(() => {
  if (isNew && !lines.value.length) fillFromList(priceListId.value);
});

// ---- lines
const partItems = computed(() =>
  (parts.value ?? []).map((p) => ({ label: p.category_id && categories.value?.[p.category_id] ? `${p.name} · ${categories.value[p.category_id]}` : p.name, value: p.id })),
);
const partToAdd = ref<string | undefined>(undefined);
watch(partToAdd, (id) => {
  if (!id) return;
  const p = parts.value?.find((x) => x.id === id);
  if (p) lines.value.push({ spare_part_id: p.id, description: p.name, qty: 1, unit_price: priceOf(p.id, priceListId.value) });
  nextTick(() => (partToAdd.value = undefined));
});
function addFreeLine() {
  lines.value.push({ spare_part_id: null, description: "", qty: 1, unit_price: 0 });
}
function removeLine(i: number) {
  lines.value.splice(i, 1);
}
// several lines removed at once: tick them, then "remove the ticked"
const ticked = ref<Set<number>>(new Set());
watch(() => lines.value.length, () => (ticked.value = new Set()));
const allTicked = computed(() => lines.value.length > 0 && ticked.value.size === lines.value.length);
function toggleTick(i: number) {
  const next = new Set(ticked.value);
  if (next.has(i)) next.delete(i);
  else next.add(i);
  ticked.value = next;
}
function toggleAll() {
  ticked.value = allTicked.value ? new Set() : new Set(lines.value.map((_, i) => i));
}
function removeTicked() {
  lines.value = lines.value.filter((_, i) => !ticked.value.has(i));
}
const listPriceChanged = (l: QuotationLine) => !!l.spare_part_id && l.unit_price !== priceOf(l.spare_part_id, priceListId.value);

// ---- totals (the database works them out again when saving)
const subtotalRaw = computed(() => lines.value.reduce((n, l) => n + (l.qty ?? 0) * (l.unit_price ?? 0), 0));
const discountAmount = computed(() => {
  const typed = Math.max(0, discountInput.value ?? 0);
  return discountMode.value === "percent" ? Math.round(subtotalRaw.value * Math.min(100, typed)) / 100 : typed;
});
const totals = computed(() => quotationTotals(lines.value, discountAmount.value, taxInvoice.value));
const money = (v: number) => formatReportMoney(v, t("common.currency"));

// ---- save / delete
const listItems = computed(() => (lists.value ?? []).map((l) => ({ label: l.name, value: l.id })));
const statusItems = computed(() => QUOTATION_STATUSES.map((s) => ({ label: t(`cs.quotations.status.${s}`), value: s })));
const discountItems = computed(() => [
  { label: t("common.currency"), value: "amount" },
  { label: "%", value: "percent" },
]);
const valid = computed(() => !!customerId.value && lines.value.length > 0 && lines.value.every((l) => l.description.trim() && (l.qty ?? 0) > 0 && (l.unit_price ?? 0) >= 0));
const saving = ref(false);
async function save() {
  if (!valid.value) return;
  saving.value = true;
  const { data, error } = await supabase.rpc("cs_save_quotation", {
    p_id: quotationId.value as never,
    p_quotation: {
      customer_id: customerId.value,
      status: statusValue.value,
      price_list_id: priceListId.value,
      issue_date: issueDate.value,
      valid_until: validUntil.value || null,
      discount: totals.value.discount,
      tax_invoice: taxInvoice.value,
      notes: notes.value,
    } as never,
    p_items: lines.value.map((l) => ({ spare_part_id: l.spare_part_id, description: l.description.trim(), qty: l.qty, unit_price: l.unit_price ?? 0 })) as never,
  });
  saving.value = false;
  if (error) {
    toast.add({ title: t("cs.quotations.saveFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("cs.quotations.saved"), color: "success" });
  if (!quotationId.value) {
    await navigateTo(`/cs/quotations/${data as string}`, { replace: true });
    return;
  }
  const { data: q } = await supabase.from("cs_quotations").select("number").eq("id", quotationId.value).maybeSingle();
  if (q) number.value = q.number as string;
}
const deleteOpen = ref(false);
const deleting = ref(false);
async function remove() {
  if (!quotationId.value) return;
  deleting.value = true;
  const { error } = await supabase.from("cs_quotations").delete().eq("id", quotationId.value);
  deleting.value = false;
  if (error) {
    toast.add({ title: t("cs.quotations.deleteFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("cs.quotations.deleted"), color: "success" });
  navigateTo("/cs/quotations");
}
</script>

<template>
  <UDashboardPanel :ui="{ body: 'kords-canvas !p-3 sm:!p-6' }">
    <template #header>
      <UDashboardNavbar :title="number ? `${t('cs.quotations.one')} ${number}` : t('cs.quotations.new')">
        <template #leading><UDashboardSidebarCollapse /></template>
        <template #right>
          <UButton to="/cs/quotations" icon="i-lucide-arrow-right" color="neutral" variant="ghost" :label="t('cs.quotations.title')" />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <p v-if="!isNew && !loaded" class="kords-card mx-auto max-w-xl p-8 text-center text-sm text-muted">{{ t("cs.quotations.notFound") }}</p>
      <div v-else class="mx-auto w-full max-w-5xl space-y-5">
        <!-- who, which list, when, status -->
        <section class="kords-card space-y-4 p-4 sm:p-5">
          <div class="grid gap-3 sm:grid-cols-2">
            <UFormField :label="t('cs.quotations.customer')" required>
              <USelectMenu v-model="customerId" v-model:search-term="customerSearch" :items="customerOptions" value-key="value" :ignore-filter="true" icon="i-lucide-user-round" :placeholder="t('cs.quotations.pickCustomer')" class="w-full">
                <template #empty>{{ t("crm.contracts.noCustomers") }}</template>
              </USelectMenu>
            </UFormField>
            <UFormField :label="t('cs.quotations.priceList')" :help="t('cs.quotations.priceListFill')">
              <USelect v-model="priceListId" :items="listItems" value-key="value" icon="i-lucide-tags" class="w-full" />
            </UFormField>
            <UFormField :label="t('cs.quotations.issueDate')"><UInput v-model="issueDate" type="date" class="w-full" /></UFormField>
            <UFormField :label="t('cs.quotations.validUntil')"><UInput v-model="validUntil" type="date" class="w-full" /></UFormField>
          </div>
          <UFormField :label="t('cs.quotations.statusLabel')">
            <div class="flex flex-wrap gap-1.5">
              <button v-for="s in statusItems" :key="s.value" type="button" class="kords-chip" :class="statusValue === s.value && 'kords-chip-on'" @click="statusValue = s.value">{{ s.label }}</button>
            </div>
          </UFormField>
        </section>

        <!-- the lines -->
        <section class="kords-card space-y-3 p-4 sm:p-5">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h3 class="text-sm font-semibold text-highlighted">{{ t("cs.quotations.lines") }}</h3>
            <div class="flex flex-wrap items-center gap-2">
              <USelectMenu v-model="partToAdd" :items="partItems" value-key="value" icon="i-lucide-wrench" :placeholder="t('cs.quotations.addPart')" class="w-64" />
              <UButton icon="i-lucide-plus" color="neutral" variant="outline" size="sm" :label="t('cs.quotations.addFree')" @click="addFreeLine" />
              <UButton v-if="ticked.size" icon="i-lucide-trash-2" color="error" variant="soft" size="sm" :label="t('cs.quotations.removeTicked', { n: ticked.size })" @click="removeTicked" />
            </div>
          </div>
          <p v-if="!lines.length" class="rounded-[10px] bg-muted p-4 text-center text-sm text-muted">{{ t("cs.quotations.noLines") }}</p>
          <div v-else class="overflow-x-auto">
            <table class="w-full min-w-[40rem] text-sm">
              <thead>
                <tr class="border-b border-default text-xs text-muted">
                  <th class="w-8 px-2 py-2"><UCheckbox :model-value="allTicked" :aria-label="t('cs.quotations.tickAll')" @update:model-value="toggleAll" /></th>
                  <th class="px-2 py-2 text-start font-medium">{{ t("cs.quotations.description") }}</th>
                  <th class="w-28 px-2 py-2 text-start font-medium">{{ t("cs.quotations.qty") }}</th>
                  <th class="w-36 px-2 py-2 text-start font-medium">{{ t("cs.quotations.unitPrice") }}</th>
                  <th class="w-32 px-2 py-2 text-end font-medium">{{ t("cs.quotations.lineTotal") }}</th>
                  <th class="w-10" />
                </tr>
              </thead>
              <tbody class="divide-y divide-default">
                <tr v-for="(l, i) in lines" :key="i" :class="ticked.has(i) && 'bg-error/5'">
                  <td class="px-2 py-2"><UCheckbox :model-value="ticked.has(i)" @update:model-value="toggleTick(i)" /></td>
                  <td class="px-2 py-2">
                    <UInput v-model="l.description" class="w-full" :placeholder="t('cs.quotations.freePlaceholder')" />
                    <span class="mt-1 block text-xs text-muted">{{ l.spare_part_id ? t("cs.quotations.partLine") : t("cs.quotations.freeLine") }}<template v-if="listPriceChanged(l)"> · {{ t("cs.quotations.priceChanged") }}</template></span>
                  </td>
                  <td class="px-2 py-2"><UInputNumber v-model="l.qty" :min="0" :step="1" class="w-full" /></td>
                  <td class="px-2 py-2"><UInputNumber v-model="l.unit_price" :min="0" class="w-full" /></td>
                  <td class="whitespace-nowrap px-2 py-2 text-end font-medium">{{ money((l.qty ?? 0) * (l.unit_price ?? 0)) }}</td>
                  <td class="px-1 py-2"><UButton icon="i-lucide-trash" color="error" variant="ghost" size="xs" :aria-label="t('common.delete')" @click="removeLine(i)" /></td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <!-- discount, tax, totals, notes -->
        <div class="grid items-start gap-5 lg:grid-cols-2">
          <section class="kords-card space-y-4 p-4 sm:p-5">
            <UFormField :label="t('cs.maintenance.discount')" :help="discountMode === 'percent' && discountAmount > 0 ? money(discountAmount) : undefined">
              <div class="flex items-center gap-2">
                <UInputNumber v-model="discountInput" :min="0" :max="discountMode === 'percent' ? 100 : undefined" class="flex-1" />
                <USelect v-model="discountMode" :items="discountItems" value-key="value" class="w-28" />
              </div>
            </UFormField>
            <UCheckbox v-model="taxInvoice" :label="t('cs.maintenance.taxInvoice', { rate: Math.round(TAX_RATE * 100) })" />
            <UFormField :label="t('cs.quotations.notes')"><UTextarea v-model="notes" :rows="4" :placeholder="t('cs.quotations.notesHint')" class="w-full" /></UFormField>
          </section>
          <section class="kords-card space-y-1 p-4 text-sm sm:p-5">
            <div class="flex justify-between"><span class="text-muted">{{ t("cs.quotations.subtotal") }}</span><span>{{ money(totals.subtotal) }}</span></div>
            <div v-if="totals.discount > 0" class="flex justify-between text-success"><span>{{ t("cs.maintenance.discount") }}</span><span>− {{ money(totals.discount) }}</span></div>
            <div v-if="totals.tax > 0" class="flex justify-between"><span class="text-muted">{{ t("cs.maintenance.taxLine", { rate: Math.round(TAX_RATE * 100) }) }}</span><span>+ {{ money(totals.tax) }}</span></div>
            <div class="flex justify-between border-t border-default pt-2 text-lg font-semibold text-highlighted"><span>{{ t("cs.quotations.total") }}</span><span>{{ money(totals.total) }}</span></div>
            <div class="flex flex-wrap gap-2 pt-4">
              <UButton icon="i-lucide-save" :label="t('common.save')" :loading="saving" :disabled="!valid" class="flex-1 justify-center" @click="save" />
              <UButton v-if="quotationId" :to="`/print/quotation/${quotationId}`" icon="i-lucide-printer" color="neutral" variant="outline" :label="t('cs.quotations.print')" />
              <UButton v-if="quotationId" icon="i-lucide-trash" color="error" variant="outline" :label="t('common.delete')" @click="deleteOpen = true" />
            </div>
          </section>
        </div>
      </div>
    </template>
  </UDashboardPanel>

  <KDeleteConfirmation v-model:open="deleteOpen" :title="t('cs.quotations.deleteTitle')" :message="t('cs.quotations.deleteBody', { number })" :loading="deleting" @confirm="remove" />
</template>
