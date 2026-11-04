<script setup lang="ts">
// Create or edit a task: for yourself or any other active user, with a deadline, a priority, a note and
// (optionally) the customer it is about.
export interface TaskRow {
  id: string;
  title: string;
  note: string | null;
  priority: "low" | "medium" | "high" | "urgent";
  status: "todo" | "in_progress" | "done";
  deadline: string | null;
  customer_id: string | null;
  assigned_to: string;
  created_by: string;
  completed_at: string | null;
  created_at: string;
  customer?: { id: string; name: string; company: string | null } | null;
}
const props = defineProps<{ task?: TaskRow | null; people: { id: string; full_name: string | null; email: string }[] }>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ saved: []; changed: [] }>();

const supabase = useSupabaseClient();
const me = useSupabaseUser();
const toast = useToast();
const { t } = useI18n();
const { isAdmin } = usePermissions();

const title = ref("");
const note = ref("");
const priority = ref<TaskRow["priority"]>("medium");
const status = ref<TaskRow["status"]>("todo");
const deadline = ref("");
const assignedTo = ref<string | null>(null);
const customerId = ref<string | null>(null);
const saving = ref(false);

// ---- Files: both people on the task can add and download them
interface Attachment { id: string; file_name: string; storage_path: string; uploaded_by: string | null; created_at: string }
const attachments = ref<Attachment[]>([]);
const queue = ref<File[]>([]);
const picker = ref<HTMLInputElement | null>(null);
const uploading = ref(false);
async function loadAttachments() {
  if (!props.task) {
    attachments.value = [];
    return;
  }
  const { data } = await supabase.from("task_attachments").select("id, file_name, storage_path, uploaded_by, created_at").eq("task_id", props.task.id).order("created_at");
  attachments.value = (data ?? []) as Attachment[];
}
async function uploadTo(taskId: string, files: File[]) {
  uploading.value = true;
  for (const file of files) {
    const path = `${taskId}/${Date.now()}-${file.name}`;
    const { error: uploadError } = await supabase.storage.from("task-attachments").upload(path, file);
    if (uploadError) {
      toast.add({ title: t("tasks.uploadFailed"), description: `${file.name}: ${uploadError.message}`, color: "error" });
      continue;
    }
    const { error } = await supabase.from("task_attachments").insert({ task_id: taskId, file_name: file.name, storage_path: path });
    if (error) {
      await supabase.storage.from("task-attachments").remove([path]);
      toast.add({ title: t("tasks.uploadFailed"), description: `${file.name}: ${error.message}`, color: "error" });
    }
  }
  uploading.value = false;
}
async function onPick(event: Event) {
  const input = event.target as HTMLInputElement;
  const files = Array.from(input.files ?? []);
  input.value = "";
  if (!files.length) return;
  if (props.task) {
    // an existing task: the files are stored straight away
    await uploadTo(props.task.id, files);
    await loadAttachments();
    emit("changed");
  } else {
    queue.value = [...queue.value, ...files];
  }
}
async function download(a: Attachment) {
  const { data, error } = await supabase.storage.from("task-attachments").createSignedUrl(a.storage_path, 60, { download: a.file_name });
  if (error || !data) {
    toast.add({ title: t("tasks.downloadFailed"), description: error?.message, color: "error" });
    return;
  }
  const link = document.createElement("a");
  link.href = data.signedUrl;
  link.download = a.file_name;
  document.body.appendChild(link);
  link.click();
  link.remove();
}
const canRemoveFile = (a: Attachment) => a.uploaded_by === me.value?.sub || props.task?.created_by === me.value?.sub || isAdmin.value;
async function removeFile(a: Attachment) {
  // the stored file first: its rule looks the file up through the row
  const { error: storageError } = await supabase.storage.from("task-attachments").remove([a.storage_path]);
  const { data, error } = storageError ? { data: null, error: storageError } : await supabase.from("task_attachments").delete().eq("id", a.id).select("id");
  if (error || !data?.length) {
    toast.add({ title: t("tasks.deleteFailed"), description: error?.message, color: "error" });
    return;
  }
  await loadAttachments();
  emit("changed");
}
const personName = (id: string | null) => {
  const p = props.people.find((x) => x.id === id);
  return p ? p.full_name || p.email : "";
};
const fileIcon = (name: string) => {
  const ext = name.split(".").pop()?.toLowerCase() ?? "";
  if (["png", "jpg", "jpeg", "gif", "webp", "heic", "svg"].includes(ext)) return "i-lucide-image";
  if (ext === "pdf") return "i-lucide-file-text";
  if (["xls", "xlsx", "csv"].includes(ext)) return "i-lucide-file-spreadsheet";
  if (["doc", "docx"].includes(ext)) return "i-lucide-file-type";
  return "i-lucide-file";
};

