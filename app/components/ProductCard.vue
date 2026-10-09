<script setup lang="ts">
// One Customer Service product: its funnel with the date of every stage, the
// contract / warranty / payment details, the instruments package and notes.
// The page decides what goes beside it: `actions` (header, right) and `extra`
// (between the details and the instruments).
const props = defineProps<{
  product: CsProduct;
  dates: Map<string, string>;
  items?: CsProductItem[];
  categoryName?: string | null;
  salesPersonName?: string | null;
}>();

const { t } = useI18n();
const { stagesOf, stageById, stageName, stageColor, stageLimitDays, dateOf, daysSince, formatDate } = useCs();

const p = computed(() => props.product);
const items = computed(() => props.items ?? []);

const warrantyColor = { in_warranty: "success", out_of_warranty: "neutral" } as const;
const paymentColor = { paid: "success", unpaid: "error" } as const;

// A step in the funnel is "reached" once the product is at or past it.
function stepState(prod: CsProduct, stageId: string) {
  const list = stagesOf(prod.pipeline_id);
  const here = list.findIndex((s) => s.id === prod.stage_id);
  const i = list.findIndex((s) => s.id === stageId);
  if (i === here) return "current";
  return i < here ? "done" : "todo";
}
const stepClass = {
  current: "border-primary bg-primary text-inverted",
  done: "border-primary/40 bg-primary/10 text-primary",
  todo: "border-default bg-default text-muted",
} as const;

// Days in the current stage, and whether that is past the stage's maximum stay.
function daysInCurrent(prod: CsProduct) {
  return daysSince(dateOf(props.dates, prod.id, prod.stage_id) ?? prod.contract_date);
}
function isOverdue(prod: CsProduct) {
  const limit = stageLimitDays(stageById(prod.stage_id));
  const days = daysInCurrent(prod);
  return limit !== null && days !== null && days > limit;
}
</script>

