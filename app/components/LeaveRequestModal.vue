<script setup lang="ts">
// Ask for a vacation: the type, from day to day, who approves it, a note — and a file when the
// type asks for one (the sick leave does).
import type { Approver, LeavePolicy, LeaveType } from "~/composables/useLeave";

const props = defineProps<{ types: LeaveType[]; policy: LeavePolicy; approvers: Approver[]; remaining: Record<string, number> }>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ saved: [] }>();

const supabase = useSupabaseClient();
const me = useSupabaseUser();
const toast = useToast();
const { t } = useI18n();
const { workingDays, errorText } = useLeave();

const typeId = ref<string | null>(null);
const start = ref("");
const end = ref("");
const approverId = ref<string | null>(null);
const note = ref("");
const files = ref<File[]>([]);
const picker = ref<HTMLInputElement | null>(null);
const saving = ref(false);

watch(open, (isOpen) => {
  if (!isOpen) return;
  typeId.value = props.types[0]?.id ?? null;
  start.value = "";
  end.value = "";
  approverId.value = props.approvers.length === 1 ? props.approvers[0]!.id : null;
  note.value = "";
  files.value = [];
});

const type = computed(() => props.types.find((x) => x.id === typeId.value) ?? null);
const days = computed(() => workingDays(start.value, end.value, props.policy.weekend_days));
const left = computed(() => (typeId.value ? props.remaining[typeId.value] ?? 0 : 0));
const typeItems = computed(() => props.types.map((x) => ({ label: x.name, value: x.id })));
const approverItems = computed(() => props.approvers.map((a) => ({ label: a.full_name || a.email, value: a.id })));
const needsFile = computed(() => !!type.value?.requires_attachment);
const valid = computed(
  () => !!typeId.value && !!start.value && !!end.value && end.value >= start.value && days.value > 0 && days.value <= left.value && !!approverId.value && (!needsFile.value || files.value.length > 0),
);

function onPick(e: Event) {
  const input = e.target as HTMLInputElement;
  files.value = [...files.value, ...Array.from(input.files ?? [])];
  input.value = "";
}

async function save() {
  if (!valid.value) return;
  saving.value = true;
  // the files first, in the person's own folder of the private storage
  const attachments: { name: string; path: string }[] = [];
  for (const file of files.value) {
    const path = `${me.value?.sub}/${Date.now()}-${file.name}`;
    const { error } = await supabase.storage.from("leave-files").upload(path, file);
    if (error) {
      saving.value = false;
      toast.add({ title: t("leave.uploadFailed"), description: `${file.name}: ${error.message}`, color: "error" });
      return;
    }
    attachments.push({ name: file.name, path });
  }
  const { error } = await supabase.from("leave_requests").insert({
    leave_type_id: typeId.value!,
    start_date: start.value,
    end_date: end.value,
    approver_id: approverId.value!,
    note: note.value.trim() || null,
    attachments,
  });
  saving.value = false;
  if (error) {
    // do not leave the uploaded files behind
    if (attachments.length) await supabase.storage.from("leave-files").remove(attachments.map((a) => a.path));
    toast.add({ title: t("leave.requestFailed"), description: errorText(error.message), color: "error" });
    return;
  }
  toast.add({ title: t("leave.requestSent"), color: "success" });
  open.value = false;
  emit("saved");
}
</script>

<template>
  <UModal v-model:open="open" :title="t('leave.requestVacation')">
    <template #body>
      <div class="space-y-4">
        <UFormField :label="t('leave.type')" required>
          <USelect v-model="typeId" :items="typeItems" value-key="value" icon="i-lucide-calendar-heart" class="w-full" />
        </UFormField>
        <div class="grid gap-4 sm:grid-cols-2">
          <UFormField :label="t('leave.from')" required>
            <UInput v-model="start" type="date" class="w-full" />
          </UFormField>
          <UFormField :label="t('leave.to')" required>
            <UInput v-model="end" type="date" :min="start || undefined" class="w-full" />
          </UFormField>
        </div>
        <p v-if="start && end" class="rounded-[10px] px-3 py-2 text-sm" :class="days > 0 && days <= left ? 'bg-primary/10 text-primary' : 'bg-error/10 text-error'">
          {{ t("leave.daysSummary", { days, left }) }}
          <template v-if="days === 0"> · {{ t("leave.errors.no_working_days") }}</template>
          <template v-else-if="days > left"> · {{ t("leave.errors.insufficient_balance") }}</template>
        </p>
        <UFormField :label="t('leave.approver')" required :help="approvers.length ? undefined : t('leave.noApprovers')">
          <USelect v-model="approverId" :items="approverItems" value-key="value" icon="i-lucide-user-check" :placeholder="t('leave.pickApprover')" class="w-full" />
        </UFormField>
        <UFormField :label="t('leave.note')">
          <UTextarea v-model="note" :rows="2" class="w-full" />
        </UFormField>
        <div class="space-y-2">
          <div class="flex items-center justify-between gap-2">
            <p class="text-sm font-medium text-highlighted">{{ t("leave.files") }} <span v-if="needsFile" class="text-error">*</span></p>
            <input ref="picker" type="file" multiple class="hidden" @change="onPick" />
            <UButton icon="i-lucide-paperclip" size="xs" color="neutral" variant="outline" :label="t('leave.attach')" @click="picker?.click()" />
          </div>
          <p v-if="needsFile && !files.length" class="text-xs text-warning">{{ t("leave.fileRequired") }}</p>
          <ul v-if="files.length" class="space-y-1.5">
            <li v-for="(f, i) in files" :key="i" class="flex items-center gap-2 rounded-[10px] border border-default p-2">
              <UIcon name="i-lucide-file" class="size-4 shrink-0 text-muted" />
              <span class="min-w-0 flex-1 truncate text-sm"><bdi>{{ f.name }}</bdi></span>
              <UButton icon="i-lucide-x" color="neutral" variant="ghost" size="sm" :aria-label="t('common.cancel')" @click="files.splice(i, 1)" />
            </li>
          </ul>
        </div>
        <UButton :label="t('leave.send')" icon="i-lucide-send" :loading="saving" :disabled="!valid" size="lg" block @click="save" />
      </div>
    </template>
  </UModal>
</template>