// the customer picker searches as you type; the chosen customer stays in the list
interface CustomerOption { label: string; value: string }
const customerOptions = ref<CustomerOption[]>([]);
const customerSearch = ref("");
const label = (c: { name: string; company: string | null; phone?: string | null }) => [c.company, c.name, c.phone].filter(Boolean).join(" · ");
let searchTimer: ReturnType<typeof setTimeout> | undefined;
watch(customerSearch, (q) => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(async () => {
    const term = q.trim();
    let query = supabase.from("customers").select("id, name, company, phone").order("created_at", { ascending: false }).limit(20);
    if (term) query = query.or(`name.ilike.%${term}%,company.ilike.%${term}%,phone.ilike.%${term}%`);
    const { data } = await query;
    const found = (data ?? []).map((c) => ({ label: label(c), value: c.id }));
    const chosen = customerOptions.value.find((o) => o.value === customerId.value);
    customerOptions.value = chosen && !found.some((o) => o.value === chosen.value) ? [chosen, ...found] : found;
  }, 250);
});

const toLocalInput = (iso: string | null | undefined) => {
  if (!iso) return "";
  const d = new Date(iso);
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
};

watch(open, async (isOpen) => {
  if (!isOpen) return;
  const task = props.task;
  title.value = task?.title ?? "";
  note.value = task?.note ?? "";
  priority.value = task?.priority ?? "medium";
  status.value = task?.status ?? "todo";
  deadline.value = toLocalInput(task?.deadline);
  assignedTo.value = task?.assigned_to ?? ((me.value?.sub as string | undefined) ?? null);
  customerId.value = task?.customer_id ?? null;
  customerOptions.value = task?.customer ? [{ label: label(task.customer), value: task.customer.id }] : [];
  customerSearch.value = "";
  queue.value = [];
  await loadAttachments();
});

const peopleItems = computed(() =>
  props.people.map((p) => ({ label: p.id === me.value?.sub ? `${p.full_name || p.email} (${t("tasks.me")})` : p.full_name || p.email, value: p.id })),
);
const priorityItems = computed(() => (["low", "medium", "high", "urgent"] as const).map((p) => ({ label: t(`tasks.priority.${p}`), value: p })));
const statusItems = computed(() => (["todo", "in_progress", "done"] as const).map((s) => ({ label: t(`tasks.status.${s}`), value: s })));
const valid = computed(() => !!title.value.trim() && !!assignedTo.value);

