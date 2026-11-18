<script setup lang="ts">
// Add, change and delete the saved replies. Everyone who can open the WhatsApp inbox can.
// `prefill` fills the new-reply text (e.g. what was just typed in a chat).
const open = defineModel<boolean>("open", { default: false });
const props = defineProps<{ prefill?: string }>();

const toast = useToast();
const { t } = useI18n();
const { replies, load, save, remove } = useSavedReplies();

const editingId = ref<string | null>(null);
const form = reactive({ title: "", shortcut: "", body: "" });
const saving = ref(false);
const confirmDelete = ref<string | null>(null);
const search = ref("");

function startEdit(r: SavedReply | null, body = "") {
  editingId.value = r?.id ?? null;
  form.title = r?.title ?? "";
  form.shortcut = r?.shortcut ?? "";
  form.body = r?.body ?? body;
  confirmDelete.value = null;
}
watch(open, async (isOpen) => {
  if (!isOpen) return;
  search.value = "";
  startEdit(null, props.prefill ?? "");
  await load();
});

const shown = computed(() => {
  const q = search.value.trim().toLowerCase();
  return replies.value.filter((r) => !q || `${r.title} ${r.body} ${r.shortcut ?? ""}`.toLowerCase().includes(q));
});
const formValid = computed(() => !!form.title.trim() && !!form.body.trim() && !/[\s/]/.test(form.shortcut.trim().replace(/^\//, "")));

async function onSave() {
  if (!formValid.value) return;
  saving.value = true;
  const error = await save(editingId.value, { title: form.title.trim(), body: form.body.trim(), shortcut: form.shortcut.trim().replace(/^\//, "") || null });
  saving.value = false;
  if (error) {
    toast.add({ title: t("chats.saved.saveFailed"), description: error.code === "23505" ? t("chats.saved.shortcutTaken") : error.message, color: "error" });
    return;
  }
  toast.add({ title: t("chats.saved.saved"), color: "success" });
  startEdit(null);
}
async function onRemove(id: string) {
  if (confirmDelete.value !== id) {
    confirmDelete.value = id;
    return;
  }
  const error = await remove(id);
  if (error) toast.add({ title: t("chats.saved.saveFailed"), description: error.message, color: "error" });
  else toast.add({ title: t("chats.saved.deleted"), color: "success" });
  confirmDelete.value = null;
  if (editingId.value === id) startEdit(null);
}
</script>

<template>
  <UModal v-model:open="open" :title="t('chats.saved.manage')" :ui="{ content: 'sm:max-w-3xl' }">
    <template #body>
      <div class="grid gap-5 md:grid-cols-2">
        <!-- the list -->
        <div class="space-y-2">
          <UInput v-model="search" icon="i-lucide-search" size="sm" :placeholder="t('chats.saved.search')" class="w-full" />
          <p v-if="!shown.length" class="rounded-[10px] bg-muted p-4 text-center text-sm text-muted">{{ replies.length ? t("chats.saved.noMatch") : t("chats.saved.empty") }}</p>
          <ul v-else class="max-h-[26rem] divide-y divide-default overflow-y-auto rounded-[10px] border border-default">
            <li v-for="r in shown" :key="r.id" class="flex items-start justify-between gap-2 px-3 py-2 text-sm" :class="editingId === r.id && 'bg-primary/5'">
              <button type="button" class="min-w-0 flex-1 text-start" @click="startEdit(r)">
                <p class="flex items-center gap-2 font-medium text-highlighted">{{ r.title }}<span v-if="r.shortcut" class="text-xs font-normal text-muted">/{{ r.shortcut }}</span></p>
                <p class="line-clamp-2 whitespace-pre-line text-xs text-toned">{{ r.body }}</p>
              </button>
              <div class="flex shrink-0 gap-1">
                <UButton size="xs" color="neutral" variant="ghost" icon="i-lucide-pencil" :aria-label="t('common.edit')" @click="startEdit(r)" />
                <UButton size="xs" :color="confirmDelete === r.id ? 'error' : 'neutral'" :variant="confirmDelete === r.id ? 'solid' : 'ghost'" icon="i-lucide-trash" :label="confirmDelete === r.id ? t('chats.saved.confirmDelete') : undefined" :aria-label="t('common.delete')" @click="onRemove(r.id)" />
              </div>
            </li>
          </ul>
        </div>

        <!-- add / edit -->
        <div class="space-y-3">
          <p class="text-sm font-semibold text-highlighted">{{ editingId ? t("chats.saved.editing") : t("chats.saved.newReply") }}</p>
          <UFormField :label="t('chats.saved.titleField')" required><UInput v-model="form.title" class="w-full" /></UFormField>
          <UFormField :label="t('chats.saved.shortcut')" :help="t('chats.saved.shortcutHelp')"><UInput v-model="form.shortcut" :placeholder="t('chats.saved.shortcutExample')" class="w-full" /></UFormField>
          <UFormField :label="t('chats.saved.body')" :help="t('chats.saved.variables')" required><UTextarea v-model="form.body" :rows="5" class="w-full" /></UFormField>
          <div class="flex flex-wrap justify-end gap-2">
            <UButton v-if="editingId || form.title || form.body" color="neutral" variant="ghost" :label="editingId ? t('chats.saved.newReply') : t('common.cancel')" :icon="editingId ? 'i-lucide-plus' : undefined" @click="startEdit(null)" />
            <UButton :label="editingId ? t('common.save') : t('chats.saved.add')" :loading="saving" :disabled="!formValid" @click="onSave" />
          </div>
        </div>
      </div>
    </template>
  </UModal>
</template>
