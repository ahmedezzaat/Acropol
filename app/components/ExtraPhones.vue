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
    <!-- each person is a small card, fields stacked so nothing is squeezed -->
    <div v-for="(c, index) in list" :key="index" class="space-y-2 rounded-[10px] border border-default bg-muted/40 p-3">
      <div class="flex items-center gap-2">
        <UInput
          :model-value="c.name"
          icon="i-lucide-user-round"
          :placeholder="t('common.contactPersonName')"
          class="min-w-0 flex-1"
          @update:model-value="(v: string | number) => update(index, { name: String(v) })"
        />
        <UButton icon="i-lucide-trash-2" color="error" variant="ghost" size="sm" :aria-label="t('common.delete')" @click="remove(index)" />
      </div>
      <PhoneInput :model-value="c.phone" @update:model-value="(v: string) => update(index, { phone: v })" />
    </div>
    <UButton icon="i-lucide-plus" size="sm" color="neutral" variant="soft" :label="t('common.addPhone')" @click="add" />
  </div>
</template>
