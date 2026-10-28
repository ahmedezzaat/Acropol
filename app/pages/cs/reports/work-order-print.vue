<script setup lang="ts">
// The printable work order (أمر الشغل) of one done visit: customer contact details, what was
// done and what it cost, the notes, the next maintenance and the customer's signature.
// Opens the print dialog by itself — choose "Save as PDF" there. ?visit=<visit key>.
definePageMeta({
  layout: false,
  crmPermission: { module: "reports", action: "maintenance_done" },
});

const route = useRoute();
const supabase = useSupabaseClient();
const { t, locale } = useI18n();

interface Part { name: string; quantity: number; unit_price: number }
interface Entry { product_name: string; category_name: string | null; cost: number | null; visit_cost: number | null; note: string | null; parts: Part[] | null; next_at: string | null; next_note: string | null }
interface WorkOrder {
  customer: { name: string; company: string | null; phone: string | null; extra_phones: string[] | null; extra_phone_names: string[] | null; email: string | null; address: string | null; area: string | null };
  visit: { done_on: string; note: string | null };
  technician: string | null;
  signature_path: string | null;
  entries: Entry[];
}

const visitKey = typeof route.query.visit === "string" ? route.query.visit : "";
const error = ref<string | null>(null);
const signatureUrl = ref<string | null>(null);

const { data: order } = await useAsyncData<WorkOrder | null>("report-work-order", async () => {
  const { data, error: rpcError } = await supabase.rpc("report_work_order", { p_visit_key: visitKey });
  if (rpcError) {
    error.value = rpcError.message;
    return null;
  }
  return data as unknown as WorkOrder;
});

const money = (v: number | null | undefined) => formatReportMoney(Number(v ?? 0), t("common.currency"));
const entries = computed(() => order.value?.entries ?? []);
const totalCost = computed(() => entries.value.reduce((n, e) => n + Number(e.cost ?? 0), 0));
// the parts of the whole visit, and the visit fee (entered once, on the first product)
const partsTotal = (e: Entry) => (e.parts ?? []).reduce((n, p) => n + p.quantity * p.unit_price, 0);
const phones = computed(() => {
  const c = order.value?.customer;
  if (!c) return [];
  return [
    ...(c.phone ? [{ phone: c.phone, name: null as string | null }] : []),
    ...(c.extra_phones ?? []).map((p, i) => ({ phone: p, name: c.extra_phone_names?.[i] || null })),
  ];
});
const orderNo = visitKey.slice(0, 8).toUpperCase();

function doPrint() {
  window.print();
}
onMounted(async () => {
  // the signature is a private file: a short-lived link, loaded before the print dialog opens
  const path = order.value?.signature_path;
  if (path) {
    const { data } = await supabase.storage.from("visit-signatures").createSignedUrl(path, 600);
    signatureUrl.value = data?.signedUrl ?? null;
    if (signatureUrl.value) await new Promise<void>((resolve) => {
      const img = new Image();
      img.onload = img.onerror = () => resolve();
      img.src = signatureUrl.value!;
    });
  }
  if (order.value) setTimeout(doPrint, 400);
});
</script>

