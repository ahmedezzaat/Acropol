<script setup lang="ts">
// The technician's view of the Confirmed visits page, made for a phone: cards for yesterday, today (the default)
// and tomorrow — each with the customer, area and the product categories. A card
// opens the full customer, the product details and every past note, with the button
// to mark the visit done.
useHead({ htmlAttrs: { class: "carbon" } });

const supabase = useSupabaseClient();
const me = useSupabaseUser();
const { t, locale } = useI18n();
const { hasPermission } = usePermissions();
const { loadAreas, areaName, formatDateTime } = useCs();

const canComplete = computed(() => hasPermission("cs_maintenance", "complete"));
// "see my confirmed visits" shows only the visits assigned to me; "see all" every one
const seesAll = computed(() => hasPermission("cs_maintenance", "view_confirmed_all"));

type Day = "yesterday" | "today" | "tomorrow";
const day = ref<Day>("today");

const DAY_MS = 86_400_000;
const midnight = (offsetDays: number) => {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() + offsetDays);
  return d;
};
const isoDate = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
const dayOf = (ms: number): Day | null => {
  const today = midnight(0).getTime();
  if (ms >= today - DAY_MS && ms < today) return "yesterday";
  if (ms >= today && ms < today + DAY_MS) return "today";
  if (ms >= today + DAY_MS && ms < today + 2 * DAY_MS) return "tomorrow";
  return null;
};

// ---- Data
interface Category {
  id: string;
  name: string;
}
interface Card {
  key: string;
  customerId: string;
  day: Day;
  at: number;
  done: boolean;
  products: CsProduct[];
}

const loading = ref(true);
const customers = ref<Map<string, CsCustomer>>(new Map());
const categories = ref<Category[]>([]);
const cards = ref<Card[]>([]);

async function load() {
  loading.value = true;
  const from = midnight(-1).toISOString();
  const to = midnight(2).toISOString();
  const scope = seesAll.value ? {} : { maintenance_technician_id: me.value?.sub as string };

  const [pending, cats, doneLogs] = await Promise.all([
    supabase
      .from("customer_products")
      .select("*")
      .not("maintenance_confirmed_at", "is", null)
      .gte("next_maintenance_at", from)
      .lt("next_maintenance_at", to)
      .match(scope)
      .order("next_maintenance_at"),
    supabase.from("product_categories").select("id, name").order("sort_order"),
    // visits finished yesterday and today, so the technician sees what is already done
    supabase
      .from("product_maintenance_log")
      .select("product_id, done_on, technician_id")
      .eq("kind", "done")
      .gte("done_on", isoDate(midnight(-1)))
      .lte("done_on", isoDate(midnight(0)))
      .match(seesAll.value ? {} : { technician_id: me.value?.sub as string }),
    loadAreas(),
  ]);
  categories.value = (cats.data ?? []) as Category[];

  const doneRows = (doneLogs.data ?? []) as { product_id: string; done_on: string; technician_id: string | null }[];
  const doneProductIds = [...new Set(doneRows.map((r) => r.product_id))];
  const doneProducts = doneProductIds.length ? (((await supabase.from("customer_products").select("*").in("id", doneProductIds)).data ?? []) as CsProduct[]) : [];

  const list: Card[] = [];
  const pendingByKey = new Map<string, Card>();
  for (const p of (pending.data ?? []) as CsProduct[]) {
    const at = new Date(p.next_maintenance_at!).getTime();
    const d = dayOf(at);
    if (!d) continue;
    const key = `${p.customer_id}|${d}|todo`;
    const card = pendingByKey.get(key) ?? { key, customerId: p.customer_id, day: d, at, done: false, products: [] };
    card.at = Math.min(card.at, at);
    card.products.push(p);
    pendingByKey.set(key, card);
  }
  list.push(...pendingByKey.values());

  const doneByKey = new Map<string, Card>();
  for (const r of doneRows) {
    const p = doneProducts.find((x) => x.id === r.product_id);
    if (!p) continue;
    const dateMs = new Date(`${r.done_on.slice(0, 10)}T12:00:00`).getTime();
    const d = dayOf(dateMs);
    if (!d || d === "tomorrow") continue;
    const key = `${p.customer_id}|${d}|done`;
    const card = doneByKey.get(key) ?? { key, customerId: p.customer_id, day: d, at: dateMs, done: true, products: [] };
    if (!card.products.some((x) => x.id === p.id)) card.products.push(p);
    doneByKey.set(key, card);
  }
  list.push(...doneByKey.values());

  const customerIds = [...new Set(list.map((c) => c.customerId))];
  const custRows = customerIds.length ? (((await supabase.from("customers").select("id, name, company, customer_type, phone, address, area_id").in("id", customerIds)).data ?? []) as CsCustomer[]) : [];
  customers.value = new Map(custRows.map((c) => [c.id, c]));
  cards.value = list.sort((a, b) => Number(a.done) - Number(b.done) || a.at - b.at);
  loading.value = false;
}
await load();

