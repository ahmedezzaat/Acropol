<script setup lang="ts">
// An avatar whose colour comes from the person's name, so rows stay easy to tell
// apart: `user` = the brand ramp (staff), `contact` = the slate ramp (customers and
// leads read quieter), `light` = same slate ramp as `contact`.
const props = withDefaults(
  defineProps<{ name?: string | null; kind?: "user" | "contact" | "light"; size?: "3xs" | "2xs" | "xs" | "sm" | "md" | "lg" | "xl" | "2xl" | "3xl"; icon?: string }>(),
  { name: null, kind: "user", size: "md", icon: undefined },
);

const initial = computed(() => (props.name ?? "").trim().charAt(0).toUpperCase() || undefined);
const index = computed(() => {
  let h = 0;
  for (const ch of props.name ?? "") h = (h * 31 + ch.charCodeAt(0)) >>> 0;
  return (h % 5) + 1;
});
// Every avatar is a 10% tint of its colour with the full colour as the initial.
const ramp = computed(() => ({ user: "tone", contact: "neutral", light: "neutral" })[props.kind]);
const style = computed(() => {
  const color = `var(--avatar-${ramp.value}-${index.value})`;
  return { background: `color-mix(in srgb, ${color} 10%, transparent)`, color };
});
</script>

<template>
  <UAvatar :text="initial" :icon="initial ? undefined : (icon ?? 'i-lucide-user-round')" :size="size" :style="style" />
</template>
