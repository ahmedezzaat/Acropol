<script setup lang="ts">
// Add a maintenance entry to one of a customer's products from the customer's
// profile: a visit that was done, an appointment that is scheduled, or one that
// was cancelled. Each has a date, what happened, and an optional cost.
const props = defineProps<{ customerId: string; products: CsProduct[] }>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ saved: [] }>();

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();
const { hasPermission } = usePermissions();

type RecordType = "done" | "scheduled" | "cancelled";
const typeAllowed: Record<RecordType, ComputedRef<boolean>> = {
  done: computed(() => hasPermission("cs_maintenance", "complete")),
  scheduled: computed(() => hasPermission("cs_maintenance", "schedule")),
  cancelled: computed(() => hasPermission("cs_maintenance", "cancel")),
};
const typeItems = computed(() =>
  (["done", "scheduled", "cancelled"] as const)
    .filter((k) => typeAllowed[k].value)
    .map((k) => ({ label: t(`cs.maintenance.stat.${k === "cancelled" ? "declined" : k}`), value: k })),
);
const canUpdateProduct = computed(() => hasPermission("cs_customers", "edit"));

const pad = (n: number) => String(n).padStart(2, "0");
const todayIso = () => {
  const d = new Date();
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
};
const nowLocal = () => {
  const d = new Date();
  return `${todayIso()}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
};

const productId = ref<string | null>(null);
const type = ref<RecordType>("done");
const doneOn = ref("");
const when = ref("");
const note = ref("");
const cost = ref<number | null>(null);
const saving = ref(false);

watch(open, (isOpen) => {
  if (!isOpen) return;
  productId.value = props.products[0]?.id ?? null;
  type.value = typeItems.value[0]?.value ?? "done";
  doneOn.value = todayIso();
  when.value = nowLocal();
  note.value = "";
  cost.value = null;
});

const productItems = computed(() => props.products.map((p) => ({ label: p.name, value: p.id })));
const valid = computed(
  () => !!productId.value && (type.value === "done" ? !!doneOn.value : !!when.value) && (cost.value === null || cost.value >= 0),
);

const sameDay = (a: string, b: string) => new Date(a).toDateString() === new Date(b).toDateString();

async function save() {
  const product = props.products.find((p) => p.id === productId.value);
  if (!product || !valid.value) return;
  saving.value = true;

  const at = type.value === "done" ? null : new Date(when.value).toISOString();
  const futureAppointment = type.value === "scheduled" && !!at && new Date(at).getTime() > Date.now();
  const row = {
    product_id: product.id,
    kind: type.value === "scheduled" && product.next_maintenance_at && futureAppointment ? "rescheduled" : type.value,
    done_on: type.value === "done" ? doneOn.value : null,
    scheduled_for: at,
    note: note.value.trim() || null,
    cost: cost.value,
  };
  const { error } = await supabase.from("product_maintenance_log").insert(row);
  if (error) {
    saving.value = false;
    toast.add({ title: t("cs.maintenance.saveFailed"), description: error.message, color: "error" });
    return;
  }

  // Keep the product's own maintenance state in step with what was recorded.
  if (canUpdateProduct.value) {
    const patch: { last_maintenance_on?: string; next_maintenance_at?: string | null; next_maintenance_note?: string | null } = {};
    if (type.value === "done") {
      if (!product.last_maintenance_on || doneOn.value > product.last_maintenance_on) patch.last_maintenance_on = doneOn.value;
      // The booked appointment has been carried out.
      if (product.next_maintenance_at && product.next_maintenance_at.slice(0, 10) <= doneOn.value) {
        patch.next_maintenance_at = null;
        patch.next_maintenance_note = null;
      }
    } else if (futureAppointment) {
      patch.next_maintenance_at = at;
      patch.next_maintenance_note = note.value.trim() || null;
    } else if (type.value === "cancelled" && at && product.next_maintenance_at && sameDay(product.next_maintenance_at, at)) {
      patch.next_maintenance_at = null;
      patch.next_maintenance_note = null;
    }
    if (Object.keys(patch).length) await supabase.from("customer_products").update(patch).eq("id", product.id);
  }

  saving.value = false;
  toast.add({ title: t("cs.profile.recordSaved"), color: "success" });
  open.value = false;
  emit("saved");
}
</script>

<template>
  <UModal v-model:open="open" :title="t('cs.profile.addMaintenanceRecord')">
    <template #body>
      <div class="space-y-4">
        <UFormField v-if="products.length > 1" :label="t('cs.profile.recordProduct')" required>
          <USelect :model-value="productId ?? undefined" :items="productItems" value-key="value" class="w-full" @update:model-value="(v: string | undefined) => (productId = v ?? null)" />
        </UFormField>
        <p v-else-if="products[0]" class="text-sm font-medium text-highlighted">{{ products[0].name }}</p>

        <UFormField :label="t('cs.profile.recordType')" required>
          <URadioGroup v-model="type" orientation="horizontal" :items="typeItems" value-key="value" />
        </UFormField>

        <UFormField :label="t('cs.profile.recordDate')" required>
          <UInput v-if="type === 'done'" v-model="doneOn" type="date" class="w-full" />
          <UInput v-else v-model="when" type="datetime-local" class="w-full" />
        </UFormField>
        <UFormField :label="t('cs.profile.whatHappened')">
          <UTextarea v-model="note" :rows="3" class="w-full" />
        </UFormField>
        <UFormField :label="t('cs.profile.costOptional')">
          <UInputNumber v-model="cost" :min="0" class="w-full" />
        </UFormField>

        <UButton :label="t('common.save')" :loading="saving" :disabled="!valid" size="lg" block @click="save" />
      </div>
    </template>
  </UModal>
</template>
