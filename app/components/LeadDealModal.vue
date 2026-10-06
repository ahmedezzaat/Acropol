<script setup lang="ts">
// "Create a deal" for a lead you are already looking at: the lead is fixed, so
// the form only asks what the customer is interested in, which pipeline, and
// (with the assign permission) who owns it. The deal starts in the pipeline's
// first stage, exactly like creating it from the Deals page.
const props = defineProps<{
  lead: { id: string; name: string; customer_id: string | null; assigned_to: string | null } | null;
}>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ created: [] }>();

const supabase = useSupabaseClient();
const toast = useToast();
const { hasPermission } = usePermissions();
const { t } = useI18n();

interface Category {
  id: string;
  name: string;
}
interface Pipeline {
  id: string;
  name: string;
}
interface Stage {
  id: string;
  pipeline_id: string;
  sort_order: number;
}
interface Profile {
  id: string;
  full_name: string | null;
  email: string;
}

const categories = ref<Category[]>([]);
const pipelines = ref<Pipeline[]>([]);
const stages = ref<Stage[]>([]);
const profiles = ref<Profile[]>([]);

const categoryIds = ref<string[]>([]);
const pipelineId = ref<string | undefined>(undefined);
const assignedTo = ref<string | null>(null);
const saving = ref(false);

const canAssign = computed(() => hasPermission("crm_deals", "assign"));

const categoryItems = computed(() => categories.value.map((c) => ({ label: c.name, value: c.id })));
const pipelineItems = computed(() => pipelines.value.map((p) => ({ label: p.name, value: p.id })));
const assigneeItems = computed(() => [
  { label: t("common.unassigned"), value: null },
  ...profiles.value.map((p) => ({ label: p.full_name || p.email, value: p.id })),
]);

watch(open, async (isOpen) => {
  if (!isOpen) return;
  categoryIds.value = [];
  assignedTo.value = props.lead?.assigned_to ?? null;
  const [cats, pips, stg, people] = await Promise.all([
    supabase.from("product_categories").select("id, name").order("sort_order"),
    supabase.from("pipelines").select("id, name").order("sort_order"),
    supabase.from("pipeline_stages").select("id, pipeline_id, sort_order").order("sort_order"),
    supabase.from("profiles").select("id, full_name, email").eq("is_active", true),
  ]);
  categories.value = cats.data ?? [];
  pipelines.value = pips.data ?? [];
  stages.value = stg.data ?? [];
  profiles.value = people.data ?? [];
  pipelineId.value = pipelines.value[0]?.id;
});

const firstStageId = computed(
  () => stages.value.filter((s) => s.pipeline_id === pipelineId.value).sort((a, b) => a.sort_order - b.sort_order)[0]?.id,
);
const valid = computed(() => !!props.lead && categoryIds.value.length > 0 && !!pipelineId.value && !!firstStageId.value);

async function create() {
  if (!valid.value || !props.lead) return;
  saving.value = true;

  const title = categories.value
    .filter((c) => categoryIds.value.includes(c.id))
    .map((c) => c.name)
    .join("، ");

  const payload: Record<string, unknown> = {
    title,
    lead_id: props.lead.id,
    customer_id: props.lead.customer_id,
    pipeline_id: pipelineId.value,
    stage_id: firstStageId.value,
  };
  // Without the assign permission the database makes the creator the owner.
  if (canAssign.value) payload.assigned_to = assignedTo.value;

  const { error } = await supabase.from("deals").insert(payload);
  saving.value = false;

  if (error) {
    toast.add({ title: t("crm.deals.createDealFailed"), description: error.message, color: "error" });
    return;
  }
  toast.add({ title: t("crm.deals.dealCreated"), color: "success" });
  open.value = false;
  emit("created");
}

function removeCategory(id: string) {
  categoryIds.value = categoryIds.value.filter((v) => v !== id);
}
</script>

<template>
  <UModal v-model:open="open" :title="t('crm.leads.createDealFor', { name: lead?.name ?? '' })">
    <template #body>
      <div class="space-y-4">
        <UFormField :label="t('crm.deals.dealTitle')" required>
          <USelectMenu
            v-model="categoryIds"
            :items="categoryItems"
            value-key="value"
            multiple
            :placeholder="t('crm.deals.selectCategories')"
            class="w-full"
          >
            <template #default>
              <div v-if="categoryIds.length" class="flex flex-wrap gap-1 py-0.5">
                <UBadge v-for="id in categoryIds" :key="id" color="neutral" variant="subtle" class="gap-1">
                  {{ categoryItems.find((c) => c.value === id)?.label }}
                  <UIcon name="i-lucide-x" class="size-3 cursor-pointer" @click.stop="removeCategory(id)" />
                </UBadge>
              </div>
              <span v-else class="text-muted">{{ t("crm.deals.selectCategories") }}</span>
            </template>
          </USelectMenu>
        </UFormField>

        <UFormField :label="t('crm.deals.pipeline')">
          <USelect v-model="pipelineId" :items="pipelineItems" value-key="value" class="w-full" />
        </UFormField>

        <UFormField v-if="canAssign" :label="t('crm.deals.assignedTo')">
          <USelect v-model="assignedTo" :items="assigneeItems" value-key="value" class="w-full" />
        </UFormField>

        <UButton
          :label="t('crm.leads.createDealSubmit')"
          :loading="saving"
          :disabled="!valid"
          size="lg"
          block
          @click="create"
        />
      </div>
    </template>
  </UModal>
</template>
