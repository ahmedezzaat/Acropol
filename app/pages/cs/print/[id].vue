<script setup lang="ts">
// A printable A4 sheet: the customer's details and their product(s), with who
// exported it and when. Open it and use Print / Save as PDF. /cs/print/<customer>
// prints every product; add ?product=<id> for one.
definePageMeta({
  layout: false,
  crmPermission: { module: "cs_customers" },
});

const route = useRoute();
const customerId = route.params.id as string;
const onlyProduct = typeof route.query.product === "string" ? route.query.product : null;

const supabase = useSupabaseClient();
const user = useSupabaseUser();
const { t, locale } = useI18n();
const { visitTasks, stagesOf, stageName, formatDate, formatDateTime, dateIndex, dateOf, maintenanceDue, loadAreas, loadPipelines, areaName } = useCs();

await Promise.all([loadAreas(true), loadPipelines(true)]);

const { data: customer, status } = await useAsyncData(`cs-print-${customerId}`, async () => {
  const { data } = await supabase
    .from("customers")
    .select("id, name, company, phone, extra_phones, extra_phone_names, email, address, area_id, created_at, customer_type")
    .eq("id", customerId)
    .maybeSingle();
  return (data ?? null) as CsCustomer | null;
});

const { data: bundle } = await useAsyncData(`cs-print-${customerId}-products`, async () => {
  let query = supabase.from("customer_products").select("*").eq("customer_id", customerId).order("created_at", { ascending: false });
  if (onlyProduct) query = query.eq("id", onlyProduct);
  const { data: products } = await query;
  const list = (products ?? []) as CsProduct[];
  const ids = list.map((p) => p.id);
  const [items, dates, categories, people] = await Promise.all([
    ids.length ? supabase.from("customer_product_items").select("*").in("product_id", ids).order("sort_order") : { data: [] },
    ids.length ? supabase.from("customer_product_stage_dates").select("product_id, stage_id, reached_on").in("product_id", ids) : { data: [] },
    supabase.from("product_categories").select("id, name, maintenance_interval_months, maintenance_tasks"),
    supabase.from("profiles").select("id, full_name, email"),
  ]);
  return {
    products: list,
    items: (items.data ?? []) as CsProductItem[],
    dates: (dates.data ?? []) as CsStageDate[],
    categories: (categories.data ?? []) as { id: string; name: string; maintenance_interval_months: number | null; maintenance_tasks: MaintenanceTask[] }[],
    people: (people.data ?? []) as { id: string; full_name: string | null; email: string }[],
  };
});

const products = computed(() => bundle.value?.products ?? []);
const dates = computed(() => dateIndex(bundle.value?.dates ?? []));
const categoryOf = (id: string | null) => bundle.value?.categories.find((c) => c.id === id) ?? null;
const personName = (id: string | null) => {
  const p = id ? bundle.value?.people.find((x) => x.id === id) : null;
  return p ? p.full_name || p.email : null;
};
const itemsOf = (productId: string) => (bundle.value?.items ?? []).filter((i) => i.product_id === productId);

// Who is printing it.
const me = computed(() => {
  const id = user.value?.sub as string | undefined;
  const p = id ? bundle.value?.people.find((x) => x.id === id) : null;
  return p ? p.full_name || p.email : ((user.value?.email as string | undefined) ?? "—");
});
const myEmail = computed(() => {
  const id = user.value?.sub as string | undefined;
  return (id ? bundle.value?.people.find((x) => x.id === id)?.email : null) ?? (user.value?.email as string | undefined) ?? "";
});
const exportedAt = new Date();
const exportedAtText = formatDMYTime(exportedAt, locale.value);

function dueText(p: CsProduct) {
  if (p.maintenance_declined_at) return t("cs.maintenance.declinedNote");
  if (p.next_maintenance_at) return formatDateTime(p.next_maintenance_at);
  const due = maintenanceDue(p, categoryOf(p.category_id)?.maintenance_interval_months ?? null);
  return due ? `${formatDate(due)} (${t("cs.maintenance.periodicShort")})` : "—";
}
// What the next periodic visit will do (the category's maintenance policy).
function planOf(p: CsProduct) {
  const category = categoryOf(p.category_id);
  if (p.maintenance_declined_at) return [];
  const due = maintenanceDue(p, category?.maintenance_interval_months ?? null);
  return visitTasks(p.operation_date, due, category?.maintenance_tasks);
}
const yesNo = (v: string | null, yes: string) => (v ? (v === yes ? t("cs.profile.yes") : t("cs.profile.no")) : "—");

function doPrint() {
  window.print();
}
// Open the print dialog once the sheet is on screen.
onMounted(() => {
  setTimeout(() => {
    if (customer.value) window.print();
  }, 600);
});
</script>

