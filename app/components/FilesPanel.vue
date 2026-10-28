<script setup lang="ts">
// The files attached to a deal, or — on a customer — the files of every deal
// that customer has. Files live in the private deal-attachments bucket; one
// row in deal_attachments per file. Only a deal's own panel can add or remove.
const props = defineProps<{
  dealId?: string;
  customerId?: string;
  canEdit?: boolean;
}>();
const emit = defineEmits<{ changed: [] }>();

interface FileRow {
  id: string;
  deal_id: string;
  file_name: string;
  storage_path: string;
  kind: string | null;
  from_work_pipeline_id: string | null;
  uploaded_by: string | null;
  created_at: string;
}

const { hasPermission } = usePermissions();
// Files uploaded from the technical office have their own permissions.
const canViewWork = computed(() => hasPermission("crm_work_files", "view"));
const canEditWork = computed(() => hasPermission("crm_work_files", "edit"));
const canDeleteWork = computed(() => hasPermission("crm_work_files", "delete"));
const canRemove = (r: { kind: string | null; from_work_pipeline_id: string | null }) =>
  canManage.value && r.kind !== "contract" && (!r.from_work_pipeline_id || canDeleteWork.value);

const supabase = useSupabaseClient();
const { t } = useI18n();
const toast = useToast();

const loading = ref(true);
const rows = ref<FileRow[]>([]);
const dealTitles = ref<Record<string, string>>({});
const people = ref<Record<string, string>>({});
const workNames = ref<Record<string, string>>({});
const uploading = ref(false);
const picker = ref<HTMLInputElement | null>(null);

async function load() {
  loading.value = true;
  let dealIds: string[] = [];
  if (props.dealId) {
    dealIds = [props.dealId];
  } else if (props.customerId) {
    const { data } = await supabase.from("deals").select("id, title").eq("customer_id", props.customerId);
    dealIds = (data ?? []).map((d) => d.id);
    dealTitles.value = Object.fromEntries((data ?? []).map((d) => [d.id, d.title]));
  }
  if (!dealIds.length) {
    rows.value = [];
    loading.value = false;
    return;
  }
  const { data } = await supabase
    .from("deal_attachments")
    .select("id, deal_id, file_name, storage_path, kind, from_work_pipeline_id, uploaded_by, created_at")
    .in("deal_id", dealIds)
    .order("created_at", { ascending: false });
  rows.value = ((data ?? []) as FileRow[]).filter((r) => !r.from_work_pipeline_id || canViewWork.value);

  // the work pipelines files came from (to tag them)
  const workIds = [...new Set(rows.value.map((r) => r.from_work_pipeline_id).filter((x): x is string => !!x))];
  if (workIds.length) {
    const { data: wp } = await supabase.from("work_pipelines").select("id, name").in("id", workIds);
    workNames.value = Object.fromEntries((wp ?? []).map((w) => [w.id, w.name]));
  }

  const uploaderIds = [...new Set(rows.value.map((r) => r.uploaded_by).filter((x): x is string => !!x))];
  if (uploaderIds.length) {
    const { data: profiles } = await supabase.from("profiles").select("id, full_name, email").in("id", uploaderIds);
    people.value = Object.fromEntries((profiles ?? []).map((p) => [p.id, p.full_name || p.email]));
  }
  loading.value = false;
}
onMounted(load);

const showDeal = computed(() => !!props.customerId && !props.dealId);
const canManage = computed(() => !!props.dealId && !!props.canEdit);

function iconFor(name: string) {
  const ext = name.split(".").pop()?.toLowerCase() ?? "";
  if (["png", "jpg", "jpeg", "gif", "webp", "heic"].includes(ext)) return "i-lucide-image";
  if (ext === "pdf") return "i-lucide-file-text";
  if (["xls", "xlsx", "csv"].includes(ext)) return "i-lucide-file-spreadsheet";
  if (["doc", "docx"].includes(ext)) return "i-lucide-file-type";
  return "i-lucide-paperclip";
}

