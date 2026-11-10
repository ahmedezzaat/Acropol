<script setup lang="ts">
// The printed contract on the company letterhead, cut into real A4 pages (what you see is what prints). Use
// "Print / Save as PDF". /print/contract/<document id>
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

// ---- the contract as a list of pieces; they are measured and then put on pages
const atoms = computed<ContractAtomData[]>(() => {
  if (!tpl.value || !v.value) return [];
  const x = v.value;
  const list: ContractAtomData[] = [
    { t: "title", text: "عقد إتفـاق", keep: true },
    { t: "center", text: `الموافق : ${dmy.value}` },
    { t: "party", text: "(الطرف الاول)", keep: true },
    { t: "p", text: `انه في يوم - ${weekday.value} : تم الإتفاق بين` },
    { t: "p", text: "كل من السادة:" },
    { t: "line", label: "المالك او من ينوب عنه :", text: x.ownerName },
    { t: "line", label: "عنوان الوحده :", text: x.unitAddress },
    { t: "line", label: "رقم العميل:", text: x.customerPhone, ltr: true },
    { t: "party", text: "(الطرف الثانى)", keep: true },
    { t: "u", text: "ثانياً:", keep: true },
    { t: "p", text: "شركة اكروبول لحلول الطاقة الجديدة والمتجددة ش.م.م ويمثلها السيد : مصطفى محمود الزغبى بصفتة العضو المنتدب – سجل تجارى رقم 379219 بطاقة ضريبية رقم 703 – 710 - 227 الشركات الفردى الكائن مقرها عمارة 20 ب عمارات العبور - صلاح سالم - القاهرة (ويرمز له فى هذا العقد بالمورد)" },
    { t: "p", text: `(طرف ثانى) ويمثلها في هذا العقد بصفته مفوضاً من الشركة السيد : ${x.representative}` },
  ];
  for (const b of tpl.value.blocks(x, refNo.value)) {
    if (b.heading) list.push({ t: b.heading === "تمهيد" ? "intro" : "h2", text: b.heading, keep: true });
    for (const it of b.items) list.push({ t: "p", text: it.text, bold: it.bold, keep: it.bold && it.text === "شروط الضمان" });
  }
  list.push({ t: "sigTitle", text: "التوقيعـــــــات", keep: true });
  list.push({ t: "sig", owner: x.ownerName, rep: x.representative });
  return list;
});

// ---- cut into A4 pages: measure each piece at the printed width, then fill page after page
const MM = 96 / 25.4;
const TOP_MM = 38; // the letterhead's logo
const RUNHEAD_MM = 14; // Ref No. / Date line and the space under it
const BOTTOM_MM = 40; // the letterhead's footer and the space above it
const USABLE_PX = (297 - TOP_MM - RUNHEAD_MM - BOTTOM_MM) * MM;
const measureEl = ref<HTMLElement | null>(null);
const pages = ref<ContractAtomData[][]>([]);
const ready = ref(false);

async function paginate() {
  await nextTick();
  const nodes = Array.from(measureEl.value?.querySelectorAll<HTMLElement>(".measure-atom") ?? []);
  if (!nodes.length || nodes.length !== atoms.value.length) return;
  const heights = nodes.map((n) => n.offsetHeight);
  const out: ContractAtomData[][] = [[]];
  let used = 0;
  let i = 0;
  while (i < atoms.value.length) {
    // a heading goes with the piece that follows it
    let j = i;
    let h = heights[j]!;
    while (atoms.value[j]!.keep && j + 1 < atoms.value.length) {
      j++;
      h += heights[j]!;
    }
    if (used + h > USABLE_PX && out[out.length - 1]!.length) {
      out.push([]);
      used = 0;
    }
    for (let k = i; k <= j; k++) out[out.length - 1]!.push(atoms.value[k]!);
    used += h;
    i = j + 1;
  }
  pages.value = out;
  ready.value = true;
}
onMounted(async () => {
  if (!doc.value) return;
  await document.fonts?.ready;
  await paginate();
  if (route.query.print === "1") setTimeout(() => window.print(), 300);
});
watch(atoms, () => {
  if (import.meta.client && doc.value) {
    ready.value = false;
    paginate();
  }
});