<template>
  <div class="sheet-wrap">
    <div class="no-print toolbar">
      <button type="button" class="btn" @click="doPrint">{{ t("cs.print.button") }}</button>
      <NuxtLink :to="`/cs/customers/${customerId}`" class="btn ghost">{{ t("cs.print.back") }}</NuxtLink>
      <span class="hint">{{ t("cs.print.hint") }}</span>
    </div>

    <p v-if="status === 'pending'" class="empty">…</p>
    <p v-else-if="!customer" class="empty">{{ t("cs.profile.notFound") }}</p>

    <article v-else class="sheet" :dir="locale === 'ar' ? 'rtl' : 'ltr'">
      <header class="doc-head">
        <div class="brand">{{ t("nav.appName") }}</div>
        <div class="doc-title">{{ t("cs.print.title") }}</div>
      </header>

      <section class="block">
        <h2>{{ t("cs.print.customer") }}</h2>
        <div class="customer-name">{{ customerTitle(customer) }}</div>
        <div v-if="customerSubtitle(customer)" class="muted">{{ customerSubtitle(customer) }}</div>
        <dl class="grid">
          <div><dt>{{ t("common.phone") }}</dt><dd dir="ltr">{{ customer.phone || "—" }}</dd></div>
          <div v-if="customer.extra_phones?.length"><dt>{{ t("common.extraPhones") }}</dt><dd dir="ltr">{{ toExtraContacts(customer.extra_phones, customer.extra_phone_names).map((c) => (c.name ? `${c.phone} (${c.name})` : c.phone)).join(" ، ") }}</dd></div>
          <div><dt>{{ t("common.email") }}</dt><dd dir="ltr">{{ customer.email || "—" }}</dd></div>
          <div><dt>{{ t("cs.customers.area") }}</dt><dd>{{ areaName(customer.area_id) || "—" }}</dd></div>
          <div><dt>{{ t("crm.leads.leadType") }}</dt><dd>{{ t(`crm.leads.type.${isCompanyCustomer(customer) ? "company" : "individual"}`) }}</dd></div>
          <div class="wide"><dt>{{ t("cs.customers.address") }}</dt><dd>{{ customer.address || "—" }}</dd></div>
        </dl>
      </section>

      <section v-for="p in products" :key="p.id" class="block product">
        <h2>
          {{ t("cs.print.product") }}: {{ p.name }}<template v-if="(p.quantity ?? 1) > 1"> × {{ p.quantity }}</template>
          <span v-if="p.contract_code" class="code" dir="ltr">#{{ p.contract_code }}</span>
        </h2>

        <table class="funnel">
          <thead>
            <tr><th v-for="st in stagesOf(p.pipeline_id)" :key="st.id" :class="st.id === p.stage_id && 'current'">{{ st.name }}</th></tr>
          </thead>
          <tbody>
            <tr><td v-for="st in stagesOf(p.pipeline_id)" :key="st.id" :class="st.id === p.stage_id && 'current'">{{ formatDate(dateOf(dates, p.id, st.id)) }}</td></tr>
          </tbody>
        </table>

        <dl class="grid">
          <div><dt>{{ t("cs.profile.category") }}</dt><dd>{{ categoryOf(p.category_id)?.name ?? "—" }}</dd></div>
          <div><dt>{{ t("cs.installations.currentStage") }}</dt><dd>{{ stageName(p.stage_id) }}</dd></div>
          <div><dt>{{ t("cs.profile.contractDate") }}</dt><dd>{{ formatDate(p.contract_date) }}</dd></div>
          <div><dt>{{ t("cs.profile.operationDate") }}</dt><dd>{{ formatDate(p.operation_date) }}</dd></div>
          <div><dt>{{ t("cs.profile.salesPerson") }}</dt><dd>{{ personName(p.sales_person_id) || "—" }}</dd></div>
          <div><dt>{{ t("cs.profile.warrantyLabel") }}</dt><dd>{{ yesNo(p.warranty_status, "in_warranty") }}</dd></div>
          <div><dt>{{ t("cs.profile.paymentLabel") }}</dt><dd>{{ yesNo(p.payment_status, "paid") }}</dd></div>
          <div><dt>{{ t("cs.maintenance.next") }}</dt><dd>{{ dueText(p) }}</dd></div>
          <div v-if="p.last_maintenance_on"><dt>{{ t("cs.maintenance.lastDone") }}</dt><dd>{{ formatDate(p.last_maintenance_on) }}</dd></div>
          <div v-if="p.warranty_details" class="wide"><dt>{{ t("cs.profile.warrantyDetails") }}</dt><dd class="pre">{{ p.warranty_details }}</dd></div>
        </dl>

        <div v-if="planOf(p).length" class="sub">
          <h3>{{ t("cs.maintenance.visitPlan") }}</h3>
          <ul class="plan">
            <li v-for="(task, i) in planOf(p)" :key="i">
              <span class="pre">{{ task.title }}</span>
              <span v-if="task.replace" class="muted pre"> — {{ t("cs.maintenance.partsToChange") }}: {{ task.replace }}</span>
            </li>
          </ul>
        </div>

        <div v-if="itemsOf(p.id).length" class="sub">
          <h3>{{ t("cs.profile.items") }}</h3>
          <table class="items">
            <tbody>
              <tr v-for="i in itemsOf(p.id)" :key="i.id"><td>{{ i.name }}</td><td class="qty">{{ i.quantity }} {{ i.unit ?? "" }}</td></tr>
            </tbody>
          </table>
        </div>

        <div v-if="p.notes" class="sub">
          <h3>{{ t("cs.profile.notes") }}</h3>
          <p class="pre">{{ p.notes }}</p>
        </div>
      </section>

      <p v-if="!products.length" class="muted">{{ t("cs.profile.noProducts") }}</p>

      <footer class="doc-foot">
        {{ t("cs.print.exportedBy") }}: <strong>{{ me }}</strong><template v-if="myEmail && myEmail !== me"> ({{ myEmail }})</template>
        · {{ t("cs.print.exportedAt") }}: {{ exportedAtText }}
      </footer>
    </article>
  </div>
