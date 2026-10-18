<script setup lang="ts">
// The confirmed visits laid out on a calendar grid, for one week or one month,
// so empty days (gaps) and crowded days are easy to see. Weeks start on Saturday.
// A visit is the products of one customer on one day (see confirmed-visits.vue).
interface CalendarVisit {
  key: string;
  customerId: string;
  at: number;
  products: { id: string; name: string; quantity?: number }[];
  technicianIds: (string | null)[];
}

const props = defineProps<{
  visits: CalendarVisit[];
  mode: "week" | "month";
  // the first day of the range shown: a Saturday for a week, the 1st for a month
  start: Date;
  customerTitle: (customerId: string) => string;
  techName: (id: string | null | undefined) => string | null;
}>();
const emit = defineEmits<{ select: [visit: CalendarVisit] }>();

const { t, locale } = useI18n();

const dayMs = 86_400_000;
const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate());
const weekdayName = (d: Date) => d.toLocaleDateString(locale.value === "ar" ? "ar-EG-u-nu-latn" : "en", { weekday: "long" });
const monthName = (d: Date) => d.toLocaleDateString(locale.value === "ar" ? "ar-EG-u-nu-latn" : "en", { month: "long", year: "numeric" });

const todayKey = computed(() => startOfDay(new Date()).getTime());

// Every day cell of the grid, in rows of seven.
const days = computed(() => {
  const first = startOfDay(props.start);
  let from = first;
  let count = 7;
  if (props.mode === "month") {
    // start on the Saturday on or before the 1st, run to the Friday on or after the last day
    const offset = (first.getDay() + 1) % 7;
    from = new Date(first.getFullYear(), first.getMonth(), first.getDate() - offset);
    const last = new Date(first.getFullYear(), first.getMonth() + 1, 0);
    const tail = 6 - ((last.getDay() + 1) % 7);
    count = Math.round((startOfDay(new Date(last.getFullYear(), last.getMonth(), last.getDate() + tail)).getTime() - from.getTime()) / dayMs) + 1;
  }
  return Array.from({ length: count }, (_, i) => {
    const date = new Date(from.getFullYear(), from.getMonth(), from.getDate() + i);
    const begin = date.getTime();
    const list = props.visits.filter((v) => v.at >= begin && v.at < begin + dayMs).sort((a, b) => a.at - b.at);
    const inRange = props.mode === "week" || date.getMonth() === first.getMonth();
    // a gap is an empty day that can still be filled: today or later
    return { date, key: begin, list, inRange, gap: inRange && !list.length && begin >= todayKey.value };
  });
});
const clock = (ms: number) => formatClock(new Date(ms), locale.value);

const inRangeDays = computed(() => days.value.filter((d) => d.inRange));
const summary = computed(() => ({
  visits: inRangeDays.value.reduce((n, d) => n + d.list.length, 0),
  unassigned: inRangeDays.value.reduce((n, d) => n + d.list.filter((v) => v.technicianIds.some((id) => !id)).length, 0),
  empty: inRangeDays.value.filter((d) => d.gap).length,
}));

const title = computed(() => {
  if (props.mode === "month") return monthName(props.start);
  const end = new Date(props.start.getFullYear(), props.start.getMonth(), props.start.getDate() + 6);
  return `${formatDMY(props.start)} – ${formatDMY(end)}`;
});

function techLabel(v: CalendarVisit) {
  const ids = [...new Set(v.technicianIds)];
  if (ids.length > 1) return t("cs.confirmedVisits.mixed");
  return props.techName(ids[0] ?? null) || t("cs.maintenance.unassigned");
}
const assigned = (v: CalendarVisit) => v.technicianIds.every((id) => !!id);

// A week shows every visit of a day; a month shows the first few and the rest as a count.
const MONTH_LIMIT = 3;
</script>

<template>
  <div class="space-y-3">
    <div class="flex flex-wrap items-center justify-between gap-2">
      <h3 class="text-base font-semibold text-highlighted">{{ title }}</h3>
      <div class="flex flex-wrap items-center gap-2 text-xs text-muted">
        <KBadge :label="t('cs.confirmedVisits.calVisits', { count: summary.visits })" tone="primary" />
        <KBadge v-if="summary.unassigned" :label="t('cs.confirmedVisits.calUnassigned', { count: summary.unassigned })" tone="warning" />
        <KBadge :label="t('cs.confirmedVisits.calEmptyDays', { count: summary.empty })" :tone="summary.empty ? 'neutral' : 'success'" outlined />
      </div>
    </div>

    <div class="overflow-x-auto">
      <div class="grid min-w-[56rem] grid-cols-7 gap-2">
        <!-- Weekday names -->
        <template v-if="mode === 'month'">
          <div v-for="d in days.slice(0, 7)" :key="`h${d.key}`" class="px-1 text-center text-xs font-medium text-muted">{{ weekdayName(d.date) }}</div>
        </template>

        <div
          v-for="d in days"
          :key="d.key"
          class="kords-card flex flex-col gap-1.5 p-2"
          :class="[
            mode === 'week' ? 'min-h-48' : 'min-h-28',
            !d.inRange && 'opacity-40',
            d.gap && 'kords-gap',
            d.key === todayKey && 'kords-card-selected !border-solid',
          ]"
        >
          <div class="flex items-center justify-between gap-1">
            <div class="min-w-0">
              <div v-if="mode === 'week'" class="truncate text-xs font-medium text-muted">{{ weekdayName(d.date) }}</div>
              <div class="text-sm font-semibold" :class="d.key === todayKey ? 'text-primary' : 'text-highlighted'">
                {{ mode === "week" ? formatDMY(d.date) : d.date.getDate() }}
              </div>
            </div>
            <KBadge v-if="d.list.length" :label="String(d.list.length)" :tone="d.list.every(assigned) ? 'primary' : 'warning'" />
          </div>

          <p v-if="d.gap" class="my-auto text-center text-xs text-muted">{{ t("cs.confirmedVisits.calGap") }}</p>

          <button
            v-for="v in mode === 'month' ? d.list.slice(0, MONTH_LIMIT) : d.list"
            :key="v.key"
            type="button"
            class="rounded-[7px] border-s-4 bg-muted px-2 py-1 text-start text-xs transition-colors hover:bg-elevated"
            :class="assigned(v) ? 'border-s-primary' : 'border-s-warning'"
            :title="`${customerTitle(v.customerId)} · ${v.products.map((p) => p.name).join('، ')}`"
            @click="emit('select', v)"
          >
            <div class="flex items-center justify-between gap-1">
              <span class="font-medium text-highlighted">{{ clock(v.at) }}</span>
              <span class="text-muted">{{ v.products.length }}</span>
            </div>
            <div class="truncate text-toned">{{ customerTitle(v.customerId) }}</div>
            <div v-if="mode === 'week'" class="truncate" :class="assigned(v) ? 'text-muted' : 'text-warning'">{{ techLabel(v) }}</div>
          </button>
          <div v-if="mode === 'month' && d.list.length > MONTH_LIMIT" class="text-center text-xs text-muted">
            +{{ d.list.length - MONTH_LIMIT }}
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
