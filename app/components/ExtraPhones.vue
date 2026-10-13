<script setup lang="ts">
// More phone numbers for a customer, beside the main one: any number of rows,
// each a phone input with the contact person to ask for on that number.
const list = defineModel<ExtraContact[]>({ default: () => [] });
const { t } = useI18n();

function add() {
  list.value = [...list.value, { phone: "", name: "" }];
}
function remove(index: number) {
  list.value = list.value.filter((_, i) => i !== index);
}
function update(index: number, patch: Partial<ExtraContact>) {
  list.value = list.value.map((c, i) => (i === index ? { ...c, ...patch } : c));
}
</script>

<template>
  <div class="space-y-3">
    <div v-for="(c, index) in list" :key="index" class="flex items-start gap-2">
      <div class="grid min-w-0 flex-1 gap-2 sm:grid-cols-2">
        <UInput
          :model-value="c.name"
          icon="i-lucide-user-round"
          :placeholder="t('common.contactPersonName')"
          class="w-full"
          @update:model-value="(v: string | number) => update(index, { name: String(v) })"
        />
        <PhoneInput :model-value="c.phone" @update:model-value="(v: string) => update(index, { phone: v })" />
      </div>
      <UButton icon="i-lucide-x" color="neutral" variant="ghost" :aria-label="t('common.delete')" @click="remove(index)" />
    </div>
    <UButton icon="i-lucide-plus" size="sm" color="neutral" variant="soft" :label="t('common.addPhone')" @click="add" />
  </div>
</template>
