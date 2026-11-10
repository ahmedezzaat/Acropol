<script setup lang="ts">
// The printed contract on the company letterhead. Open it and use "Print / Save as PDF" (the browser's own PDF
// maker keeps the Arabic exactly as shown). /print/contract/<document id>
definePageMeta({ layout: false });

const route = useRoute();
const docId = route.params.id as string;
const supabase = useSupabaseClient();
const { t } = useI18n();

interface DocRow { id: string; contract_id: string | null; deal_id: string | null; template_key: string; year: number; seq: number; doc_date: string; variables: ContractDocVars }
const { data: doc, status } = await useAsyncData(`contract-doc-${docId}`, async () => {
  const { data } = await supabase.from("contract_documents").select("id, contract_id, deal_id, template_key, year, seq, doc_date, variables").eq("id", docId).maybeSingle();
  return (data ?? null) as unknown as DocRow | null;
});

const tpl = computed(() => (doc.value ? templateByKey(doc.value.template_key) : null));
const v = computed(() => doc.value?.variables ?? null);
const refNo = computed(() => (doc.value && tpl.value ? contractRef(tpl.value.prefix, doc.value.year, doc.value.seq) : ""));
const date = computed(() => (doc.value ? new Date(`${doc.value.doc_date}T12:00:00`) : null));
const headDate = computed(() => (date.value ? new Intl.DateTimeFormat("en-GB", { day: "numeric", month: "long", year: "numeric" }).format(date.value) : ""));
const weekday = computed(() => (date.value ? new Intl.DateTimeFormat("ar-EG", { weekday: "long" }).format(date.value) : ""));
const dmy = computed(() => (date.value ? `${date.value.getDate()} / ${date.value.getMonth() + 1} / ${date.value.getFullYear()}` : ""));
const blocks = computed(() => (tpl.value && v.value ? tpl.value.blocks(v.value, refNo.value) : []));

// the file name of the saved PDF: the reference and the owner
useHead({ title: computed(() => (doc.value && v.value ? `${refNo.value} - ${v.value.ownerName}` : "")) });

function doPrint() {
  window.print();
}
onMounted(async () => {
  if (route.query.print === "1" && doc.value) {
    await document.fonts?.ready;
    setTimeout(() => window.print(), 300);
  }
});
</script>

<template>
  <div class="doc-wrap">
    <div class="no-print toolbar">
      <button type="button" class="btn" @click="doPrint">{{ t("crm.contracts.doc.print") }}</button>
      <NuxtLink v-if="doc && (doc.contract_id || doc.deal_id)" :to="doc.contract_id ? `/crm/contracts/${doc.contract_id}` : `/crm/deals/${doc.deal_id}`" class="btn ghost">{{ t("crm.contracts.doc.back") }}</NuxtLink>
      <span class="hint">{{ t("crm.contracts.doc.printHint") }}</span>
    </div>

    <p v-if="status === 'pending'" class="empty">…</p>
    <p v-else-if="!doc || !tpl || !v" class="empty">{{ t("crm.contracts.doc.notFound") }}</p>

    <template v-else>
      <!-- the letterhead behind every printed page -->
      <div class="letterhead print-only" aria-hidden="true" />
      <article class="paper" dir="rtl">
        <table class="flow">
          <thead>
            <tr>
              <td>
                <div class="sp-top" />
                <div class="runhead" dir="ltr"><span>Ref No. {{ refNo }}</span><span>Date: {{ headDate }}</span></div>
              </td>
            </tr>
          </thead>
          <tfoot>
            <tr><td><div class="sp-bottom" /></td></tr>
          </tfoot>
          <tbody>
            <tr>
              <td class="content">
                <h1 class="title">عقد إتفـاق</h1>
                <p class="center">الموافق : {{ dmy }}</p>

                <p class="party">(الطرف الاول)</p>
                <p>انه في يوم - {{ weekday }} : تم الإتفاق بين</p>
                <p>كل من السادة:</p>
                <p><b>المالك او من ينوب عنه :</b> {{ v.ownerName }}</p>
                <p><b>عنوان الوحده :</b> {{ v.unitAddress }}</p>
                <p><b>رقم العميل:</b> <bdi dir="ltr">{{ v.customerPhone }}</bdi></p>

                <p class="party">(الطرف الثانى)</p>
                <p class="u">ثانياً:</p>
                <p>شركة اكروبول لحلول الطاقة الجديدة والمتجددة ش.م.م ويمثلها السيد : مصطفى محمود الزغبى بصفتة العضو المنتدب – سجل تجارى رقم 379219 بطاقة ضريبية رقم 703 – 710 - 227 الشركات الفردى الكائن مقرها عمارة 20 ب عمارات العبور - صلاح سالم - القاهرة (ويرمز له فى هذا العقد بالمورد)</p>
                <p>(طرف ثانى) ويمثلها في هذا العقد بصفته مفوضاً من الشركة السيد : {{ v.representative }}</p>

                <section v-for="(b, i) in blocks" :key="i" class="clause" :class="b.heading === 'تمهيد' && 'intro'">
                  <h2 v-if="b.heading" :class="b.heading === 'تمهيد' ? 'intro-title' : 'u'">{{ b.heading }}</h2>
                  <p v-for="(it, j) in b.items" :key="j" :class="{ bold: it.bold }">{{ it.text }}</p>
                </section>

                <p class="u sig-title">التوقيعـــــــات</p>
                <div class="sigs">
                  <div>
                    <p class="bold">الطرف الأول أو من ينوب عنه</p>
                    <p>السيد / {{ v.ownerName }}</p>
                  </div>
                  <div>
                    <p class="bold">الطرف الثاني</p>
                    <p>شركة اكروبول :</p>
                    <p>توقيع ممثل الشركه / {{ v.representative }}</p>
                  </div>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </article>
    </template>
  </div>
