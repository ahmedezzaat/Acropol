<script setup lang="ts">
// One piece of a printed contract (a heading, a paragraph, the signatures...). The contract page measures these to
// cut the contract into A4 pages, so each one carries its own spacing as padding.
defineProps<{ a: ContractAtomData }>();
</script>

<template>
  <div class="atom" :class="`atom-${a.t}`">
    <template v-if="a.t === 'title'"><h1>{{ a.text }}</h1></template>
    <template v-else-if="a.t === 'line'"><b>{{ a.label }}</b> <bdi :dir="a.ltr ? 'ltr' : undefined">{{ a.text }}</bdi></template>
    <template v-else-if="a.t === 'sig'">
      <div class="sigs">
        <div><p class="b">الطرف الأول أو من ينوب عنه</p><p>السيد / {{ a.owner }}</p></div>
        <div><p class="b">الطرف الثاني</p><p>شركة اكروبول :</p><p>توقيع ممثل الشركه / {{ a.rep }}</p></div>
      </div>
    </template>
    <template v-else><span :class="{ b: a.bold }">{{ a.text }}</span></template>
  </div>
</template>

<style scoped>
.atom { padding-bottom: 1.2mm; }
.atom-title h1 { text-align: center; font-size: 18pt; text-decoration: underline; margin: 0; padding-bottom: 1mm; }
.atom-center { text-align: center; }
.atom-party { font-weight: 700; padding-top: 2.5mm; }
.atom-u { text-decoration: underline; font-weight: 700; }
.atom-h2 { font-weight: 700; text-decoration: underline; font-size: 12pt; padding-top: 2.2mm; padding-bottom: 0.8mm; }
.atom-intro { font-weight: 700; text-decoration: underline; text-align: center; font-size: 15pt; padding-top: 3mm; }
.atom-sigTitle { font-weight: 700; text-decoration: underline; text-align: center; padding-top: 6mm; }
.sigs { display: grid; grid-template-columns: 1fr 1fr; gap: 12mm; padding-top: 3mm; }
.sigs p { margin: 0 0 1mm; }
.b { font-weight: 700; }
</style>