async function save() {
  if (!valid.value) return;
  saving.value = true;
  const row = {
    title: title.value.trim(),
    note: note.value.trim() || null,
    priority: priority.value,
    status: status.value,
    deadline: deadline.value ? new Date(deadline.value).toISOString() : null,
    customer_id: customerId.value,
    assigned_to: assignedTo.value!,
  };
  let taskId = props.task?.id ?? null;
  let error: { message: string } | null = null;
  if (props.task) {
    ({ error } = await supabase.from("tasks").update(row).eq("id", props.task.id));
  } else {
    const created = await supabase.from("tasks").insert(row).select("id").single();
    error = created.error;
    taskId = created.data?.id ?? null;
  }
  // files picked while creating are stored once the task exists
  if (!error && taskId && queue.value.length) await uploadTo(taskId, queue.value);
  saving.value = false;
  if (error) {
    toast.add({ title: t("tasks.saveFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("tasks.saved"), color: "success" });
  open.value = false;
  emit("saved");
}
</script>

<template>
  <UModal v-model:open="open" :title="task ? t('tasks.edit') : t('tasks.new')">
    <template #body>
      <div class="space-y-4">
        <UFormField :label="t('tasks.titleField')" required>
          <UInput v-model="title" class="w-full" autofocus />
        </UFormField>
        <UFormField :label="t('tasks.assignee')" required>
          <USelect v-model="assignedTo" :items="peopleItems" value-key="value" icon="i-lucide-user" class="w-full" />
        </UFormField>
        <div class="grid gap-4 sm:grid-cols-2">
          <UFormField :label="t('tasks.priorityLabel')">
            <USelect v-model="priority" :items="priorityItems" value-key="value" icon="i-lucide-flag" class="w-full" />
          </UFormField>
          <UFormField :label="t('tasks.deadline')">
            <UInput v-model="deadline" type="datetime-local" class="w-full" />
          </UFormField>
        </div>
        <UFormField :label="t('tasks.customer')" :help="t('tasks.customerHint')">
          <USelectMenu
            v-model="customerId"
            v-model:search-term="customerSearch"
            :items="customerOptions"
            value-key="value"
            :ignore-filter="true"
            icon="i-lucide-user-round"
            :placeholder="t('tasks.customerPlaceholder')"
            class="w-full"
          >
            <template #empty>{{ t("tasks.noCustomers") }}</template>
          </USelectMenu>
          <UButton v-if="customerId" size="xs" color="neutral" variant="link" :label="t('tasks.clearCustomer')" class="mt-1 px-0" @click="customerId = null" />
        </UFormField>
        <UFormField :label="t('tasks.note')">
          <UTextarea v-model="note" :rows="3" class="w-full" />
        </UFormField>
        <!-- Files: the giver and the receiver can both add and download them -->
        <div class="space-y-2">
          <div class="flex items-center justify-between gap-2">
            <p class="text-sm font-medium text-highlighted">{{ t("tasks.files") }}</p>
            <input ref="picker" type="file" multiple class="hidden" @change="onPick" />
            <UButton icon="i-lucide-paperclip" size="xs" color="neutral" variant="outline" :label="t('tasks.attach')" :loading="uploading" @click="picker?.click()" />
          </div>
          <ul v-if="attachments.length || queue.length" class="space-y-1.5">
            <li v-for="a in attachments" :key="a.id" class="flex items-center gap-2 rounded-[10px] border border-default p-2">
              <span class="flex size-8 shrink-0 items-center justify-center rounded-[8px] bg-primary/10 text-primary"><UIcon :name="fileIcon(a.file_name)" class="size-4" /></span>
              <span class="min-w-0 flex-1">
                <span class="block truncate text-sm font-medium text-highlighted"><bdi>{{ a.file_name }}</bdi></span>
                <span class="block truncate text-xs text-muted">{{ formatDMYTime(a.created_at) }}<template v-if="personName(a.uploaded_by)"> · {{ personName(a.uploaded_by) }}</template></span>
              </span>
              <UButton icon="i-lucide-download" color="neutral" variant="ghost" size="sm" :aria-label="t('files.download')" :title="t('files.download')" @click="download(a)" />
              <UButton v-if="canRemoveFile(a)" icon="i-lucide-trash-2" color="error" variant="ghost" size="sm" :aria-label="t('common.delete')" @click="removeFile(a)" />
            </li>
            <li v-for="(f, i) in queue" :key="`q${i}`" class="flex items-center gap-2 rounded-[10px] border border-dashed border-default p-2">
              <span class="flex size-8 shrink-0 items-center justify-center rounded-[8px] bg-muted text-muted"><UIcon :name="fileIcon(f.name)" class="size-4" /></span>
              <span class="min-w-0 flex-1 truncate text-sm"><bdi>{{ f.name }}</bdi></span>
              <UButton icon="i-lucide-x" color="neutral" variant="ghost" size="sm" :aria-label="t('common.cancel')" @click="queue.splice(i, 1)" />
            </li>
          </ul>
          <p v-else class="text-xs text-muted">{{ t("tasks.noFiles") }}</p>
        </div>
        <UFormField v-if="task" :label="t('tasks.statusLabel')">
          <USelect v-model="status" :items="statusItems" value-key="value" class="w-full" />
        </UFormField>
        <UButton :label="t('common.save')" :loading="saving" :disabled="!valid" size="lg" block @click="save" />
      </div>
    </template>
  </UModal>
</template>
