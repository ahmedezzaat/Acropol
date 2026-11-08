<script setup lang="ts">
// Ask for a delay permission: arrive later on a day, for up to the allowed hours, a few times a month.
import type { Approver, LeavePolicy } from "~/composables/useLeave";

const props = defineProps<{ policy: LeavePolicy; approvers: Approver[]; usedThisMonth: number; schedule: { start: string; end: string }; fixedApprover?: Approver | null }>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ saved: [] }>();

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();
const { errorText } = useLeave();

const date = ref("");
const hours = ref<number | null>(null);
const approverId = ref<string | null>(null);
const reason = ref("");
const saving = ref(false);

watch(open, (isOpen) => {
  if (!isOpen) return;
  date.value = "";
  hours.value = props.policy.delay_max_hours;
  approverId.value = props.fixedApprover?.id ?? (props.approvers.length === 1 ? props.approvers[0]!.id : null);
  reason.value = "";
});

const approverItems = computed(() => props.approvers.map((a) => ({ label: a.full_name || a.email, value: a.id })));
const quotaLeft = computed(() => Math.max(0, props.policy.delay_per_month - props.usedThisMonth));
// when the person may arrive: their start time plus the hours asked for
const arriveBy = computed(() => {
  if (!hours.value) return "";
  const [h, m] = props.schedule.start.split(":").map(Number) as [number, number];
  const total = h * 60 + m + Math.round(hours.value * 60);
  return `${String(Math.floor(total / 60) % 24).padStart(2, "0")}:${String(total % 60).padStart(2, "0")}`;
});
const valid = computed(() => !!date.value && !!approverId.value && !!hours.value && hours.value > 0 && hours.value <= props.policy.delay_max_hours);

async function save() {
  if (!valid.value) return;
  saving.value = true;
  const { error } = await supabase.from("leave_delay_requests").insert({
    delay_date: date.value,
    hours: hours.value!,
    approver_id: approverId.value!,
    reason: reason.value.trim() || null,
  });
  saving.value = false;
  if (error) {
    toast.add({ title: t("leave.requestFailed"), description: errorText(error.message), color: "error" });
    return;
  }
  toast.add({ title: t("leave.requestSent"), color: "success" });
  open.value = false;
  emit("saved");
}
</script>

<template>
  <UModal v-model:open="open" :title="t('leave.requestDelay')">
    <template #body>
      <div class="space-y-4">
        <p class="rounded-[10px] bg-muted px-3 py-2 text-sm text-toned">
          {{ t("leave.delayRule", { hours: policy.delay_max_hours, times: policy.delay_per_month }) }}
          · {{ t("leave.delayLeft", { left: quotaLeft }) }}
        </p>
        <div class="grid gap-4 sm:grid-cols-2">
          <UFormField :label="t('leave.delayDate')" required>
            <UInput v-model="date" type="date" class="w-full" />
          </UFormField>
          <UFormField :label="t('leave.delayHours')" required>
            <UInputNumber v-model="hours" :min="0.5" :max="policy.delay_max_hours" :step="0.5" class="w-full" />
          </UFormField>
        </div>
        <p v-if="arriveBy" class="text-sm text-muted">{{ t("leave.arriveBy", { start: schedule.start, time: arriveBy }) }}</p>
        <div v-if="fixedApprover" class="flex items-center gap-2 rounded-[10px] bg-muted px-3 py-2 text-sm">
          <UIcon name="i-lucide-user-check" class="size-4 text-primary" />
          <span class="text-muted">{{ t("leave.goesTo") }}</span>
          <span class="font-medium text-highlighted">{{ fixedApprover.full_name || fixedApprover.email }}</span>
        </div>
        <UFormField v-else :label="t('leave.approver')" required :help="approvers.length ? undefined : t('leave.noApprovers')">
          <USelect v-model="approverId" :items="approverItems" value-key="value" icon="i-lucide-user-check" :placeholder="t('leave.pickApprover')" class="w-full" />
        </UFormField>
        <UFormField :label="t('leave.reason')">
          <UTextarea v-model="reason" :rows="2" class="w-full" />
        </UFormField>
        <UButton :label="t('leave.send')" icon="i-lucide-send" :loading="saving" :disabled="!valid || quotaLeft === 0" size="lg" block @click="save" />
      </div>
    </template>
  </UModal>
</template>
