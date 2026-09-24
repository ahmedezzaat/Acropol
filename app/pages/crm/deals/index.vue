<script setup lang="ts">
import * as z from "zod";
import type { FormSubmitEvent } from "@nuxt/ui";

definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "crm_deals" },
});

const supabase = useSupabaseClient();
const toast = useToast();
const { hasPermission } = usePermissions();
const { t } = useI18n();

interface Pipeline {
  id: string;
  name: string;
  sort_order: number;
}

interface Stage {
  id: string;
  pipeline_id: string;
  name: string;
  sort_order: number;
  is_closed: boolean;
  reason_category: "archive" | "competitor" | null;
}

interface Reason {
  id: string;
  pipeline_id: string;
  category: "archive" | "competitor";
  name: string;
}

interface Deal {
  id: string;
  title: string;
  value: number | null;
  customer_id: string;
  pipeline_id: string;
  stage_id: string;
  assigned_to: string | null;
}

interface Customer {
  id: string;
  name: string;
}

interface Profile {
  id: string;
  full_name: string | null;
  email: string;
}

const { data: pipelines } = await useAsyncData<Pipeline[]>("crm-deals-pipelines", async () => {
  const { data, error } = await supabase.from("pipelines").select("id, name, sort_order").order("sort_order");
  if (error) throw error;
  return data ?? [];
});

const { data: allStages } = await useAsyncData<Stage[]>("crm-deals-stages", async () => {
  const { data, error } = await supabase
    .from("pipeline_stages")
    .select("id, pipeline_id, name, sort_order, is_closed, reason_category")
    .order("sort_order");
  if (error) throw error;
  return data ?? [];
});

const { data: allReasons } = await useAsyncData<Reason[]>("crm-deals-reasons", async () => {
  const { data, error } = await supabase
    .from("pipeline_stage_reasons")
    .select("id, pipeline_id, category, name")
    .order("sort_order");
  if (error) throw error;
  return data ?? [];
});

const { data: deals, refresh, status } = await useAsyncData<Deal[]>("crm-deals", async () => {
  const { data, error } = await supabase
    .from("deals")
    .select("id, title, value, customer_id, pipeline_id, stage_id, assigned_to")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data ?? [];
});

const { data: customers } = await useAsyncData<Customer[]>("crm-deals-customers", async () => {
  const { data, error } = await supabase.from("customers").select("id, name").order("name");
  if (error) throw error;
  return data ?? [];
});

const { data: profiles } = await useAsyncData<Profile[]>("crm-deals-profiles", async () => {
  const { data, error } = await supabase.from("profiles").select("id, full_name, email").eq("is_active", true);
  if (error) throw error;
  return data ?? [];
});

const customerOptions = computed(() =>
  (customers.value ?? []).map((c) => ({ label: c.name, value: c.id })),
);
function customerName(id: string) {
  return customers.value?.find((c) => c.id === id)?.name ?? "—";
}
const assigneeOptions = computed(() => [
  { label: t("common.unassigned"), value: null },
  ...(profiles.value ?? []).map((p) => ({ label: p.full_name || p.email, value: p.id })),
]);
function assigneeInitial(id: string | null) {
  const p = profiles.value?.find((p) => p.id === id);
  const label = p?.full_name || p?.email || "";
  return label.charAt(0).toUpperCase();
}

const activePipelineId = ref<string | null>(null);
watchEffect(() => {
  if (!activePipelineId.value && pipelines.value?.length) {
    activePipelineId.value = pipelines.value[0].id;
  }
});

const pipelineTabs = computed(() =>
  (pipelines.value ?? []).map((p) => ({ label: p.name, value: p.id })),
);

const activeStages = computed(() =>
  (allStages.value ?? []).filter((s) => s.pipeline_id === activePipelineId.value),
);

function dealsForStage(stageId: string) {
  return (deals.value ?? []).filter((d) => d.stage_id === stageId);
}

// --- Create deal ---
const createOpen = ref(false);
const creating = ref(false);

const schema = computed(() =>
  z
    .object({
      title: z.string().min(1, t("validation.required")),
      customer_id: z.uuid(t("validation.required")),
      pipeline_id: z.uuid(t("validation.required")),
      stage_id: z.uuid(t("validation.required")),
      stage_reason_id: z.uuid().nullable().optional(),
      assigned_to: z.uuid().nullable().optional(),
      value: z.number().optional(),
      expected_close_date: z.string().optional(),
    })
    .superRefine((data, ctx) => {
      const stage = allStages.value?.find((s) => s.id === data.stage_id);
      if (stage?.reason_category && !data.stage_reason_id) {
        ctx.addIssue({ message: t("validation.required"), path: ["stage_reason_id"] });
      }
    }),
);
type Schema = {
  title: string;
  customer_id: string;
  pipeline_id: string;
  stage_id: string;
  stage_reason_id?: string | null;
  assigned_to?: string | null;
  value?: number;
  expected_close_date?: string;
};
const state = reactive<Partial<Schema>>({
  title: "",
  customer_id: undefined,
  pipeline_id: undefined,
  stage_id: undefined,
  stage_reason_id: null,
  assigned_to: null,
  value: undefined,
  expected_close_date: "",
});
const canAssign = computed(() => hasPermission("crm_deals", "assign"));

const createPipelineStages = computed(() =>
  (allStages.value ?? []).filter((s) => s.pipeline_id === state.pipeline_id),
);
const createStage = computed(() => allStages.value?.find((s) => s.id === state.stage_id));
const createReasonOptions = computed(() =>
  (allReasons.value ?? [])
    .filter((r) => r.pipeline_id === state.pipeline_id && r.category === createStage.value?.reason_category)
    .map((r) => ({ label: r.name, value: r.id })),
);