const dayTabs = computed(() =>
  (["yesterday", "today", "tomorrow"] as const).map((d) => ({
    value: d,
    label: t(`cs.myVisits.${d}`),
    count: cards.value.filter((c) => c.day === d).length,
  })),
);
const shown = computed(() => cards.value.filter((c) => c.day === day.value));
const pendingCount = computed(() => shown.value.filter((c) => !c.done).length);

const clock = (ms: number) => formatClock(new Date(ms), locale.value);
const categoryNames = (c: Card) => [...new Set(c.products.map((p) => categories.value.find((x) => x.id === p.category_id)?.name ?? p.name))];
const titleOf = (id: string) => {
  const c = customers.value.get(id);
  return c ? customerTitle(c) : "—";
};
const areaOf = (id: string) => areaName(customers.value.get(id)?.area_id);

// ---- Details of one visit: full customer, products, every past note
interface NoteRow {
  id: string;
  at: string;
  text: string;
  kind: string;
  product: string;
  by: string | null;
}
const detailOpen = ref(false);
const detailCard = ref<Card | null>(null);
const detailLoading = ref(false);
const detailCustomer = ref<CsCustomer | null>(null);
const allProducts = ref<CsProduct[]>([]);
const items = ref<CsProductItem[]>([]);
const notes = ref<NoteRow[]>([]);

const detailProducts = computed(() => (detailCard.value ? allProducts.value.filter((p) => detailCard.value!.products.some((v) => v.id === p.id)) : []));
const otherProducts = computed(() => (detailCard.value ? allProducts.value.filter((p) => !detailCard.value!.products.some((v) => v.id === p.id)) : []));

const kindLabel = (k: string) =>
  ({
    done: "evDone",
    note: "evNote",
    scheduled: "evScheduled",
    rescheduled: "evRescheduled",
    cancelled: "evCancelled",
    declined: "evDeclined",
    resumed: "evResumed",
    confirmed: "evConfirmed",
    assigned: "evAssigned",
  })[k] ?? "evNote";

