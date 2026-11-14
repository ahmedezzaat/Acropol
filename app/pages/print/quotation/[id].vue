<script setup lang="ts">
// A quotation printed on A4 (Print / Save as PDF): the company's logo and contact details, the customer, the lines,
// the totals, the terms and room for signatures. /print/quotation/<id>
definePageMeta({ layout: false });

const route = useRoute();
const id = route.params.id as string;
const supabase = useSupabaseClient();
const { t } = useI18n();

const COMPANY = {
  nameAr: "أكروبول لحلول الطاقة المتجددة",
  nameEn: "Acropol Renewable Energy Solutions S.A.E",
  email: "info@acropol.com.eg",
  address: "20 ب عمارات العبور، صلاح سالم، القاهرة",
  website: "acropol-eg.com",
};

interface Q {
  number: string; status: string; issue_date: string; valid_until: string | null; discount: number; tax_invoice: boolean;
  notes: string | null; subtotal: number; tax: number; total: number;
  customer: { name: string; company: string | null; phone: string | null; address: string | null } | null;
}
const { data, status } = await useAsyncData(`print-quotation-${id}`, async () => {
  const [{ data: q }, { data: items }] = await Promise.all([
    supabase.from("cs_quotations").select("number, status, issue_date, valid_until, discount, tax_invoice, notes, subtotal, tax, total, customer:customers(name, company, phone, address)").eq("id", id).maybeSingle(),
    supabase.from("cs_quotation_items").select("description, qty, unit_price, line_total").eq("quotation_id", id).order("sort_order"),
  ]);
  if (!q) return null;
  const quote = q as unknown as Q;
  return {
    q: { ...quote, discount: Number(quote.discount), subtotal: Number(quote.subtotal), tax: Number(quote.tax), total: Number(quote.total) },
    items: (items ?? []).map((i) => ({ description: i.description as string, qty: Number(i.qty), unit_price: Number(i.unit_price), line_total: Number(i.line_total) })),
  };
});

const money = (v: number) => `${v.toLocaleString("en-US", { maximumFractionDigits: 2 })} ${t("common.currency")}`;
const num = (v: number) => v.toLocaleString("en-US", { maximumFractionDigits: 2 });
// the file name of the saved PDF
useHead({ title: computed(() => (data.value ? `${data.value.q.number} - ${data.value.q.customer?.company || data.value.q.customer?.name || ""}` : "")) });
function doPrint() {
  window.print();
}
</script>

