<script setup lang="ts">
// More phone numbers for a customer, beside the main one: any number of rows,
// each a normal phone input.
const list = defineModel<string[]>({ default: () => [] });
const { t } = useI18n();

function add() {
  list.value = [...list.value, ""];
}
function remove(index: number) {
  list.value = list.value.filter((_, i) => i !== index);
}
function update(index: number, value: string) {
  list.value = list.value.map((v, i) => (i === index ? value : v));
}
</script>

<template>
  <div class="space-y-2">
    <div v-for="(phone, index) in list" :key="index" class="flex items-start gap-2">
      <div class="min-w-0 flex-1">
        <PhoneInput :model-value="phone" @update:model-value="(v: string) => update(index, v)" />
      </div>
      <UButton icon="i-lucide-x" color="neutral" variant="ghost" :aria-label="t('common.delete')" @click="remove(index)" />
    </div>
    <UButton icon="i-lucide-plus" size="sm" color="neutral" variant="soft" :label="t('common.addPhone')" @click="add" />
  </div>
</template>