async function openCard(c: Card) {
  detailCard.value = c;
  detailOpen.value = true;
  detailLoading.value = true;
  detailCustomer.value = null;
  allProducts.value = [];
  items.value = [];
  notes.value = [];
  const [cust, prods] = await Promise.all([
    supabase.from("customers").select("*").eq("id", c.customerId).maybeSingle(),
    supabase.from("customer_products").select("*").eq("customer_id", c.customerId).order("created_at"),
  ]);
  detailCustomer.value = (cust.data ?? null) as CsCustomer | null;
  allProducts.value = (prods.data ?? []) as CsProduct[];
  const ids = allProducts.value.map((p) => p.id);
  if (ids.length) {
    const [itemRows, logRows, visitRows] = await Promise.all([
      supabase.from("customer_product_items").select("*").in("product_id", ids).order("sort_order"),
      supabase.from("product_maintenance_log").select("id, product_id, kind, happened_at, done_on, note, created_by").in("product_id", ids).not("note", "is", null),
      supabase.from("maintenance_visits").select("id, note, visit_at, created_at, created_by").eq("customer_id", c.customerId).not("note", "is", null),
    ]);
    items.value = (itemRows.data ?? []) as CsProductItem[];
    const logs = (logRows.data ?? []) as { id: string; product_id: string; kind: string; happened_at: string; done_on: string | null; note: string | null; created_by: string | null }[];
    const visits = (visitRows.data ?? []) as { id: string; note: string | null; visit_at: string | null; created_at: string; created_by: string | null }[];
    const authorIds = [...new Set([...logs.map((l) => l.created_by), ...visits.map((v) => v.created_by)].filter((x): x is string => !!x))];
    const people = authorIds.length ? (((await supabase.from("profiles").select("id, full_name, email").in("id", authorIds)).data ?? []) as { id: string; full_name: string | null; email: string }[]) : [];
    const who = (id: string | null) => {
      const p = people.find((x) => x.id === id);
      return p ? p.full_name || p.email : null;
    };
    const rows: NoteRow[] = [
      ...logs
        .filter((l) => l.note?.trim())
        .map((l) => ({
          id: l.id,
          at: l.kind === "done" && l.done_on ? `${l.done_on.slice(0, 10)}T12:00:00` : l.happened_at,
          text: l.note!.trim(),
          kind: l.kind,
          product: allProducts.value.find((p) => p.id === l.product_id)?.name ?? "",
          by: who(l.created_by),
        })),
      ...visits
        .filter((v) => v.note?.trim())
        .map((v) => ({ id: v.id, at: v.visit_at ?? v.created_at, text: v.note!.trim(), kind: "visit", product: "", by: who(v.created_by) })),
    ];
    // the notes written on the products and when the visit was confirmed
    for (const p of allProducts.value) {
      if (p.notes?.trim()) rows.push({ id: `pn-${p.id}`, at: p.created_at, text: p.notes.trim(), kind: "note", product: p.name, by: null });
      if (p.maintenance_confirm_note?.trim()) rows.push({ id: `cn-${p.id}`, at: p.maintenance_confirmed_at ?? p.created_at, text: p.maintenance_confirm_note.trim(), kind: "confirmed", product: p.name, by: who(p.maintenance_confirmed_by ?? null) });
    }
    notes.value = rows.sort((a, b) => new Date(b.at).getTime() - new Date(a.at).getTime());
  }
  detailLoading.value = false;
}

const categoryOf = (p: CsProduct) => categories.value.find((x) => x.id === p.category_id)?.name ?? null;
const itemsOf = (productId: string) => items.value.filter((i) => i.product_id === productId);
const yesNo = (v: string | null | undefined, positive: string) => (v ? (v === positive ? t("cs.profile.yes") : t("cs.profile.no")) : "—");

// ---- Mark done: the same dialog as on the confirmed visits page
const doneOpen = ref(false);
function openDone() {
  doneOpen.value = true;
}
async function onSaved() {
  detailOpen.value = false;
  await load();
}
function setDay(v: unknown) {
  if (v === "yesterday" || v === "today" || v === "tomorrow") day.value = v;
}
function closeDetail() {
  detailOpen.value = false;
}
</script>

