<script setup lang="ts">
// Request (or edit) a field trip / inspection. Opened from the Trips &
// inspections page and from a deal — from a deal, `dealId` pre-selects it.
const props = defineProps<{ dealId?: string; visit?: Visit | null }>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ saved: [] }>();

const supabase = useSupabaseClient();
const user = useSupabaseUser();
const toast = useToast();
const { t } = useI18n();
const { dealLabels, visitTypes, kindRequiresDeal, loadDeals, loadTypes } = useVisits();

const editing = computed(() => !!props.visit);
const saving = ref(false);

const kind = ref<VisitKind>("");
const selectedDeal = ref<string | undefined>(undefined);
const visitDate = ref("");
const timeFrom = ref("");
const timeTo = ref("");
const address = ref("");
const notes = ref("");

const today = new Date().toISOString().slice(0, 10);

watch(open, async (isOpen) => {
  if (!isOpen) return;
  await Promise.all([loadDeals(), loadTypes()]);
  const v = props.visit;
  // Opened from a deal: only types that belong to a deal make sense.
  kind.value = v?.kind ?? kindOptions.value[0]?.value ?? "";
  selectedDeal.value = v?.deal_id ?? props.dealId;
  visitDate.value = v?.visit_date ?? "";
  timeFrom.value = v?.time_from.slice(0, 5) ?? "";
  timeTo.value = v?.time_to.slice(0, 5) ?? "";
  address.value = v?.address ?? "";
  notes.value = v?.notes ?? "";
});

const dealOptions = computed(() =>
  dealLabels.value.map((d) => ({ label: d.contact === d.title ? d.contact : `${d.contact} — ${d.title}`, value: d.id })),
);
const kindOptions = computed(() =>
  visitTypes.value
    .filter((x) => !props.dealId || x.requires_deal)
    .map((x) => ({ label: x.name, value: x.key })),
);
// A type like جولة خارجية is not tied to any deal, so the deal field goes away.
const needsDeal = computed(() => !kind.value || kindRequiresDeal(kind.value));

const timeOrderOk = computed(() => !timeFrom.value || !timeTo.value || timeTo.value > timeFrom.value);
const valid = computed(
  () =>
    !!kind.value &&
    (!needsDeal.value || !!selectedDeal.value) &&
    !!visitDate.value &&
    !!timeFrom.value &&
    !!timeTo.value &&
    timeOrderOk.value &&
    address.value.trim().length > 0,
);

async function submit() {
  if (!valid.value || !user.value?.sub) return;
  saving.value = true;

  const details = {
    kind: kind.value,
    visit_date: visitDate.value,
    time_from: timeFrom.value,
    time_to: timeTo.value,
    address: address.value.trim(),
    notes: notes.value.trim() || null,
  };
  const { error } = props.visit
    ? await supabase.from("field_visits").update(details).eq("id", props.visit.id)
    : await supabase
        .from("field_visits")
        .insert({
          ...details,
          deal_id: needsDeal.value ? selectedDeal.value! : null,
          requested_by: user.value.sub as string,
        });
  saving.value = false;

  if (error) {
    toast.add({ title: t("crm.visits.saveFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t(editing.value ? "crm.visits.saved" : "crm.visits.submitted"), color: "success" });
  open.value = false;
  emit("saved");
}
</script>

<template>
  <UModal v-model:open="open" :title="t(editing ? 'crm.visits.edit' : 'crm.visits.new')">
    <template #body>
      <div class="space-y-4">
        <UFormField :label="t('crm.visits.kindLabel')">
          <URadioGroup
            v-model="kind"
            orientation="horizontal"
            :items="kindOptions"
            value-key="value"
            :disabled="editing"
          />
        </UFormField>

        <UFormField v-if="needsDeal" :label="t('crm.visits.deal')" required>
          <USelectMenu
            v-model="selectedDeal"
            :items="dealOptions"
            value-key="value"
            searchable
            :disabled="editing || !!dealId"
            :placeholder="t('crm.visits.pickDeal')"
            class="w-full"
          />
        </UFormField>

        <UFormField :label="t('crm.visits.date')" required>
          <UInput v-model="visitDate" type="date" :min="editing ? undefined : today" class="w-full" />
        </UFormField>

        <div class="grid grid-cols-2 gap-3">
          <UFormField :label="t('crm.visits.timeFrom')" required>
            <UInput v-model="timeFrom" type="time" class="w-full" />
          </UFormField>
          <UFormField :label="t('crm.visits.timeTo')" required :error="!timeOrderOk ? t('crm.visits.timeOrder') : undefined">
            <UInput v-model="timeTo" type="time" class="w-full" />
          </UFormField>
        </div>

        <UFormField :label="t('crm.visits.address')" required>
          <UInput v-model="address" icon="i-lucide-map-pin" class="w-full" />
        </UFormField>

        <UFormField :label="t('crm.visits.notes')">
          <UTextarea v-model="notes" :rows="3" class="w-full" />
        </UFormField>

        <UButton
          :label="t(editing ? 'crm.visits.save' : 'crm.visits.submit')"
          :loading="saving"
          :disabled="!valid"
          size="lg"
          block
          @click="submit"
        />
      </div>
    </template>
  </UModal>
</template>
