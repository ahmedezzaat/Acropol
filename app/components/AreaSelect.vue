<script setup lang="ts">
// Pick an area (المنطقة) from the list in Settings -> Areas; null = no area.
const model = defineModel<string | null>({ default: null });
defineProps<{ disabled?: boolean }>();

const { t } = useI18n();
const { areas, loadAreas } = useCs();
useAsyncData("area-select-areas", async () => {
  await loadAreas();
  return true;
});

const NONE = "__none__";
const items = computed(() => [{ label: t("cs.customers.noArea"), value: NONE }, ...areas.value.map((a) => ({ label: a.name, value: a.id }))]);
</script>

<template>
  <USelect
    :model-value="model ?? NONE"
    :items="items"
    value-key="value"
    icon="i-lucide-map-pin"
    :disabled="disabled"
    class="w-full"
    @update:model-value="(v: string) => (model = v === NONE ? null : v)"
  />
</template>