<template>
  <UDashboardPanel :ui="{ body: 'kords-canvas !p-3 sm:!p-6' }">
    <template #header>
      <UDashboardNavbar :title="t('cs.myVisits.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <div class="mx-auto w-full max-w-2xl space-y-4">
        <!-- Yesterday / today / tomorrow -->
        <div class="grid grid-cols-3 gap-2">
          <button
            v-for="d in dayTabs"
            :key="d.value"
            type="button"
            class="flex flex-col items-center gap-0.5 rounded-[14px] border px-2 py-3 transition-colors"
            :class="day === d.value ? 'border-primary bg-primary text-inverted' : 'border-default bg-default text-highlighted'"
            @click="setDay(d.value)"
          >
            <span class="text-base font-semibold">{{ d.label }}</span>
            <span class="text-xs" :class="day === d.value ? 'text-inverted/80' : 'text-muted'">{{ d.count }}</span>
          </button>
        </div>

        <p class="text-sm text-muted">{{ pendingCount ? t("cs.myVisits.pending", { count: pendingCount }) : t("cs.myVisits.noneLeft") }}</p>

        <div v-if="loading" class="flex justify-center py-16">
          <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
        </div>
        <div v-else-if="!shown.length" class="kords-card flex flex-col items-center gap-2 p-10 text-center">
          <UIcon name="i-lucide-calendar-check" class="size-8 text-muted" />
          <p class="text-sm text-muted">{{ t("cs.myVisits.empty") }}</p>
        </div>

        <ul v-else class="space-y-3">
          <li v-for="c in shown" :key="c.key">
            <button
              type="button"
              class="kords-card block w-full space-y-2 border-s-4 p-4 text-start transition-colors active:bg-elevated"
              :class="c.done ? 'border-s-success opacity-80' : 'border-s-primary'"
              @click="openCard(c)"
            >
              <div class="flex items-start justify-between gap-3">
                <span class="min-w-0 text-base font-semibold text-highlighted">{{ titleOf(c.customerId) }}</span>
                <KBadge v-if="c.done" :label="t('cs.myVisits.done')" tone="success" icon="i-lucide-check" />
                <span v-else class="shrink-0 text-sm font-semibold text-primary">{{ clock(c.at) }}</span>
              </div>
              <div v-if="areaOf(c.customerId)" class="flex items-center gap-1.5 text-sm text-muted">
                <UIcon name="i-lucide-map-pin" class="size-4 shrink-0" />{{ areaOf(c.customerId) }}
              </div>
              <div class="flex flex-wrap gap-1.5">
                <KBadge v-for="n in categoryNames(c)" :key="n" :label="n" tone="neutral" outlined />
              </div>
            </button>
          </li>
        </ul>
      </div>
    </template>
  </UDashboardPanel>

  <!-- Full details of the visit -->
  <UModal v-model:open="detailOpen" fullscreen :title="detailCard ? titleOf(detailCard.customerId) : ''" :ui="{ body: 'p-3 sm:p-6' }">
    <template #body>
      <div v-if="detailLoading || !detailCustomer" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>
      <div v-else class="mx-auto w-full max-w-2xl space-y-4">
        <!-- Customer -->
        <section class="kords-card space-y-3 p-4">
          <div>
            <h3 class="text-lg font-semibold text-highlighted">{{ customerTitle(detailCustomer) }}</h3>
            <p v-if="customerSubtitle(detailCustomer)" class="text-sm text-muted">{{ customerSubtitle(detailCustomer) }}</p>
          </div>
          <div class="grid grid-cols-2 gap-2">
            <UButton v-if="detailCustomer.phone" :to="`tel:${detailCustomer.phone}`" icon="i-lucide-phone" size="lg" color="neutral" variant="outline" :label="t('cs.myVisits.call')" block />
            <UButton v-if="toWhatsAppLink(detailCustomer.phone)" :to="toWhatsAppLink(detailCustomer.phone)!" target="_blank" rel="noopener noreferrer" icon="i-simple-icons-whatsapp" size="lg" color="neutral" variant="outline" :label="t('cs.profile.whatsapp')" block />
          </div>
          <dl class="space-y-2 text-sm">
            <div v-if="detailCustomer.phone"><dt class="text-xs text-muted">{{ t("common.phone") }}</dt><dd dir="ltr" class="text-start font-medium text-highlighted">{{ detailCustomer.phone }}</dd></div>
            <div v-for="(x, i) in toExtraContacts(detailCustomer.extra_phones, detailCustomer.extra_phone_names)" :key="i">
              <dt class="text-xs text-muted">{{ x.name || t("common.extraPhones") }}</dt>
              <dd><a :href="`tel:${x.phone}`" dir="ltr" class="font-medium text-primary">{{ x.phone }}</a></dd>
            </div>
            <div v-if="areaName(detailCustomer.area_id)"><dt class="text-xs text-muted">{{ t("cs.customers.area") }}</dt><dd class="font-medium text-highlighted">{{ areaName(detailCustomer.area_id) }}</dd></div>
            <div v-if="detailCustomer.address"><dt class="text-xs text-muted">{{ t("cs.customers.address") }}</dt><dd class="whitespace-pre-line font-medium text-highlighted">{{ detailCustomer.address }}</dd></div>
            <div v-if="detailCustomer.email"><dt class="text-xs text-muted">{{ t("common.email") }}</dt><dd dir="ltr" class="text-start text-highlighted">{{ detailCustomer.email }}</dd></div>
          </dl>
        </section>

        <!-- This visit -->
        <section v-if="detailCard" class="space-y-2">
          <h4 class="text-sm font-semibold text-highlighted">{{ t("cs.myVisits.thisVisit") }}</h4>
          <p v-if="!detailCard.done" class="text-sm text-muted">{{ formatDateTime(new Date(detailCard.at).toISOString()) }}</p>
          <div v-for="p in detailProducts" :key="p.id" class="kords-card space-y-2 p-4 text-sm">
            <div class="flex flex-wrap items-center gap-2">
              <span class="text-base font-semibold text-highlighted">{{ p.name }}</span>
              <span v-if="(p.quantity ?? 1) > 1" class="text-xs text-muted">× {{ p.quantity }}</span>
              <KBadge v-if="categoryOf(p)" :label="categoryOf(p)!" tone="neutral" outlined />
            </div>
            <dl class="grid grid-cols-2 gap-x-3 gap-y-2">
              <div v-if="p.contract_code"><dt class="text-xs text-muted">{{ t("cs.profile.contractCode") }}</dt><dd dir="ltr" class="text-start font-medium">{{ p.contract_code }}</dd></div>
              <div v-if="p.operation_date"><dt class="text-xs text-muted">{{ t("cs.profile.operationDate") }}</dt><dd class="font-medium">{{ formatDMY(p.operation_date) }}</dd></div>
              <div v-if="p.last_maintenance_on"><dt class="text-xs text-muted">{{ t("cs.maintenance.lastDone") }}</dt><dd class="font-medium">{{ formatDMY(p.last_maintenance_on) }}</dd></div>
              <div><dt class="text-xs text-muted">{{ t("cs.profile.warrantyLabel") }}</dt><dd class="font-medium">{{ yesNo(p.warranty_status, "in_warranty") }}</dd></div>
              <div><dt class="text-xs text-muted">{{ t("cs.profile.paymentLabel") }}</dt><dd class="font-medium">{{ yesNo(p.payment_status, "paid") }}</dd></div>
            </dl>
            <p v-if="p.warranty_details" class="whitespace-pre-line text-toned">{{ p.warranty_details }}</p>
            <ul v-if="itemsOf(p.id).length" class="divide-y divide-default rounded-[10px] bg-muted px-3">
              <li v-for="it in itemsOf(p.id)" :key="it.id" class="flex justify-between gap-2 py-1.5">
                <span>{{ it.name }}</span>
                <span class="text-muted">{{ it.quantity }}<template v-if="it.unit"> {{ it.unit }}</template></span>
              </li>
            </ul>
          </div>
        </section>

        <!-- The customer's other products -->
        <section v-if="otherProducts.length" class="space-y-1">
          <h4 class="text-sm font-semibold text-highlighted">{{ t("cs.myVisits.otherProducts") }}</h4>
          <ul class="kords-card divide-y divide-default px-4 text-sm">
            <li v-for="p in otherProducts" :key="p.id" class="py-2">{{ p.name }}<span v-if="categoryOf(p)" class="ms-2 text-xs text-muted">{{ categoryOf(p) }}</span></li>
          </ul>
        </section>

        <!-- Every past note -->
        <section class="space-y-2">
          <h4 class="text-sm font-semibold text-highlighted">{{ t("cs.myVisits.pastNotes") }} <span class="text-xs font-normal text-muted">({{ notes.length }})</span></h4>
          <p v-if="!notes.length" class="kords-card p-4 text-sm text-muted">{{ t("cs.myVisits.noNotes") }}</p>
          <ul v-else class="space-y-2">
            <li v-for="n in notes" :key="n.id" class="kords-card space-y-1 p-3 text-sm">
              <div class="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-muted">
                <KBadge :label="n.kind === 'visit' ? t('cs.profile.visitNote') : t(`cs.maintenance.${kindLabel(n.kind)}`)" tone="neutral" />
                <span>{{ formatDMY(n.at) }}</span>
                <span v-if="n.product">· {{ n.product }}</span>
                <span v-if="n.by">· {{ n.by }}</span>
              </div>
              <p class="whitespace-pre-line text-toned">{{ n.text }}</p>
            </li>
          </ul>
        </section>

        <div class="sticky bottom-0 -mx-3 border-t border-default bg-default p-3 sm:mx-0">
          <UButton
            v-if="canComplete && detailCard && !detailCard.done"
            icon="i-lucide-check"
            size="xl"
            color="success"
            :label="t('cs.maintenance.markDone')"
            block
            @click="openDone"
          />
          <UButton v-else color="neutral" variant="outline" size="lg" :label="t('cs.myVisits.close')" block @click="closeDetail" />
        </div>
      </div>
    </template>
  </UModal>

  <MaintenanceDoneModal v-model:open="doneOpen" :products="detailCard?.products ?? []" @saved="onSaved" />
</template>
