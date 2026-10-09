<script setup lang="ts">
// Add (or edit) a product on a customer: its name, category and contract date. A new product starts in the first stage of the chosen
// pipeline. (Instruments are not entered here; saving never touches them.)
const props = defineProps<{ customerId: string; product?: CsProduct | null }>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ saved: [] }>();

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

interface Category {
  id: string;
  name: string;
}

const { pipelines, loadPipelines, stagesOf } = useCs();

const editing = computed(() => !!props.product);
const pipelineId = ref<string | undefined>(undefined);
const saving = ref(false);

const name = ref("");
const categoryId = ref<string | null>(null);
const contractCode = ref("");
const contractDate = ref("");
const operationDate = ref("");
const warrantyStatus = ref<string | null>(null);
const warrantyDetails = ref("");
const paymentStatus = ref<string | null>(null);
const notes = ref("");
const categories = ref<Category[]>([]);
const salesPersonId = ref<string | null>(null);
const people = ref<{ id: string; full_name: string | null; email: string }[]>([]);

watch(open, async (isOpen) => {
  if (!isOpen) return;
  const [{ data }, { data: users }] = await Promise.all([
    supabase.from("product_categories").select("id, name").order("sort_order"),
    supabase.from("profiles").select("id, full_name, email").eq("is_active", true).order("full_name"),
    loadPipelines(),
  ]);
  categories.value = data ?? [];
  people.value = users ?? [];
  const p = props.product;
  pipelineId.value = p?.pipeline_id ?? pipelines.value[0]?.id;
  name.value = p?.name ?? "";
  categoryId.value = p?.category_id ?? null;
  contractCode.value = p?.contract_code ?? "";
  salesPersonId.value = p?.sales_person_id ?? null;
  contractDate.value = p?.contract_date ?? "";
  operationDate.value = p?.operation_date ?? "";
  warrantyStatus.value = p?.warranty_status ?? null;
  warrantyDetails.value = p?.warranty_details ?? "";
  paymentStatus.value = p?.payment_status ?? null;
  notes.value = p?.notes ?? "";
});

const pipelineItems = computed(() => pipelines.value.map((x) => ({ label: x.name, value: x.id })));
const firstStageId = computed(() => stagesOf(pipelineId.value)[0]?.id);
const firstStageName = computed(() => stagesOf(pipelineId.value)[0]?.name ?? "");

const categoryItems = computed(() => [
  { label: t("cs.profile.noCategory"), value: null },
  ...categories.value.map((c) => ({ label: c.name, value: c.id })),
]);

const salesPersonItems = computed(() => {
  const items = [
    { label: t("cs.profile.noSalesPerson"), value: null as string | null },
    ...people.value.map((u) => ({ label: u.full_name || u.email, value: u.id as string | null })),
  ];
  // Keep the saved person selectable even if they were deactivated since.
  const saved = props.product?.sales_person_id;
  if (saved && !items.some((i) => i.value === saved)) items.push({ label: "—", value: saved });
  return items;
});

const warrantyItems = computed(() => [
  { label: t("cs.profile.notSet"), value: null },
  { label: t("cs.profile.yes"), value: "in_warranty" },
  { label: t("cs.profile.no"), value: "out_of_warranty" },
]);
const paymentItems = computed(() => [
  { label: t("cs.profile.notSet"), value: null },
  { label: t("cs.profile.yes"), value: "paid" },
  { label: t("cs.profile.no"), value: "unpaid" },
]);

const valid = computed(() => name.value.trim().length > 0 && (editing.value || (!!pipelineId.value && !!firstStageId.value)));

async function save() {
  if (!valid.value) return;
  saving.value = true;

  const details = {
    name: name.value.trim(),
    category_id: categoryId.value,
    contract_code: contractCode.value.trim() || null,
    sales_person_id: salesPersonId.value,
    contract_date: contractDate.value || null,
    operation_date: operationDate.value || null,
    warranty_status: warrantyStatus.value,
    warranty_details: warrantyDetails.value.trim() || null,
    payment_status: paymentStatus.value,
    notes: notes.value.trim() || null,
  };

  if (props.product) {
    const { error } = await supabase.from("customer_products").update(details).eq("id", props.product.id);
    if (error) return fail(error.message);
  } else {
    const { error } = await supabase
      .from("customer_products")
      .insert({ ...details, customer_id: props.customerId, pipeline_id: pipelineId.value! });
    if (error) return fail(error.message);
  }

  saving.value = false;
  toast.add({ title: t(editing.value ? "cs.profile.productSaved" : "cs.profile.productAdded"), color: "success" });
  open.value = false;
  emit("saved");
}

function fail(message?: string) {
  saving.value = false;
  toast.add({ title: t("cs.profile.productSaveFailed"), description: message, color: "error" });
}
</script>

<template>
  <UModal v-model:open="open" :title="t(editing ? 'cs.profile.editProduct' : 'cs.profile.addProduct')">
    <template #body>
      <div class="space-y-4">
        <UFormField :label="t('cs.profile.productName')" required>
          <UInput v-model="name" :placeholder="t('cs.profile.productNameHint')" class="w-full" />
        </UFormField>
        <!-- Where a new product starts: always the funnel's first stage. -->
        <p v-if="!editing && firstStageName" class="flex items-center gap-1.5 text-sm text-muted">
          <UIcon name="i-lucide-flag" class="size-4" />
          {{ t("cs.profile.startsIn", { stage: firstStageName }) }}
        </p>
        <UFormField v-if="!editing && pipelines.length > 1" :label="t('cs.profile.pipeline')">
          <USelect v-model="pipelineId" :items="pipelineItems" value-key="value" class="w-full" />
        </UFormField>
        <UFormField :label="t('cs.profile.salesPerson')">
          <USelect v-model="salesPersonId" :items="salesPersonItems" value-key="value" icon="i-lucide-user-round" class="w-full" />
        </UFormField>
        <UFormField :label="t('cs.profile.category')">
          <USelect v-model="categoryId" :items="categoryItems" value-key="value" class="w-full" />
        </UFormField>

        <div class="grid gap-3 sm:grid-cols-2">
          <UFormField :label="t('cs.profile.contractCode')">
            <UInput v-model="contractCode" dir="ltr" class="w-full" />
          </UFormField>
          <UFormField :label="t('cs.profile.contractDate')">
            <UInput v-model="contractDate" type="date" class="w-full" />
          </UFormField>
          <UFormField :label="t('cs.profile.operationDate')">
            <UInput v-model="operationDate" type="date" class="w-full" />
          </UFormField>
          <UFormField :label="t('cs.profile.warrantyLabel')">
            <USelect v-model="warrantyStatus" :items="warrantyItems" value-key="value" class="w-full" />
          </UFormField>
          <UFormField :label="t('cs.profile.paymentLabel')">
            <USelect v-model="paymentStatus" :items="paymentItems" value-key="value" class="w-full" />
          </UFormField>
        </div>
        <UFormField :label="t('cs.profile.warrantyDetails')">
          <UTextarea v-model="warrantyDetails" :rows="2" class="w-full" />
        </UFormField>

        <UFormField :label="t('cs.profile.notes')">
          <UTextarea v-model="notes" :rows="3" class="w-full" />
        </UFormField>

        <UButton
          :label="t(editing ? 'common.save' : 'cs.profile.addProduct')"
          :loading="saving"
          :disabled="!valid"
          size="lg"
          block
          @click="save"
        />
      </div>
    </template>
  </UModal>
</template>