</template>

<style scoped>
.sheet-wrap {
  min-height: 100vh;
  background: #e5e7eb;
  padding: 16px;
  font-family: inherit;
  color: #111827;
}
.toolbar {
  max-width: 210mm;
  margin: 0 auto 12px;
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 10px;
}
.btn {
  background: #1d4ed8;
  color: #fff;
  border: 0;
  padding: 8px 16px;
  font-size: 14px;
  cursor: pointer;
  text-decoration: none;
}
.btn.ghost {
  background: #fff;
  color: #111827;
  border: 1px solid #d1d5db;
}
.hint {
  color: #6b7280;
  font-size: 12px;
}
.empty {
  text-align: center;
  padding: 40px;
}
.sheet {
  width: 210mm;
  min-height: 297mm;
  margin: 0 auto;
  background: #fff;
  padding: 14mm 14mm 22mm;
  box-sizing: border-box;
  position: relative;
  font-size: 12.5px;
  line-height: 1.6;
}
.doc-head {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  border-bottom: 2px solid #1d4ed8;
  padding-bottom: 8px;
  margin-bottom: 14px;
}
.brand {
  font-size: 20px;
  font-weight: 700;
  color: #1d4ed8;
}
.doc-title {
  font-size: 15px;
  font-weight: 600;
}
.block {
  margin-bottom: 14px;
  break-inside: avoid;
}
h2 {
  font-size: 14px;
  font-weight: 700;
  background: #f3f4f6;
  padding: 4px 8px;
  margin: 0 0 8px;
}
h3 {
  font-size: 12.5px;
  font-weight: 700;
  margin: 8px 0 4px;
}
.code {
  color: #6b7280;
  font-weight: 400;
  margin-inline-start: 6px;
}
.customer-name {
  font-size: 17px;
  font-weight: 700;
}
.muted {
  color: #6b7280;
}
.grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 4px 20px;
  margin: 8px 0 0;
}
.grid > div {
  display: flex;
  gap: 8px;
  border-bottom: 1px solid #e5e7eb;
  padding: 3px 0;
}
.grid .wide {
  grid-column: 1 / -1;
}
dt {
  color: #6b7280;
  min-width: 90px;
}
dd {
  margin: 0;
  font-weight: 600;
}
.pre {
  white-space: pre-line;
  font-weight: 400;
}
.funnel {
  width: 100%;
  border-collapse: collapse;
  text-align: center;
  margin-bottom: 6px;
}
.funnel th,
.funnel td {
  border: 1px solid #d1d5db;
  padding: 4px 6px;
}
.funnel th {
  background: #f9fafb;
  font-weight: 600;
}
.funnel .current {
  background: #1d4ed8;
  color: #fff;
}
.plan {
  margin: 0;
  padding-inline-start: 18px;
}
.items {
  width: 100%;
  border-collapse: collapse;
}
.items td {
  border-bottom: 1px solid #e5e7eb;
  padding: 3px 4px;
}
.items .qty {
  text-align: end;
  font-weight: 600;
  white-space: nowrap;
}
.doc-foot {
  position: absolute;
  inset-inline: 14mm;
  bottom: 10mm;
  border-top: 1px solid #d1d5db;
  padding-top: 6px;
  font-size: 11px;
  color: #4b5563;
}

@media print {
  .no-print {
    display: none !important;
  }
  .sheet-wrap {
    background: #fff;
    padding: 0;
  }
  .sheet {
    width: auto;
    min-height: 0;
    margin: 0;
    padding: 0 0 14mm;
    box-shadow: none;
  }
  /* The exported-by line repeats at the bottom of every printed page. */
  .doc-foot {
    position: fixed;
    inset-inline: 0;
    bottom: 0;
  }
}
</style>

<style>
@media print {
  @page {
    size: A4;
    margin: 12mm 12mm 16mm;
  }
}
</style>
