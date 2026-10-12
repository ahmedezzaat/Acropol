<script setup lang="ts">
// "Are you sure?" before deleting: cancel (outline) and a destructive confirm.
const open = defineModel<boolean>("open", { default: false });
withDefaults(defineProps<{ title: string; message: string; loading?: boolean; confirmLabel?: string }>(), {
  loading: false,
  confirmLabel: undefined,
});
const emit = defineEmits<{ confirm: [] }>();
const { t } = useI18n();
function close() {
  open.value = false;
}
</script>

<template>
  <KDialog v-model:open="open" :title="title">
    <p class="text-sm text-muted">{{ message }}</p>
    <template #actions>
      <UButton color="neutral" variant="outline" :label="t('common.cancel')" @click="close" />
      <UButton color="error" :label="confirmLabel ?? t('common.delete')" :loading="loading" @click="emit('confirm')" />
    </template>
  </KDialog>
</template>