<template>
  <div class="wrap">
    <div class="no-print toolbar">
      <button type="button" class="btn" @click="doPrint">{{ t("cs.quotations.print") }}</button>
      <NuxtLink :to="`/cs/quotations/${id}`" class="btn ghost">{{ t("cs.quotations.printBack") }}</NuxtLink>
      <span class="hint">{{ t("cs.quotations.printHint") }}</span>
    </div>

    <p v-if="status === 'pending'" class="empty">…</p>
    <p v-else-if="!data" class="empty">{{ t("cs.quotations.notFound") }}</p>

    <article v-else class="sheet" dir="rtl">
      <!-- the company -->
      <header class="head">
        <div class="brand">
          <img src="/acropol-logo.png" alt="Acropol" class="logo" />
          <div>
            <p class="company">{{ COMPANY.nameAr }}</p>
            <p class="company-en" dir="ltr">{{ COMPANY.nameEn }}</p>
          </div>
        </div>
        <div class="doc">
          <p class="doc-title">{{ t("cs.quotations.printTitle") }}</p>
          <p><span class="muted">{{ t("cs.quotations.number") }}:</span> <bdi dir="ltr" class="strong">{{ data.q.number }}</bdi></p>
          <p><span class="muted">{{ t("cs.quotations.issueDate") }}:</span> {{ formatDMY(data.q.issue_date) }}</p>
          <p v-if="data.q.valid_until"><span class="muted">{{ t("cs.quotations.validUntil") }}:</span> {{ formatDMY(data.q.valid_until) }}</p>
        </div>
      </header>

      <!-- the customer -->
      <section class="customer">
        <p class="muted small">{{ t("cs.quotations.printFor") }}</p>
        <p class="strong big">{{ data.q.customer?.company || data.q.customer?.name || "—" }}</p>
        <p v-if="data.q.customer?.company && data.q.customer?.name">{{ data.q.customer.name }}</p>
        <p v-if="data.q.customer?.phone"><bdi dir="ltr">{{ data.q.customer.phone }}</bdi></p>
        <p v-if="data.q.customer?.address">{{ data.q.customer.address }}</p>
      </section>

      <!-- the lines -->
      <table class="lines">
        <thead>
          <tr>
            <th class="n">#</th>
            <th>{{ t("cs.quotations.description") }}</th>
            <th class="c">{{ t("cs.quotations.qty") }}</th>
            <th class="c">{{ t("cs.quotations.unitPrice") }}</th>
            <th class="c">{{ t("cs.quotations.lineTotal") }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(l, i) in data.items" :key="i">
            <td class="n">{{ i + 1 }}</td>
            <td>{{ l.description }}</td>
            <td class="c">{{ num(l.qty) }}</td>
            <td class="c">{{ num(l.unit_price) }}</td>
            <td class="c strong">{{ num(l.line_total) }}</td>
          </tr>
        </tbody>
      </table>

      <!-- totals -->
      <div class="totals">
        <div><span>{{ t("cs.quotations.subtotal") }}</span><span>{{ money(data.q.subtotal) }}</span></div>
        <div v-if="data.q.discount > 0"><span>{{ t("cs.maintenance.discount") }}</span><span>− {{ money(Math.min(data.q.discount, data.q.subtotal)) }}</span></div>
        <div v-if="data.q.tax > 0"><span>{{ t("cs.maintenance.taxLine", { rate: 14 }) }}</span><span>+ {{ money(data.q.tax) }}</span></div>
        <div class="grand"><span>{{ t("cs.quotations.total") }}</span><span>{{ money(data.q.total) }}</span></div>
      </div>

      <!-- terms -->
      <section v-if="data.q.notes || data.q.valid_until" class="terms">
        <p class="strong">{{ t("cs.quotations.printTerms") }}</p>
        <p v-if="data.q.valid_until">{{ t("cs.quotations.printValid", { date: formatDMY(data.q.valid_until) }) }}</p>
        <p v-if="data.q.notes" class="pre">{{ data.q.notes }}</p>
      </section>

      <!-- signatures -->
      <section class="signs">
        <div><p class="muted">{{ t("cs.quotations.printSign") }}</p><div class="line" /></div>
        <div><p class="muted">{{ t("cs.quotations.printCustomerSign") }}</p><div class="line" /></div>
      </section>

      <!-- contact details at the bottom of every page -->
      <footer class="foot">
        <span dir="ltr">{{ COMPANY.email }}</span>
        <span>·</span>
        <span>{{ COMPANY.address }}</span>
        <span>·</span>
        <span dir="ltr">{{ COMPANY.website }}</span>
      </footer>
    </article>
  </div>
</template>

<style scoped>
.wrap { background: #e9ecf1; min-height: 100vh; padding: 16px 0 40px; font-family: "Thmanyah Sans", "Segoe UI", Tahoma, sans-serif; color: #111; }
.toolbar { max-width: 210mm; margin: 0 auto 12px; display: flex; flex-wrap: wrap; align-items: center; gap: 8px; padding: 0 8px; }
.btn { background: #12376b; color: #fff; border: 0; border-radius: 8px; padding: 8px 16px; font: inherit; cursor: pointer; text-decoration: none; }
.btn.ghost { background: #fff; color: #12376b; border: 1px solid #c8cfdc; }
.hint { color: #555; font-size: 13px; }
.empty { text-align: center; padding: 40px; color: #555; }

/* one A4 width on screen; the browser cuts the pages when printing */
.sheet { position: relative; width: 210mm; min-height: 297mm; margin: 0 auto; background: #fff; padding: 14mm 14mm 24mm; box-shadow: 0 2px 12px rgba(0, 0, 0, 0.18); font-size: 10.5pt; line-height: 1.6; box-sizing: border-box; }
.head { display: flex; justify-content: space-between; align-items: flex-start; gap: 8mm; padding-bottom: 5mm; border-bottom: 2px solid #12376b; }
.brand { display: flex; align-items: center; gap: 4mm; }
.logo { width: 32mm; height: auto; }
.company { font-size: 13pt; font-weight: 700; color: #12376b; margin: 0; }
.company-en { font-size: 9pt; color: #2a9fd8; margin: 0; }
.doc { text-align: start; }
.doc p { margin: 0; }
.doc-title { font-size: 18pt; font-weight: 700; color: #12376b; }
.customer { margin: 6mm 0 5mm; padding: 4mm; background: #f3f6fb; border-radius: 3mm; }
.customer p { margin: 0; }
.lines { width: 100%; border-collapse: collapse; }
.lines th { background: #12376b; color: #fff; font-weight: 600; padding: 2.5mm 2mm; text-align: start; font-size: 9.5pt; }
.lines td { padding: 2.2mm 2mm; border-bottom: 1px solid #dfe5ee; vertical-align: top; }
.lines tbody tr:nth-child(even) td { background: #f8fafc; }
.lines .n { width: 8mm; text-align: center; }
.lines .c { text-align: center; white-space: nowrap; }
.lines tr { break-inside: avoid; }
.totals { width: 75mm; margin: 5mm 0 0 auto; margin-inline-start: auto; margin-inline-end: 0; break-inside: avoid; }
.totals div { display: flex; justify-content: space-between; padding: 1.2mm 0; }
.totals .grand { border-top: 2px solid #12376b; margin-top: 1mm; padding-top: 2mm; font-size: 13pt; font-weight: 700; color: #12376b; }
.terms { margin-top: 7mm; break-inside: avoid; }
.terms p { margin: 0 0 1mm; }
.pre { white-space: pre-line; }
.signs { display: grid; grid-template-columns: 1fr 1fr; gap: 14mm; margin-top: 14mm; break-inside: avoid; }
.signs .line { border-bottom: 1px solid #555; height: 14mm; }
.foot { position: absolute; bottom: 8mm; left: 14mm; right: 14mm; display: flex; justify-content: center; flex-wrap: wrap; gap: 2mm; font-size: 8.5pt; color: #12376b; border-top: 1px solid #dfe5ee; padding-top: 2mm; }
.muted { color: #667085; }
.small { font-size: 9pt; }
.strong { font-weight: 700; }
.big { font-size: 12pt; }

@media print {
  /* every printed page keeps its margins; the bottom one holds the contact line */
  @page { size: A4; margin: 14mm 14mm 22mm; }
  .wrap { background: none; padding: 0; min-height: 0; }
  .no-print { display: none !important; }
  .sheet { width: auto; min-height: 0; box-shadow: none; margin: 0; padding: 0; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
  /* the contact line repeats at the bottom of every printed page, in the bottom margin */
  .foot { position: fixed; bottom: -14mm; left: 0; right: 0; }
  .lines thead { display: table-header-group; }
}
</style>