function openCreate() {
  state.pipeline_id = activePipelineId.value ?? undefined;
  const firstStage = createPipelineStages.value[0];
  state.stage_id = firstStage?.id;
  state.stage_reason_id = null;
  createOpen.value = true;
}

watch(
  () => state.pipeline_id,
  () => {
    const firstStage = createPipelineStages.value[0];
    state.stage_id = firstStage?.id;
    state.stage_reason_id = null;
  },
);
watch(
  () => state.stage_id,
  () => {
    state.stage_reason_id = null;
  },
);

async function onCreate(event: FormSubmitEvent<Schema>) {
  creating.value = true;
  const payload: Record<string, unknown> = {
    title: event.data.title,
    customer_id: event.data.customer_id,
    pipeline_id: event.data.pipeline_id,
    stage_id: event.data.stage_id,
    stage_reason_id: event.data.stage_reason_id || null,
    value: event.data.value ?? null,
    expected_close_date: event.data.expected_close_date || null,
  };
  if (canAssign.value) payload.assigned_to = event.data.assigned_to || null;

  const { error } = await supabase.from("deals").insert(payload);
  creating.value = false;

  if (error) {
    toast.add({ title: t("crm.deals.createDealFailed"), description: error.message, color: "error" });
    return;
  }

  toast.add({ title: t("crm.deals.dealCreated"), color: "success" });
  createOpen.value = false;
  Object.assign(state, {
    title: "",
    customer_id: undefined,
    assigned_to: null,
    value: undefined,
    expected_close_date: "",
  });
  refresh();
}

function openDeal(deal: Deal) {
  navigateTo(`/crm/deals/${deal.id}`);
}
</script>

<template>
  <UDashboardPanel>
    <template #header>
      <UDashboardNavbar :title="t('crm.deals.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton
            v-if="hasPermission('crm_deals', 'create')"
            icon="i-lucide-plus"
            :label="t('crm.deals.newDeal')"
            @click="openCreate"
          />
        </template>
      </UDashboardNavbar>

      <UDashboardToolbar>
        <template #left>
          <UTabs v-model="activePipelineId" :items="pipelineTabs" value-key="value" />
        </template>
      </UDashboardToolbar>
    </template>

    <template #body>
      <div v-if="status === 'pending' || status === 'idle'" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>

      <div v-else class="flex gap-4 overflow-x-auto pb-4">
        <div
          v-for="stage in activeStages"
          :key="stage.id"
          class="w-64 shrink-0 rounded-lg border border-default"
          :class="stage.is_closed ? 'bg-elevated' : 'bg-default'"
        >
          <div class="flex items-center justify-between border-b border-default p-3">
            <span class="font-medium text-highlighted">{{ stage.name }}</span>
            <UBadge :label="String(dealsForStage(stage.id).length)" color="neutral" variant="subtle" />
          </div>
          <div class="space-y-2 p-2">
            <div
              v-for="deal in dealsForStage(stage.id)"
              :key="deal.id"
              class="cursor-pointer rounded-md border border-default bg-default p-2 text-sm hover:border-primary"
              @click="openDeal(deal)"
            >
              <div class="flex items-start justify-between gap-2">
                <div class="font-medium text-highlighted">{{ deal.title }}</div>
                <UAvatar
                  v-if="deal.assigned_to"
                  :text="assigneeInitial(deal.assigned_to)"
                  size="2xs"
                />
              </div>
              <div class="text-muted">{{ customerName(deal.customer_id) }}</div>
              <div v-if="deal.value" class="text-muted">{{ deal.value }}</div>
            </div>
            <div v-if="dealsForStage(stage.id).length === 0" class="py-4 text-center text-xs text-muted">
              {{ t("crm.deals.noDealsInStage") }}
            </div>
          </div>
        </div>
      </div>
    </template>
  </UDashboardPanel>

  <UModal v-model:open="createOpen" :title="t('crm.deals.newDeal')">
    <template #body>
      <UForm :schema="schema" :state="state" class="space-y-4" @submit="onCreate">
        <UFormField name="title" :label="t('crm.deals.dealTitle')">
          <UInput v-model="state.title" class="w-full" />
        </UFormField>
        <UFormField name="customer_id" :label="t('crm.deals.customer')">
          <USelect v-model="state.customer_id" :items="customerOptions" value-key="value" class="w-full" />
        </UFormField>
        <UFormField name="pipeline_id" :label="t('crm.deals.pipeline')">
          <USelect v-model="state.pipeline_id" :items="pipelineTabs" value-key="value" class="w-full" />
        </UFormField>
        <UFormField name="stage_id" :label="t('crm.deals.stage')">
          <USelect
            v-model="state.stage_id"
            :items="createPipelineStages.map((s) => ({ label: s.name, value: s.id }))"
            value-key="value"
            class="w-full"
          />
        </UFormField>
        <UFormField v-if="createStage?.reason_category" name="stage_reason_id" :label="t('crm.deals.reason')">
          <USelect v-model="state.stage_reason_id" :items="createReasonOptions" value-key="value" class="w-full" />
        </UFormField>
        <UFormField v-if="canAssign" name="assigned_to" :label="t('crm.deals.assignedTo')">
          <USelect v-model="state.assigned_to" :items="assigneeOptions" value-key="value" class="w-full" />
        </UFormField>
        <UFormField name="value" :label="t('crm.deals.value')">
          <UInputNumber v-model="state.value" class="w-full" />
        </UFormField>
        <UFormField name="expected_close_date" :label="t('crm.deals.expectedCloseDate')">
          <UInput v-model="state.expected_close_date" type="date" class="w-full" />
        </UFormField>
        <UButton type="submit" :label="t('crm.deals.createDeal')" :loading="creating" block />
      </UForm>
    </template>
  </UModal>
</template>
