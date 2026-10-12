<script setup lang="ts">
// A small status / label pill: light tint background + strong text (the Kords
// badge). Use the tones consistently: error = overdue, warning = upcoming,
// success = done, primary / secondary = informational.
//   <KBadge tone="success" label="Done" />   <KBadge tone="error" outlined label="Lost" />
type Tone = "primary" | "secondary" | "success" | "warning" | "error" | "info" | "neutral";
withDefaults(defineProps<{ tone?: Tone; outlined?: boolean; label?: string; icon?: string; size?: "xs" | "sm" | "md" }>(), {
  tone: "neutral",
  outlined: false,
  label: undefined,
  icon: undefined,
  size: "sm",
});
</script>

<template>
  <UBadge :color="tone" :variant="outlined ? 'outline' : 'subtle'" :size="size" :label="label" :icon="icon" class="cds-tag font-medium">
    <slot />
  </UBadge>
</template>
