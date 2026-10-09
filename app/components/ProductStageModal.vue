<script setup lang="ts">
// Move a product through its pipeline's stages and keep the date of every
// stage. Picking the current stage and its date is the common case; the other
// dates can be filled in or corrected too.
const props = defineProps<{ product: CsProduct | null }>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ saved: [] }>();

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();
const { stagesOf, loadPipelines } = useCs();

const stage = ref<string>("");
const dates = reactive<Record<string, string>>({});
const saving = ref(false);

const today = new Date().toISOString().slice(0, 10);
const productStages = computed(() => stagesOf(props.product?.pipeline_id));

watch(open, async (isOpen) => {
  if (!isOpen || !props.product) return;
  await loadPipelines();
  const { data } = await supabase
    .from("customer_product_stage_dates")
    .select("stage_id, reached_on")
    .eq("product_id", props.product.id);
  stage.value = props.product.stage_id;
  for (const key of Object.keys(dates)) delete dates[key];
  for (const s of productStages.value) dates[s.id] = "";
  for (const row of data ?? []) dates[row.stage_id] = row.reached_on;
});

// Choosing a stage that has no date yet proposes today, except for stages that
// require the date to be typed in (e.g. the real operation date): those stay
// blank so saving is blocked until the user enters it.
const mustEnter = computed(() => !!productStages.value.find((s) => s.id === stage.value)?.require_date);
watch(stage, (id) => {
  if (!open.value || !id || dates[id]) return;
  if (!productStages.value.find((s) => s.id === id)?.require_date) dates[id] = today;
});

const stageItems = computed(() => productStages.value.map((s) => ({ label: s.name, value: s.id })));
const valid = computed(() => !!stage.value && !!dates[stage.value]);

async function save() {
  if (!props.product || !valid.value) return;
  saving.value = true;

  const { error } = await supabase.from("customer_products").update({ stage_id: stage.value }).eq("id", props.product.id);
  if (error) return fail(error.message);

  const filled = productStages.value.filter((s) => dates[s.id]);
  const blank = productStages.value.filter((s) => !dates[s.id]).map((s) => s.id);
  if (filled.length) {
    const { error: upError } = await supabase.from("customer_product_stage_dates").upsert(
      filled.map((s) => ({ product_id: props.product!.id, stage_id: s.id, reached_on: dates[s.id]! })),
      { onConflict: "product_id,stage_id" },
    );
    if (upError) return fail(upError.message);
  }
  if (blank.length) {
    const { error: delError } = await supabase
      .from("customer_product_stage_dates")
      .delete()
      .eq("product_id", props.product.id)
      .in("stage_id", blank);
    if (delError) return fail(delError.message);
  }

  saving.value = false;
  toast.add({ title: t("cs.installations.saved"), color: "success" });
  open.value = false;
  emit("saved");
}

function fail(message?: string) {
  saving.value = false;
  toast.add({ title: t("cs.installations.saveFailed"), description: message, color: "error" });
}
</script>

<template>
  <UModal v-model:open="open" :title="t('cs.installations.updateProgress')">
    <template #body>
      <div v-if="product" class="space-y-4">
        <p class="text-sm font-medium text-highlighted">{{ product.name }}</p>

        <UFormField :label="t('cs.installations.currentStage')">
          <URadioGroup v-model="stage" :items="stageItems" value-key="value" />
        </UFormField>

        <div class="space-y-2">
          <span class="text-sm font-medium text-highlighted">{{ t("cs.installations.stageDates") }}</span>
          <div v-for="s in productStages" :key="s.id" class="grid grid-cols-[6rem_1fr] items-center gap-3">
            <span class="truncate text-sm" :class="s.id === stage ? 'font-semibold text-primary' : 'text-muted'">{{ s.name }}</span>
            <UInput v-model="dates[s.id]" type="date" class="w-full" />
          </div>
          <p v-if="!valid" class="text-xs text-error">
            {{ t(mustEnter ? "cs.installations.dateMustEnter" : "cs.installations.dateRequired") }}
          </p>
        </div>

        <UButton :label="t('common.save')" :loading="saving" :disabled="!valid" size="lg" block @click="save" />
      </div>
    </template>
  </UModal>
</template>
