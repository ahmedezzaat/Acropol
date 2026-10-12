<script setup lang="ts">
// A key figure: an icon tile, the label and the number. Optionally a link.
//   <KStatsCard title="Customers" :value="146" icon="i-lucide-users" to="/cs/customers" />
// `tone` colours the number and the icon tile (error = needs attention, success = good).
const props = withDefaults(
  defineProps<{ title: string; value: string | number; icon?: string; to?: string; tone?: "default" | "success" | "error" | "warning" }>(),
  { icon: undefined, to: undefined, tone: "default" },
);
const valueClass = computed(() => ({ default: "text-highlighted", success: "text-success", error: "text-error", warning: "text-warning" })[props.tone]);
const tileClass = computed(
  () => ({ default: "bg-primary/10 text-primary", success: "bg-success/10 text-success", error: "bg-error/10 text-error", warning: "bg-warning/10 text-warning" })[props.tone],
);
</script>

<template>
  <UPageCard :to="to" class="kords-card">
    <div class="flex items-center gap-3">
      <span v-if="icon" class="flex size-10 shrink-0 items-center justify-center rounded-md" :class="tileClass">
        <UIcon :name="icon" class="size-5" />
      </span>
      <div class="min-w-0">
        <div class="truncate text-xs text-muted">{{ title }}</div>
        <div class="text-xl font-bold" :class="valueClass">{{ value }}</div>
        <slot />
      </div>
    </div>
  </UPageCard>
</template>
