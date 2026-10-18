<script setup lang="ts">
// Assign confirmed visits to a technician (or reassign / unassign). The products
// of one customer visit are assigned together; every product keeps its own entry
// in the maintenance history.
const props = defineProps<{ products: CsProduct[] }>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ saved: [] }>();

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

interface Technician {
  id: string;
  full_name: string | null;
  email: string;
}
const technicians = ref<Technician[]>([]);
const technicianId = ref<string | null>(null);
const note = ref("");
const saving = ref(false);

watch(open, async (isOpen) => {
  if (!isOpen) return;
  const { data } = await supabase.from("profiles").select("id, full_name, email").eq("is_technician", true).eq("is_active", true).order("full_name");
  technicians.value = (data ?? []) as Technician[];
  // start on the technician already assigned when they all share one
  const current = [...new Set(props.products.map((p) => p.maintenance_technician_id ?? null))];
  technicianId.value = current.length === 1 ? current[0]! : null;
  note.value = "";
});

const items = computed(() => [
  { label: t("cs.maintenance.unassigned"), value: null as string | null },
  ...technicians.value.map((u) => ({ label: u.full_name || u.email, value: u.id as string | null })),
]);

async function save() {
  if (!props.products.length) return;
  saving.value = true;
  const now = new Date().toISOString();
  for (const p of props.products) {
    const { error } = await supabase
      .from("customer_products")
      .update({ maintenance_technician_id: technicianId.value, maintenance_assigned_at: technicianId.value ? now : null })
      .eq("id", p.id);
    if (error) {
      saving.value = false;
      toast.add({ title: t("cs.maintenance.assignFailed"), description: error.message, color: "error" });
      return;
    }
    await supabase.from("product_maintenance_log").insert({
      product_id: p.id,
      kind: "assigned",
      scheduled_for: p.next_maintenance_at,
      technician_id: technicianId.value,
      note: note.value.trim() || null,
    });
  }
  saving.value = false;
  toast.add({ title: t("cs.maintenance.assigned"), color: "success" });
  open.value = false;
  emit("saved");
}

function close() {
  open.value = false;
}
</script>

<template>
  <UModal v-model:open="open" :title="t('cs.maintenance.assignTitle')">
    <template #body>
      <div class="space-y-4">
        <ul class="space-y-1 text-sm">
          <li v-for="p in products" :key="p.id" class="flex items-center gap-2">
            <UIcon name="i-lucide-wrench" class="size-4 shrink-0 text-muted" />
            <span class="truncate">{{ p.name }}</span>
            <span v-if="(p.quantity ?? 1) > 1" class="text-xs text-muted">× {{ p.quantity }}</span>
          </li>
        </ul>

        <UFormField :label="t('cs.maintenance.technician')" required>
          <USelect
            :model-value="technicianId"
            :items="items"
            value-key="value"
            icon="i-lucide-hard-hat"
            class="w-full"
            @update:model-value="(v: string | null) => (technicianId = v)"
          />
        </UFormField>
        <p v-if="!technicians.length" class="text-xs text-warning">{{ t("cs.maintenance.noTechnicians") }}</p>
        <UFormField :label="t('cs.maintenance.assignNote')">
          <UTextarea v-model="note" :rows="2" class="w-full" />
        </UFormField>

        <div class="flex gap-2">
          <UButton color="neutral" variant="outline" :label="t('common.cancel')" class="flex-1 justify-center" @click="close" />
          <UButton icon="i-lucide-user-check" :label="t('common.save')" :loading="saving" class="flex-1 justify-center" @click="save" />
        </div>
      </div>
    </template>
  </UModal>
</template>