async function open(row: FileRow) {
  const { data, error } = await supabase.storage.from("deal-attachments").createSignedUrl(row.storage_path, 60);
  if (error || !data) {
    toast.add({ title: t("files.openFailed"), description: error?.message, color: "error" });
    return;
  }
  window.open(data.signedUrl, "_blank");
}

// The sections of the files: the quote, the contract and everything else.
const SECTIONS = [
  { kind: "quote", labelKey: "files.quoteSection", icon: "i-lucide-file-text" },
  { kind: "contract", labelKey: "files.contractSection", icon: "i-lucide-file-signature" },
  { kind: null, labelKey: "files.otherSection", icon: "i-lucide-paperclip" },
] as const;
const sections = computed(() => SECTIONS.map((s) => ({ ...s, rows: rows.value.filter((r) => (r.kind ?? null) === s.kind) })));
const pickKind = ref<string | null>(null);
function pickFor(kind: string | null) {
  pickKind.value = kind;
  picker.value?.click();
}

async function onPick(event: Event) {
  const input = event.target as HTMLInputElement;
  const files = Array.from(input.files ?? []);
  input.value = "";
  if (!files.length || !props.dealId) return;
  uploading.value = true;
  for (const file of files) {
    const path = `${props.dealId}/${Date.now()}-${file.name}`;
    const { error: uploadError } = await supabase.storage.from("deal-attachments").upload(path, file);
    if (uploadError) {
      toast.add({ title: t("files.uploadFailed"), description: `${file.name}: ${uploadError.message}`, color: "error" });
      continue;
    }
    const { error } = await supabase.from("deal_attachments").insert({ deal_id: props.dealId, file_name: file.name, storage_path: path, kind: pickKind.value });
    if (error) {
      await supabase.storage.from("deal-attachments").remove([path]);
      toast.add({ title: t("files.uploadFailed"), description: `${file.name}: ${error.message}`, color: "error" });
    }
  }
  uploading.value = false;
  await load();
  emit("changed");
}

// Renaming a technical office file.
const renaming = ref<FileRow | null>(null);
const renameOpen = computed({ get: () => !!renaming.value, set: (v) => { if (!v) renaming.value = null; } });
const newName = ref("");
const renameSaving = ref(false);
function askRename(row: FileRow) {
  renaming.value = row;
  newName.value = row.file_name;
}
async function saveRename() {
  const row = renaming.value;
  const name = newName.value.trim();
  if (!row || !name) return;
  renameSaving.value = true;
  const { error } = await supabase.from("deal_attachments").update({ file_name: name }).eq("id", row.id);
  renameSaving.value = false;
  if (error) {
    toast.add({ title: t("files.renameFailed"), description: error.message, color: "error" });
    return;
  }
  renaming.value = null;
  await load();
}

const removing = ref<FileRow | null>(null);
const removeOpen = computed({ get: () => !!removing.value, set: (v) => { if (!v) removing.value = null; } });
const deleting = ref(false);
function askRemove(row: FileRow) {
  removing.value = row;
}
function cancelRemove() {
  removing.value = null;
}
async function confirmRemove() {
  const row = removing.value;
  if (!row) return;
  deleting.value = true;
  // storage first: its policy looks the file up through the deal_attachments row
  const { error: storageError } = await supabase.storage.from("deal-attachments").remove([row.storage_path]);
  const { error } = storageError ? { error: storageError } : await supabase.from("deal_attachments").delete().eq("id", row.id);
  deleting.value = false;
  if (error) {
    toast.add({ title: t("files.deleteFailed"), description: error.message, color: "error" });
    return;
  }
  removing.value = null;
  await load();
  emit("changed");
}
</script>

