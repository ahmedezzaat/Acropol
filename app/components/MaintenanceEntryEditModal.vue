<script setup lang="ts">
// Correct a logged maintenance visit: the note and cost of each product, and for a
// visit that was done, its date and who did it. Which kind of entry it is, and
// which product it is about, stay as recorded.
interface EditItem {
  type: "done" | "scheduled" | "cancelled" | "other";
  entries: CsMaintenanceLog[];
  visit: CsMaintenanceVisit | null;
}
const props = defineProps<{ item: EditItem | null; productName: (productId: string) => string }>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ saved: [] }>();

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

const isDone = computed(() => props.item?.entries[0]?.kind === "done");

interface Row {
  id: string;
  productId: string;
  note: string;
  cost: number | null;
  technicianId: string | null;
}
const rows = ref<Row[]>([]);
const doneOn = ref("");
const visitNote = ref("");
const saving = ref(false);

const technicians = ref<{ label: string; value: string | null }[]>([]);

watch(open, async (isOpen) => {
  if (!isOpen || !props.item) return;
  const first = props.item.entries[0]!;
  rows.value = props.item.entries.map((e) => ({
    id: e.id,
    productId: e.product_id,
    note: e.note ?? "",
    cost: e.cost,
    technicianId: e.technician_id ?? null,
  }));
  doneOn.value = (first.done_on ?? "").slice(0, 10);
  visitNote.value = props.item.visit?.note ?? "";
  if (isDone.value) {
    const { data } = await supabase.from("profiles").select("id, full_name, email").eq("is_technician", true).order("full_name");
    technicians.value = [
      { label: t("cs.maintenance.unassigned"), value: null },
      ...(data ?? []).map((p) => ({ label: p.full_name || p.email, value: p.id as string | null })),
    ];
  }
});

const valid = computed(() => (!isDone.value || !!doneOn.value) && rows.value.every((r) => r.cost === null || r.cost >= 0));

function setTechnician(row: Row, v: unknown) {
  row.technicianId = typeof v === "string" && v ? v : null;
}

async function save() {
  if (!props.item || !valid.value) return;
  saving.value = true;
  for (const r of rows.value) {
    const patch: { note: string | null; cost?: number | null; done_on?: string; technician_id?: string | null } = { note: r.note.trim() || null };
    if (isDone.value) {
      patch.cost = r.cost;
      patch.done_on = doneOn.value;
      patch.technician_id = r.technicianId;
    }
    const { error } = await supabase.from("product_maintenance_log").update(patch).eq("id", r.id);
    if (error) {
      saving.value = false;
      toast.add({ title: t("cs.maintenance.saveFailed"), description: error.message, color: "error" });
      return;
    }
  }
  if (props.item.visit) {
    const { error } = await supabase
      .from("maintenance_visits")
      .update({
        note: visitNote.value.trim() || null,
        ...(isDone.value ? { visit_at: new Date(`${doneOn.value}T12:00:00`).toISOString() } : {}),
      })
      .eq("id", props.item.visit.id);
    if (error) {
      saving.value = false;
      toast.add({ title: t("cs.maintenance.saveFailed"), description: error.message, color: "error" });
      return;
    }
  }
  saving.value = false;
  toast.add({ title: t("cs.profile.entryEdited"), color: "success" });
  open.value = false;
  emit("saved");
}
</script>

<template>
  <UModal v-model:open="open" :title="t('cs.profile.editEntry')">
    <template #body>
      <div v-if="item" class="space-y-4">
        <UFormField v-if="isDone" :label="t('cs.maintenance.doneOn')" required>
          <UInput v-model="doneOn" type="date" class="w-full" />
        </UFormField>

        <div v-for="r in rows" :key="r.id" class="space-y-3 border border-default p-3">
          <p class="text-sm font-medium text-highlighted">{{ productName(r.productId) }}</p>
          <div class="grid gap-3" :class="isDone && 'sm:grid-cols-2'">
            <UFormField v-if="isDone" :label="t('cs.profile.costOptional')">
              <UInputNumber v-model="r.cost" :min="0" class="w-full" />
            </UFormField>
            <UFormField v-if="isDone" :label="t('cs.maintenance.technician')">
              <USelect :model-value="r.technicianId" :items="technicians" value-key="value" class="w-full" @update:model-value="(v) => setTechnician(r, v)" />
            </UFormField>
          </div>
          <UFormField :label="isDone ? t('cs.profile.whatHappened') : t('cs.maintenance.note')">
            <UTextarea v-model="r.note" :rows="2" class="w-full" />
          </UFormField>
        </div>

        <UFormField v-if="item.visit" :label="t('cs.profile.visitNote')">
          <UTextarea v-model="visitNote" :rows="2" class="w-full" />
        </UFormField>

        <UButton :label="t('common.save')" :loading="saving" :disabled="!valid" size="lg" block @click="save" />
      </div>
    </template>
  </UModal>
</template>