<template>
  <div class="sheet-wrap">
    <div class="no-print toolbar">
      <button type="button" class="btn" @click="doPrint">{{ t("reports.printButton") }}</button>
      <NuxtLink to="/cs/reports/maintenance-done" class="btn ghost">{{ t("reports.back") }}</NuxtLink>
      <span class="hint">{{ t("reports.printHint") }}</span>
    </div>

    <article class="sheet" :dir="locale === 'ar' ? 'rtl' : 'ltr'">
      <p v-if="!order" class="empty">{{ error ?? t("reports.noData") }}</p>
      <template v-else>
        <header class="doc-head">
          <div class="brand">{{ t("nav.appName") }}</div>
          <div class="doc-title">{{ t("reports.workOrder.title") }} <span class="no">#{{ orderNo }}</span></div>
        </header>

        <dl class="meta">
          <div><dt>{{ t("reports.workOrder.doneOn") }}</dt><dd>{{ formatDMY(order.visit.done_on) }}</dd></div>
          <div><dt>{{ t("reports.maintenanceDone.technician") }}</dt><dd>{{ order.technician || "—" }}</dd></div>
        </dl>

        <h3 class="sub">{{ t("reports.workOrder.customer") }}</h3>
        <dl class="info">
          <div><dt>{{ t("common.name") }}</dt><dd>{{ order.customer.company ? `${order.customer.company} — ${order.customer.name}` : order.customer.name }}</dd></div>
          <div>
            <dt>{{ t("common.phone") }}</dt>
            <dd><span v-for="(p, i) in phones" :key="i" class="phone" dir="ltr">{{ p.phone }}<template v-if="p.name"> ({{ p.name }})</template></span><template v-if="!phones.length">—</template></dd>
          </div>
          <div v-if="order.customer.email"><dt>{{ t("common.email") }}</dt><dd dir="ltr">{{ order.customer.email }}</dd></div>
          <div><dt>{{ t("cs.customers.area") }}</dt><dd>{{ order.customer.area || "—" }}</dd></div>
          <div class="wide"><dt>{{ t("cs.customers.address") }}</dt><dd>{{ order.customer.address || "—" }}</dd></div>
        </dl>

        <h3 class="sub">{{ t("reports.workOrder.work") }}</h3>
        <div v-for="(e, i) in entries" :key="i" class="entry">
          <div class="entry-head">
            <strong>{{ e.product_name }}</strong>
            <span v-if="e.category_name" class="muted"> · {{ e.category_name }}</span>
          </div>
          <table v-if="e.parts?.length" class="rows">
            <thead>
              <tr>
                <th>{{ t("reports.sparePartsUsed.part") }}</th>
                <th class="num">{{ t("reports.sparePartsUsed.qty") }}</th>
                <th class="num">{{ t("reports.sparePartsUsed.unitPrice") }}</th>
                <th class="num">{{ t("reports.sparePartsUsed.lineTotal") }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(p, j) in e.parts" :key="j">
                <td>{{ p.name }}</td>
                <td class="num">{{ p.quantity }}</td>
                <td class="num nowrap">{{ money(p.unit_price) }}</td>
                <td class="num nowrap">{{ money(p.quantity * p.unit_price) }}</td>
              </tr>
            </tbody>
          </table>
          <p v-else class="muted small">{{ t("reports.workOrder.noParts") }}</p>
          <div class="costs">
            <span v-if="e.visit_cost !== null">{{ t("cs.maintenance.visitCost") }}: {{ money(e.visit_cost) }}</span>
            <span v-if="e.parts?.length">{{ t("cs.maintenance.partsTotal") }}: {{ money(partsTotal(e)) }}</span>
            <strong>{{ t("reports.maintenanceDone.cost") }}: {{ money(e.cost) }}</strong>
          </div>
          <p v-if="e.note" class="note">{{ e.note }}</p>
        </div>
        <div class="grand"><span>{{ t("reports.maintenanceDone.totalCost") }}</span><span>{{ money(totalCost) }}</span></div>

        <template v-if="order.visit.note">
          <h3 class="sub">{{ t("reports.workOrder.notes") }}</h3>
          <p class="note">{{ order.visit.note }}</p>
        </template>

        <template v-if="entries.some((e) => e.next_at)">
          <h3 class="sub">{{ t("reports.workOrder.next") }}</h3>
          <ul class="next">
            <li v-for="(e, i) in entries.filter((x) => x.next_at)" :key="i">
              <strong>{{ e.product_name }}</strong> — {{ formatDMYTime(e.next_at!, locale) }}<template v-if="e.next_note"> · {{ e.next_note }}</template>
            </li>
          </ul>
        </template>

        <h3 class="sub">{{ t("cs.maintenance.customerSignature") }}</h3>
        <div class="signature">
          <img v-if="signatureUrl" :src="signatureUrl" alt="" />
          <span v-else class="muted small">{{ t("reports.workOrder.noSignature") }}</span>
        </div>
      </template>
    </article>
  </div>
</template>

<style scoped>
.sheet-wrap { min-height: 100vh; background: #e5e7eb; padding: 16px; font-family: inherit; color: #111827; }
.toolbar { max-width: 210mm; margin: 0 auto 12px; display: flex; flex-wrap: wrap; align-items: center; gap: 10px; }
.btn { background: #1d4ed8; color: #fff; border: 0; padding: 8px 16px; font-size: 14px; cursor: pointer; text-decoration: none; }
.btn.ghost { background: #fff; color: #111827; border: 1px solid #d1d5db; }
.hint { color: #6b7280; font-size: 12px; }
.sheet { width: 210mm; min-height: 297mm; margin: 0 auto; background: #fff; padding: 14mm 12mm; font-size: 12px; line-height: 1.5; }
.doc-head { display: flex; justify-content: space-between; align-items: baseline; border-bottom: 2px solid #111827; padding-bottom: 8px; margin-bottom: 12px; }
.brand { font-size: 18px; font-weight: 700; }
.doc-title { font-size: 16px; font-weight: 600; }
.no { color: #6b7280; font-weight: 400; font-size: 12px; }
.meta { display: grid; grid-template-columns: repeat(2, 1fr); gap: 6px 16px; margin: 0 0 10px; }
.meta div, .info div { display: flex; gap: 6px; }
dt { color: #6b7280; }
dt::after { content: ":"; }
dd { margin: 0; font-weight: 500; }
.sub { font-size: 13px; font-weight: 700; margin: 14px 0 6px; padding-bottom: 3px; border-bottom: 1px solid #d1d5db; }
.info { display: grid; grid-template-columns: repeat(2, 1fr); gap: 4px 16px; margin: 0; }
.info .wide { grid-column: 1 / -1; }
.phone { display: inline-block; margin-inline-end: 10px; }
.entry { border: 1px solid #d1d5db; padding: 8px; margin-bottom: 8px; break-inside: avoid; }
.entry-head { margin-bottom: 6px; }
.muted { color: #6b7280; }
.small { font-size: 11px; }
.rows { width: 100%; border-collapse: collapse; }
.rows th, .rows td { border: 1px solid #d1d5db; padding: 3px 6px; text-align: start; }
.rows th { background: #f3f4f6; font-weight: 600; }
.num { text-align: end !important; }
.nowrap { white-space: nowrap; }
.costs { display: flex; flex-wrap: wrap; gap: 4px 16px; margin-top: 6px; }
.note { white-space: pre-line; margin: 6px 0 0; }
.grand { display: flex; justify-content: space-between; font-size: 14px; font-weight: 700; border-top: 2px solid #111827; padding-top: 6px; margin-top: 4px; }
.next { margin: 0; padding-inline-start: 18px; }
.signature { border: 1px solid #d1d5db; height: 30mm; width: 70mm; display: flex; align-items: center; justify-content: center; break-inside: avoid; }
.signature img { max-width: 100%; max-height: 100%; }
.empty { text-align: center; padding: 40px 0; color: #6b7280; }
@media print { .sheet-wrap { background: #fff; padding: 0; } .sheet { width: auto; min-height: 0; padding: 0; } .no-print { display: none; } }
</style>

<style>
@media print {
  @page { size: A4; margin: 12mm 12mm 16mm; }
}
</style>
