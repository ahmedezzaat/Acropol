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
const emit = defineEmits<{ saved: [] }>();

const supabase = useSupabaseClient();
const me = useSupabaseUser();
const toast = useToast();
const { t } = useI18n();

const title = ref("");
const note = ref("");
const priority = ref<TaskRow["priority"]>("medium");
const status = ref<TaskRow["status"]>("todo");
const deadline = ref("");
const assignedTo = ref<string | null>(null);
const customerId = ref<string | null>(null);
const saving = ref(false);

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
  const { error } = props.task ? await supabase.from("tasks").update(row).eq("id", props.task.id) : await supabase.from("tasks").insert(row);
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
        <UFormField v-if="task" :label="t('tasks.statusLabel')">
          <USelect v-model="status" :items="statusItems" value-key="value" class="w-full" />
        </UFormField>
        <UButton :label="t('common.save')" :loading="saving" :disabled="!valid" size="lg" block @click="save" />
      </div>
    </template>
  </UModal>
</template>