</template>

<style scoped>
.doc-wrap { background: #e9ecf1; min-height: 100vh; padding: 16px 0 40px; font-family: "Thmanyah Sans", "Segoe UI", Tahoma, sans-serif; color: #111; }
.toolbar { max-width: 210mm; margin: 0 auto 12px; display: flex; flex-wrap: wrap; align-items: center; gap: 8px; padding: 0 8px; }
.btn { background: #2b3a5c; color: #fff; border: 0; border-radius: 8px; padding: 8px 16px; font: inherit; cursor: pointer; text-decoration: none; }
.btn.ghost { background: #fff; color: #2b3a5c; border: 1px solid #c8cfdc; }
.hint { color: #555; font-size: 13px; }
.empty { text-align: center; padding: 40px; color: #555; }

/* the paper: one A4 width; on screen the letterhead repeats down it, when printing it is fixed behind each page */
.paper { width: 210mm; margin: 0 auto; background: #fff url("/contract-letterhead.jpg") repeat-y top center / 210mm 297mm; box-shadow: 0 2px 12px rgba(0, 0, 0, 0.18); }
.letterhead { display: none; }
.flow { width: 100%; border-collapse: collapse; }
.sp-top { height: 38mm; }
.sp-bottom { height: 32mm; }
.runhead { display: flex; justify-content: space-between; padding: 0 14mm 0 24mm; font-size: 10pt; color: #222; margin-bottom: 4mm; }
.content { padding: 0 14mm 0 24mm; font-size: 11pt; line-height: 1.7; text-align: justify; vertical-align: top; }
.content p { margin: 0 0 1mm; }
.title { text-align: center; font-size: 17pt; text-decoration: underline; margin: 0 0 2mm; }
.center { text-align: center; }
.party { font-weight: 700; margin-top: 3mm !important; }
.u { text-decoration: underline; font-weight: 700; }
.bold { font-weight: 700; }
.clause { break-inside: auto; margin-top: 2.2mm; }
.clause h2 { font-size: 12pt; margin: 0 0 1mm; break-after: avoid; }
.intro-title { text-align: center; font-size: 15pt !important; text-decoration: underline; }
.sig-title { margin-top: 8mm !important; text-align: center; }
.sigs { display: grid; grid-template-columns: 1fr 1fr; gap: 12mm; margin-top: 4mm; break-inside: avoid; }
.print-only { display: none; }

@media print {
  @page { size: A4; margin: 0; }
  .doc-wrap { background: none; padding: 0; }
  .no-print { display: none !important; }
  .paper { width: auto; box-shadow: none; background: none; margin: 0; }
  .letterhead { display: block; position: fixed; inset: 0; z-index: -1; background: url("/contract-letterhead.jpg") center / 100% 100% no-repeat; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
  .flow thead { display: table-header-group; }
  .flow tfoot { display: table-footer-group; }
}
</style>