<template>
<article class="space-y-4 border border-default bg-default p-4" :class="isOverdue(p) && 'border-s-4 border-s-error'">
  <div class="flex flex-wrap items-start justify-between gap-2">
    <div class="min-w-0">
      <h4 class="font-semibold text-highlighted">
        {{ p.name }}
        <bdi v-if="p.contract_code" dir="ltr" class="ms-1 text-xs font-normal text-muted">#{{ p.contract_code }}</bdi>
      </h4>
      <div class="mt-1.5 flex flex-wrap items-center gap-1.5">
        <UBadge :label="stageName(p.stage_id)" :color="stageColor(p.stage_id)" variant="subtle" size="sm" class="cds-tag" />
        <UBadge
          v-if="isOverdue(p)"
          :label="t('cs.installations.overdue', { days: daysInCurrent(p) ?? 0 })"
          icon="i-lucide-triangle-alert"
          color="error"
          variant="subtle"
          size="sm"
          class="cds-tag"
        />
        <UBadge v-if="categoryName" :label="categoryName" color="neutral" variant="outline" size="sm" class="cds-tag" />
        <UBadge
          v-if="p.warranty_status"
          :label="t(`cs.profile.warranty.${p.warranty_status}`)"
          icon="i-lucide-shield"
          :color="warrantyColor[p.warranty_status as keyof typeof warrantyColor] ?? 'neutral'"
          variant="subtle"
          size="sm"
          class="cds-tag"
        />
        <UBadge
          v-if="p.payment_status"
          :label="t(`cs.profile.payment.${p.payment_status}`)"
          icon="i-lucide-banknote"
          :color="paymentColor[p.payment_status as keyof typeof paymentColor] ?? 'neutral'"
          variant="subtle"
          size="sm"
          class="cds-tag"
        />
      </div>
    </div>
    <slot name="actions" />
  </div>

  <!-- Funnel: the pipeline's stages in order, each with its date. More
  stages than fit a phone simply scroll sideways. -->
  <div class="overflow-x-auto">
    <ol
      class="grid gap-1.5 sm:gap-2"
      :style="{ gridTemplateColumns: `repeat(${stagesOf(p.pipeline_id).length}, minmax(${stagesOf(p.pipeline_id).length > 6 ? '4.5rem' : '0'}, 1fr))` }"
    >
      <li
        v-for="st in stagesOf(p.pipeline_id)"
        :key="st.id"
        class="border px-1 py-2 text-center"
        :class="stepClass[stepState(p, st.id)]"
        :aria-current="stepState(p, st.id) === 'current' ? 'step' : undefined"
      >
        <div class="text-xs font-semibold sm:text-sm">{{ st.name }}</div>
        <div class="mt-0.5 text-[10px] sm:text-xs" :class="stepState(p, st.id) === 'current' ? 'opacity-90' : ''">
          {{ formatDate(dateOf(props.dates, p.id, st.id)) }}
        </div>
      </li>
    </ol>
  </div>

  <div class="grid gap-x-8 gap-y-1 text-sm md:grid-cols-2">
    <dl class="divide-y divide-default">
      <div class="flex justify-between gap-3 py-2">
        <dt class="text-muted">{{ t("cs.profile.salesPerson") }}</dt>
        <dd class="font-medium text-highlighted">{{ salesPersonName || "—" }}</dd>
      </div>
      <div class="flex justify-between gap-3 py-2">
        <dt class="text-muted">{{ t("cs.profile.contractCode") }}</dt>
        <dd class="font-medium text-highlighted" dir="auto">{{ p.contract_code || "—" }}</dd>
      </div>
      <div class="flex justify-between gap-3 py-2">
        <dt class="text-muted">{{ t("cs.profile.contractDate") }}</dt>
        <dd class="font-medium text-highlighted">{{ formatDate(p.contract_date) }}</dd>
      </div>
      <div class="flex justify-between gap-3 py-2">
        <dt class="text-muted">{{ t("cs.profile.operationDate") }}</dt>
        <dd class="font-medium text-highlighted">{{ formatDate(p.operation_date) }}</dd>
      </div>
    </dl>
    <dl class="divide-y divide-default">
      <div class="flex justify-between gap-3 py-2">
        <dt class="text-muted">{{ t("cs.profile.warrantyLabel") }}</dt>
        <dd class="font-medium text-highlighted">{{ p.warranty_status ? t(p.warranty_status === "in_warranty" ? "cs.profile.yes" : "cs.profile.no") : "—" }}</dd>
      </div>
      <div class="flex justify-between gap-3 py-2">
        <dt class="text-muted">{{ t("cs.profile.paymentLabel") }}</dt>
        <dd class="font-medium text-highlighted">{{ p.payment_status ? t(p.payment_status === "paid" ? "cs.profile.yes" : "cs.profile.no") : "—" }}</dd>
      </div>
      <div v-if="p.warranty_details" class="py-2">
        <dt class="text-muted">{{ t("cs.profile.warrantyDetails") }}</dt>
        <dd class="mt-0.5 whitespace-pre-line text-toned">{{ p.warranty_details }}</dd>
      </div>
    </dl>
  </div>

  <slot name="extra" />

  <!-- Package of instruments -->
  <div v-if="items.length">
    <h5 class="mb-2 text-xs font-semibold uppercase tracking-wide text-muted">{{ t("cs.profile.items") }}</h5>
    <ul class="divide-y divide-default border border-default">
      <li v-for="i in items" :key="i.id" class="flex items-center justify-between gap-3 px-3 py-2 text-sm">
        <span class="min-w-0 truncate" dir="auto">{{ i.name }}</span>
        <span class="shrink-0 font-semibold text-highlighted">{{ i.quantity }}<span v-if="i.unit" class="ms-1 font-normal text-muted">{{ i.unit }}</span></span>
      </li>
    </ul>
  </div>

  <div v-if="p.notes" class="flex gap-2 bg-muted p-3 text-sm text-toned">
    <UIcon name="i-lucide-sticky-note" class="mt-0.5 size-4 shrink-0 text-muted" />
    <p class="whitespace-pre-line">{{ p.notes }}</p>
  </div>
</article>
</template>
