<script setup lang="ts">
// The dialog shell: a title, a close button, the content, and an optional
// actions row (primary = flat primary, secondary = soft, destructive = ghost error).
//   <KDialog v-model:open="open" title="..."> content <template #actions> buttons </template> </KDialog>
const open = defineModel<boolean>("open", { default: false });
defineProps<{ title: string; description?: string }>();
const slots = useSlots();
</script>

<template>
  <UModal v-model:open="open" :title="title" :description="description">
    <template #body>
      <slot />
    </template>
    <template v-if="slots.actions" #footer>
      <div class="flex w-full flex-wrap items-center justify-end gap-2">
        <slot name="actions" />
      </div>
    </template>
  </UModal>
</template>
