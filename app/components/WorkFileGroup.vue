<script setup lang="ts">
// One group of files on a technical office card: a heading with the count, an optional
// upload button, and the files as rows (or an empty hint).
interface FileItem {
  id: string;
  file_name: string;
}
defineProps<{
  label: string;
  icon: string;
  rows: FileItem[];
  inputId: string;
  canUpload?: boolean;
  uploading?: boolean;
}>();
const emit = defineEmits<{ pick: [event: Event]; open: [file: FileItem]; download: [file: FileItem] }>();
const { t } = useI18n();

function fileIcon(name: string) {
  const ext = name.split(".").pop()?.toLowerCase() ?? "";
  if (["png", "jpg", "jpeg", "gif", "webp", "heic", "svg"].includes(ext)) return "i-lucide-image";
  if (ext === "pdf") return "i-lucide-file-text";
  if (["xls", "xlsx", "csv"].includes(ext)) return "i-lucide-file-spreadsheet";
  if (["doc", "docx"].includes(ext)) return "i-lucide-file-type";
  return "i-lucide-file";
}
</script>

<template>
  <div class="space-y-2">
    <div class="flex items-center justify-between gap-2">
      <div class="flex min-w-0 items-center gap-2">
        <UIcon :name="icon" class="size-4 shrink-0 text-muted" />
        <p class="truncate text-xs font-semibold text-toned">{{ label }}</p>
        <KBadge :label="String(rows.length)" tone="neutral" />
      </div>
      <template v-if="canUpload">
        <input :id="inputId" type="file" multiple class="hidden" @change="emit('pick', $event)" />
        <label :for="inputId" class="inline-flex shrink-0 cursor-pointer items-center gap-1 rounded-[8px] bg-primary/10 px-2.5 py-1 text-xs font-medium text-primary hover:bg-primary/15">
          <UIcon :name="uploading ? 'i-lucide-loader-2' : 'i-lucide-plus'" class="size-3.5" :class="uploading && 'animate-spin'" />{{ t("crm.work.addFiles") }}
        </label>
      </template>
    </div>
    <p v-if="!rows.length" class="rounded-[10px] border border-dashed border-default px-3 py-2.5 text-center text-xs text-muted">{{ t("files.emptySection") }}</p>
    <ul v-else class="space-y-1.5">
      <li v-for="f in rows" :key="f.id">
        <div class="flex items-center gap-1 rounded-[10px] border border-default bg-default p-2 transition hover:border-primary/50 hover:bg-muted">
          <button type="button" class="flex min-w-0 flex-1 items-center gap-3 text-start" :title="t('files.open')" @click="emit('open', f)">
            <span class="flex size-8 shrink-0 items-center justify-center rounded-[8px] bg-primary/10 text-primary"><UIcon :name="fileIcon(f.file_name)" class="size-4" /></span>
            <span class="min-w-0 flex-1 truncate text-sm font-medium text-highlighted"><bdi>{{ f.file_name }}</bdi></span>
          </button>
          <UButton icon="i-lucide-download" color="neutral" variant="ghost" size="sm" :aria-label="t('files.download')" :title="t('files.download')" @click="emit('download', f)" />
        </div>
      </li>
    </ul>
  </div>
</template>