<template>
  <div class="space-y-3">
    <div class="flex flex-wrap items-center justify-between gap-2">
      <div class="flex items-center gap-2">
        <h3 class="text-base font-semibold text-highlighted">{{ t("files.title") }}</h3>
        <KBadge :label="String(rows.length)" tone="neutral" />
      </div>
      <input v-if="canManage" ref="picker" type="file" multiple class="hidden" @change="onPick" />
    </div>

    <div v-if="loading" class="flex justify-center py-10">
      <UIcon name="i-lucide-loader-2" class="size-5 animate-spin text-muted" />
    </div>
    <p v-else-if="!rows.length && showDeal" class="kords-card p-8 text-center text-sm text-muted">{{ t("files.emptyCustomer") }}</p>
    <template v-else>
    <section v-for="s in sections" :key="String(s.kind)" class="space-y-2">
      <div class="flex items-center justify-between gap-2">
        <div class="flex items-center gap-2">
          <UIcon :name="s.icon" class="size-4 text-muted" />
          <h4 class="text-sm font-semibold text-highlighted">{{ t(s.labelKey) }}</h4>
          <KBadge :label="String(s.rows.length)" tone="neutral" />
        </div>
        <UButton v-if="canManage" icon="i-lucide-upload" size="xs" color="neutral" variant="outline" :label="t('files.upload')" :loading="uploading && pickKind === s.kind" @click="pickFor(s.kind)" />
      </div>
      <p v-if="!s.rows.length" class="kords-card p-4 text-center text-xs text-muted">{{ t("files.emptySection") }}</p>
      <ul v-else class="space-y-2">
      <li v-for="r in s.rows" :key="r.id" class="kords-card flex items-center gap-3 p-3">
        <span class="flex size-9 shrink-0 items-center justify-center rounded-[10px] bg-primary/10 text-primary">
          <UIcon :name="iconFor(r.file_name)" class="size-5" />
        </span>
        <button type="button" class="min-w-0 flex-1 text-start" @click="open(r)">
          <div class="flex flex-wrap items-center gap-2">
            <span class="truncate text-sm font-medium text-highlighted"><bdi>{{ r.file_name }}</bdi></span>
            <KBadge v-if="r.from_work_pipeline_id" :label="t('files.fromWork', { name: workNames[r.from_work_pipeline_id] ?? '' })" tone="success" icon="i-lucide-git-fork" />
          </div>
          <div class="mt-0.5 text-xs text-muted">
            {{ formatDMYTime(r.created_at) }}<template v-if="r.uploaded_by && people[r.uploaded_by]"> · {{ people[r.uploaded_by] }}</template>
          </div>
        </button>
        <NuxtLink v-if="showDeal" :to="`/crm/deals/${r.deal_id}`" class="hidden shrink-0 items-center gap-1 text-xs text-primary sm:flex" @click.stop>
          <UIcon name="i-lucide-handshake" class="size-3.5" />
          <span class="max-w-40 truncate">{{ dealTitles[r.deal_id] || t("files.deal") }}</span>
        </NuxtLink>
        <UButton icon="i-lucide-download" color="neutral" variant="ghost" size="sm" :aria-label="t('files.open')" @click="open(r)" />
        <UButton v-if="r.from_work_pipeline_id && canEditWork" icon="i-lucide-pencil" color="neutral" variant="ghost" size="sm" :aria-label="t('files.rename')" @click="askRename(r)" />
        <UButton
          v-if="canRemove(r)"
          icon="i-lucide-trash-2"
          color="error"
          variant="ghost"
          size="sm"
          :aria-label="t('common.delete')"
          @click="askRemove(r)"
        />
      </li>
      </ul>
    </section>
    </template>

    <UModal v-model:open="renameOpen" :title="t('files.rename')">
      <template #body>
        <div class="space-y-4">
          <UInput v-model="newName" class="w-full" @keydown.enter="saveRename" />
          <UButton :label="t('common.save')" :loading="renameSaving" :disabled="!newName.trim()" block @click="saveRename" />
        </div>
      </template>
    </UModal>

    <UModal v-model:open="removeOpen" :title="t('files.deleteTitle')">
      <template #body>
        <p class="text-sm text-toned">{{ t("files.deleteBody", { name: removing?.file_name ?? "" }) }}</p>
      </template>
      <template #footer>
        <div class="flex w-full justify-end gap-2">
          <UButton color="neutral" variant="outline" :label="t('common.cancel')" @click="cancelRemove" />
          <UButton color="error" :label="t('common.delete')" :loading="deleting" @click="confirmRemove" />
        </div>
      </template>
    </UModal>
  </div>
</template>
