<script setup lang="ts">
// An installation / operation / inspection work order printed on A4: the company, who it is for, the date,
// the technician, the notes and the customer's signature. /print/work-order/<id>
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

interface W {
  number: string; kind: "installation" | "operation" | "inspection"; subject_name: string; subject_phone: string | null; subject_address: string | null;
  work_date: string; note: string | null; done_note: string | null; done_on: string | null; status: "pending" | "done"; signature_path: string | null; lead_id: string | null;
  technician: { full_name: string | null; email: string } | null;
}
const signatureUrl = ref<string | null>(null);
const { data, status } = await useAsyncData(`print-work-order-${id}`, async () => {
  const { data: w } = await supabase
    .from("cs_work_orders")
    .select("number, kind, subject_name, subject_phone, subject_address, work_date, note, done_note, done_on, status, signature_path, lead_id, technician:profiles!technician_id(full_name, email)")
    .eq("id", id)
    .maybeSingle();
  return (w as unknown as W | null) ?? null;
});
// the signature is a private file: a short-lived link, loaded before the print dialog opens
onMounted(async () => {
  if (data.value?.signature_path) {
    const { data: s } = await supabase.storage.from("visit-signatures").createSignedUrl(data.value.signature_path, 600);
    signatureUrl.value = s?.signedUrl ?? null;
  }
});
function doPrint() {
  window.print();
}
useHead({ title: computed(() => (data.value ? `${data.value.number} - ${data.value.subject_name}` : "")) });
</script>

<template>
  <div class="wrap">
    <div class="no-print toolbar">
      <button type="button" class="btn" @click="doPrint">{{ t("cs.quotations.print") }}</button>
      <NuxtLink to="/cs/work-orders" class="btn ghost">{{ t("cs.workOrders.backToList") }}</NuxtLink>
      <span class="hint">{{ t("cs.quotations.printHint") }}</span>
    </div>
    <p v-if="status === 'pending'" class="empty">…</p>
    <p v-else-if="!data" class="empty">{{ t("cs.workOrders.notFound") }}</p>
    <article v-else class="sheet" dir="rtl">
      <header class="head">
        <div class="brand">
          <img src="/acropol-logo.png" alt="Acropol" class="logo" />
          <div>
            <p class="company">{{ COMPANY.nameAr }}</p>
            <p class="company-en" dir="ltr">{{ COMPANY.nameEn }}</p>
          </div>
        </div>
        <div class="doc">
          <p class="doc-title">{{ t("cs.workOrders.printTitle") }}</p>
          <p class="kind">{{ t(`cs.workOrders.kind.${data.kind}`) }}</p>
          <p><span class="muted">{{ t("cs.quotations.number") }}:</span> <bdi dir="ltr" class="strong">{{ data.number }}</bdi></p>
          <p><span class="muted">{{ t(data.status === "done" ? "cs.workOrders.doneOn" : "cs.workOrders.plannedDate") }}:</span> {{ formatDMY(data.status === "done" ? (data.done_on ?? data.work_date) : data.work_date) }}</p>
          <p v-if="data.status === 'pending'" class="strong">{{ t("cs.workOrders.pending") }}</p>
        </div>
      </header>

      <section class="subject">
        <p class="muted small">{{ t(data.lead_id ? "cs.workOrders.lead" : "cs.workOrders.customer") }}</p>
        <p class="strong big">{{ data.subject_name }}</p>
        <p v-if="data.subject_phone"><bdi dir="ltr">{{ data.subject_phone }}</bdi></p>
        <p v-if="data.subject_address">{{ data.subject_address }}</p>
      </section>

      <section class="row">
        <p class="muted">{{ t("cs.workOrders.technician") }}</p>
        <p class="strong">{{ data.technician?.full_name || data.technician?.email || "—" }}</p>
      </section>

      <section class="notes">
        <p class="muted">{{ t(data.done_note ? "cs.workOrders.instructionsLabel" : "cs.workOrders.notes") }}</p>
        <p class="pre">{{ data.note || "—" }}</p>
      </section>
      <section v-if="data.done_note" class="notes">
        <p class="muted">{{ t("cs.workOrders.doneNoteLabel") }}</p>
        <p class="pre">{{ data.done_note }}</p>
      </section>

      <section class="signs">
        <div>
          <p class="muted">{{ t("cs.workOrders.customerSign") }}</p>
          <div class="box"><img v-if="signatureUrl" :src="signatureUrl" alt="" /></div>
        </div>
        <div>
          <p class="muted">{{ t("cs.quotations.printSign") }}</p>
          <div class="box" />
        </div>
      </section>

      <footer class="foot">
        <span dir="ltr">{{ COMPANY.email }}</span><span>·</span><span>{{ COMPANY.address }}</span><span>·</span><span dir="ltr">{{ COMPANY.website }}</span>
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
.sheet { position: relative; width: 210mm; min-height: 297mm; margin: 0 auto; background: #fff; padding: 14mm 14mm 24mm; box-shadow: 0 2px 12px rgba(0, 0, 0, 0.18); font-size: 11pt; line-height: 1.7; box-sizing: border-box; }
.head { display: flex; justify-content: space-between; align-items: flex-start; gap: 8mm; padding-bottom: 5mm; border-bottom: 2px solid #12376b; }
.brand { display: flex; align-items: center; gap: 4mm; }
.logo { width: 32mm; height: auto; }
.company { font-size: 13pt; font-weight: 700; color: #12376b; margin: 0; }
.company-en { font-size: 9pt; color: #2a9fd8; margin: 0; }
.doc p { margin: 0; }
.doc-title { font-size: 18pt; font-weight: 700; color: #12376b; }
.kind { font-size: 13pt; font-weight: 700; color: #2a9fd8; }
.subject { margin: 6mm 0 4mm; padding: 4mm; background: #f3f6fb; border-radius: 3mm; }
.subject p, .row p, .notes p { margin: 0; }
.row { display: flex; gap: 6mm; padding: 2mm 0; border-bottom: 1px solid #dfe5ee; }
.notes { margin-top: 5mm; min-height: 45mm; }
.pre { white-space: pre-line; }
.signs { display: grid; grid-template-columns: 1fr 1fr; gap: 14mm; margin-top: 12mm; break-inside: avoid; }
.box { border: 1px solid #98a2b3; height: 32mm; display: flex; align-items: center; justify-content: center; }
.box img { max-width: 100%; max-height: 100%; }
.foot { position: absolute; bottom: 8mm; left: 14mm; right: 14mm; display: flex; justify-content: center; flex-wrap: wrap; gap: 2mm; font-size: 8.5pt; color: #12376b; border-top: 1px solid #dfe5ee; padding-top: 2mm; }
.muted { color: #667085; }
.small { font-size: 9pt; }
.strong { font-weight: 700; }
.big { font-size: 12pt; }
@media print {
  @page { size: A4; margin: 14mm 14mm 22mm; }
  .wrap { background: none; padding: 0; min-height: 0; }
  .no-print { display: none !important; }
  .sheet { width: auto; min-height: 0; box-shadow: none; margin: 0; padding: 0; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
  .foot { position: fixed; bottom: -14mm; left: 0; right: 0; }
}
</style>