// the file name of the saved PDF: the reference and the owner
useHead({ title: computed(() => (doc.value && v.value ? `${refNo.value} - ${v.value.ownerName}` : "")) });
function doPrint() {
  window.print();
}
</script>

<template>
  <div class="doc-wrap">
    <div class="no-print toolbar">
      <button type="button" class="btn" :disabled="!ready" @click="doPrint">{{ t("crm.contracts.doc.print") }}</button>
      <NuxtLink v-if="doc && (doc.contract_id || doc.deal_id)" :to="doc.contract_id ? `/crm/contracts/${doc.contract_id}` : `/crm/deals/${doc.deal_id}`" class="btn ghost">{{ t("crm.contracts.doc.back") }}</NuxtLink>
      <span class="hint">{{ t("crm.contracts.doc.printHint") }}</span>
    </div>

    <p v-if="status === 'pending'" class="empty">…</p>
    <p v-else-if="!doc || !tpl || !v" class="empty">{{ t("crm.contracts.doc.notFound") }}</p>

    <template v-else>
      <!-- hidden: the pieces at the printed width, only to measure them -->
      <div ref="measureEl" class="measure" dir="rtl" aria-hidden="true">
        <div v-for="(a, i) in atoms" :key="i" class="measure-atom"><ContractAtom :a="a" /></div>
      </div>

      <p v-if="!ready" class="empty">…</p>
      <section v-for="(pg, n) in pages" :key="n" class="page" dir="rtl">
        <img class="bg" src="/contract-letterhead.jpg" alt="" />
        <div class="runhead" dir="ltr"><span>Ref No. {{ refNo }}</span><span>Date: {{ headDate }}</span></div>
        <div class="body"><ContractAtom v-for="(a, i) in pg" :key="i" :a="a" /></div>
        <div class="pageno" dir="ltr">{{ n + 1 }} / {{ pages.length }}</div>
      </section>
    </template>
  </div>
</template>

<style scoped>
.doc-wrap { background: #e9ecf1; min-height: 100vh; padding: 16px 0 40px; font-family: "Thmanyah Sans", "Segoe UI", Tahoma, sans-serif; color: #111; }
.toolbar { max-width: 210mm; margin: 0 auto 12px; display: flex; flex-wrap: wrap; align-items: center; gap: 8px; padding: 0 8px; }
.btn { background: #2b3a5c; color: #fff; border: 0; border-radius: 8px; padding: 8px 16px; font: inherit; cursor: pointer; text-decoration: none; }
.btn:disabled { opacity: 0.5; cursor: wait; }
.btn.ghost { background: #fff; color: #2b3a5c; border: 1px solid #c8cfdc; }
.hint { color: #555; font-size: 13px; }
.empty { text-align: center; padding: 40px; color: #555; }

/* the text area: 172 mm wide, the same width the pieces are measured at */
.measure { position: absolute; left: -10000px; top: 0; width: 172mm; visibility: hidden; font-size: 11pt; line-height: 1.75; text-align: justify; pointer-events: none; }

/* one A4 sheet; the letterhead is a picture inside it, so every page has it on screen and in the PDF */
.page { position: relative; width: 210mm; height: 297mm; margin: 0 auto 10mm; background: #fff; overflow: hidden; box-shadow: 0 2px 12px rgba(0, 0, 0, 0.2); }
.bg { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: fill; }
.runhead { position: absolute; top: 38mm; left: 24mm; right: 14mm; height: 9mm; display: flex; justify-content: space-between; font-size: 10pt; color: #222; }
.body { position: absolute; top: 52mm; bottom: 40mm; left: 24mm; right: 14mm; font-size: 11pt; line-height: 1.75; text-align: justify; overflow: hidden; }
.pageno { position: absolute; bottom: 24mm; left: 24mm; font-size: 8.5pt; color: #555; }

@media print {
  @page { size: A4; margin: 0; }
  .doc-wrap { background: none; padding: 0; min-height: 0; }
  .no-print, .measure, .empty { display: none !important; }
  /* a hair under 297 mm so a rounding error never adds an empty sheet */
  .page { margin: 0; box-shadow: none; height: 296.6mm; break-after: page; page-break-after: always; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
  .page:last-of-type { break-after: auto; page-break-after: auto; }
}
</style>
