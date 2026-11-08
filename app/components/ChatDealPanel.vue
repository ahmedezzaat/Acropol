<script setup lang="ts">
// Next to a WhatsApp chat: who the person is, the deals they already have, and a form to create a deal from
// the chat. A person who is not a lead yet becomes one (source WhatsApp) together with the deal.
interface Chat {
  id: string;
  wa_id: string;
  display_name: string | null;
  lead_id: string | null;
  customer_id: string | null;
  collected: Record<string, string>;
}
const props = defineProps<{ chat: Chat }>();
const emit = defineEmits<{ changed: [] }>();

const supabase = useSupabaseClient();
const me = useSupabaseUser();
const toast = useToast();
const { t } = useI18n();
const { hasPermission } = usePermissions();
const canAssign = computed(() => hasPermission("crm_deals", "assign"));

const hidden = computed(() => props.chat.wa_id.startsWith("lid-"));

// ---- What the form needs
// (not awaited: the panel opens at once and the lists fill in when they arrive)
const { data: setup } = useAsyncData("chat-deal-setup", async () => {
  const [pipelines, stages, categories, people] = await Promise.all([
    supabase.from("pipelines").select("id, name, sort_order").order("sort_order"),
    supabase.from("pipeline_stages").select("id, pipeline_id, name, sort_order, is_closed").order("sort_order"),
    supabase.from("product_categories").select("id, name").order("sort_order"),
    supabase.from("profiles").select("id, full_name, email").eq("is_active", true).order("full_name"),
  ]);
  return {
    pipelines: (pipelines.data ?? []) as { id: string; name: string }[],
    stages: (stages.data ?? []) as { id: string; pipeline_id: string; name: string; is_closed: boolean }[],
    categories: (categories.data ?? []) as { id: string; name: string }[],
    people: (people.data ?? []) as { id: string; full_name: string | null; email: string }[],
  };
});

// ---- The deals this person already has
interface DealRow { id: string; title: string; stage_id: string }
const deals = ref<DealRow[]>([]);
async function loadDeals() {
  const ors = [props.chat.lead_id && `lead_id.eq.${props.chat.lead_id}`, props.chat.customer_id && `customer_id.eq.${props.chat.customer_id}`].filter(Boolean);
  if (!ors.length) {
    deals.value = [];
    return;
  }
  const { data } = await supabase.from("deals").select("id, title, stage_id").or(ors.join(",")).order("created_at", { ascending: false });
  deals.value = (data ?? []) as DealRow[];
}
const stageName = (id: string) => setup.value?.stages.find((s) => s.id === id)?.name ?? "";
// a deal still being worked (its stage is not a closed one: won, lost, archived)
const isOpen = (d: DealRow) => !setup.value?.stages.find((s) => s.id === d.stage_id)?.is_closed;
const openDeals = computed(() => deals.value.filter(isOpen));
const closedDeals = computed(() => deals.value.filter((d) => !isOpen(d)));
// a person who already has a deal in progress is sent to it; a new deal is made only on purpose
const wantNew = ref(false);
const formVisible = computed(() => !openDeals.value.length || wantNew.value);

// ---- The form
const categoryIds = ref<string[]>([]);
const pipelineId = ref<string | null>(null);
const stageId = ref<string | null>(null);
const assignee = ref<string | null>(null);
const name = ref("");
const phone = ref("");
const areaId = ref<string | null>(null);
const creating = ref(false);
const createdId = ref<string | null>(null);

function reset() {
  categoryIds.value = [];
  pipelineId.value = setup.value?.pipelines[0]?.id ?? null;
  assignee.value = (me.value?.sub as string | undefined) ?? null;
  name.value = props.chat.collected?.name || props.chat.display_name || "";
  phone.value = "";
  areaId.value = null;
  createdId.value = null;
  wantNew.value = false;
}
watch(() => props.chat.id, () => {
  reset();
  loadDeals();
}, { immediate: true });
// the lists arrived after the panel opened: pick the first pipeline
watch(setup, () => {
  if (!pipelineId.value) pipelineId.value = setup.value?.pipelines[0]?.id ?? null;
  if (!assignee.value) assignee.value = (me.value?.sub as string | undefined) ?? null;
});
// the first stage of the chosen pipeline
watch(pipelineId, (id) => (stageId.value = setup.value?.stages.find((s) => s.pipeline_id === id)?.id ?? null), { immediate: true });

const pipelineItems = computed(() => (setup.value?.pipelines ?? []).map((p) => ({ label: p.name, value: p.id })));
const stageItems = computed(() => (setup.value?.stages ?? []).filter((s) => s.pipeline_id === pipelineId.value).map((s) => ({ label: s.name, value: s.id })));
const personItems = computed(() => (setup.value?.people ?? []).map((p) => ({ label: p.full_name || p.email, value: p.id as string | null })));

const needsLead = computed(() => !props.chat.lead_id && !props.chat.customer_id);
const valid = computed(
  () => categoryIds.value.length > 0 && !!pipelineId.value && !!stageId.value && (!needsLead.value || (!!name.value.trim() && (!hidden.value || phone.value.replace(/\D/g, "").length >= 7))),
);

function toggleCategory(id: string, on: boolean) {
  categoryIds.value = on ? [...new Set([...categoryIds.value, id])] : categoryIds.value.filter((x) => x !== id);
}

async function create() {
  if (!valid.value) return;
  creating.value = true;
  let leadId = props.chat.lead_id;
  // a person who is not a lead yet becomes one, with the deal
  if (needsLead.value) {
    const leadPayload: Record<string, unknown> = {
      name: name.value.trim(),
      phone: hidden.value ? phone.value.trim() : `+${props.chat.wa_id}`,
      source: "whatsapp",
      lead_type: "individual",
      notes: ["محادثة واتساب", ...Object.entries(props.chat.collected ?? {}).filter(([k, v]) => v && k !== "name").map(([k, v]) => `${t(`chats.fields.${k}`)}: ${v}`)].join("\n"),
      area_id: areaId.value,
    };
    if (canAssign.value) leadPayload.assigned_to = assignee.value;
    const { data: lead, error } = await supabase.from("leads").insert(leadPayload).select("id").single();
    if (error || !lead) {
      creating.value = false;
      toast.add({ title: t("chats.deal.leadFailed"), description: error?.message, color: "error" });
      return;
    }
    leadId = lead.id;
    // the chat now belongs to that lead
    await supabase.from("whatsapp_conversations").update({ lead_id: lead.id, status: "qualified", ai_paused: true }).eq("id", props.chat.id);
  }

  const title = (setup.value?.categories ?? []).filter((c) => categoryIds.value.includes(c.id)).map((c) => c.name).join("، ");
  const payload: Record<string, unknown> = { title, lead_id: leadId, customer_id: props.chat.customer_id, pipeline_id: pipelineId.value, stage_id: stageId.value };
  if (canAssign.value) payload.assigned_to = assignee.value;
  const { data: deal, error } = await supabase.from("deals").insert(payload).select("id").single();
  creating.value = false;
  if (error || !deal) {
    toast.add({ title: t("chats.deal.failed"), description: error?.message, color: "error" });
    emit("changed");
    return;
  }
  createdId.value = deal.id;
  toast.add({ title: t("chats.deal.created"), color: "success" });
  await loadDeals();
  emit("changed");
}
</script>

<template>
  <aside class="kords-card space-y-4 p-4 text-sm">
    <h3 class="flex items-center gap-2 font-semibold text-highlighted"><UIcon name="i-lucide-handshake" class="size-4 text-primary" />{{ t("chats.deal.title") }}</h3>

    <!-- Who this is -->
    <div class="space-y-1 rounded-[10px] bg-muted p-3 text-xs">
      <p v-if="chat.lead_id" class="flex items-center justify-between gap-2"><span class="text-muted">{{ t("chats.deal.isLead") }}</span><UButton :to="`/crm/leads?id=${chat.lead_id}`" size="xs" color="neutral" variant="link" :label="t('chats.openLead')" /></p>
      <p v-if="chat.customer_id" class="flex items-center justify-between gap-2"><span class="text-muted">{{ t("chats.deal.isCustomer") }}</span><UButton :to="`/cs/customers/${chat.customer_id}`" size="xs" color="neutral" variant="link" :label="t('chats.deal.openCustomer')" /></p>
      <p v-if="needsLead" class="text-muted">{{ t("chats.deal.newLeadNote") }}</p>
    </div>

    <!-- A deal already in progress: shown first, instead of making a new one -->
    <div v-if="openDeals.length" class="space-y-2 rounded-[10px] border border-primary/40 bg-primary/5 p-3">
      <p class="flex items-center gap-1.5 text-xs font-semibold text-primary"><UIcon name="i-lucide-info" class="size-3.5" />{{ t("chats.deal.hasOpen") }}</p>
      <NuxtLink v-for="d in openDeals" :key="d.id" :to="`/crm/deals/${d.id}`" class="flex items-center justify-between gap-2 rounded-[8px] border border-default bg-default px-2.5 py-2 text-xs hover:border-primary">
        <span class="truncate font-medium text-highlighted">{{ d.title || "—" }}</span>
        <span class="flex shrink-0 items-center gap-1.5"><KBadge :label="stageName(d.stage_id)" tone="primary" /><UIcon name="i-lucide-external-link" class="size-3.5 text-muted" /></span>
      </NuxtLink>
    </div>
    <!-- Their finished deals -->
    <div v-if="closedDeals.length" class="space-y-1.5">
      <p class="text-xs font-semibold text-toned">{{ t("chats.deal.closed") }}</p>
      <NuxtLink v-for="d in closedDeals" :key="d.id" :to="`/crm/deals/${d.id}`" class="flex items-center justify-between gap-2 rounded-[8px] border border-default px-2.5 py-1.5 text-xs hover:border-primary">
        <span class="truncate text-toned">{{ d.title || "—" }}</span>
        <KBadge :label="stageName(d.stage_id)" tone="neutral" class="shrink-0" />
      </NuxtLink>
    </div>

    <!-- The form -->
    <div v-if="createdId" class="space-y-2 rounded-[10px] bg-success/10 p-3 text-xs text-success">
      <p class="font-medium">{{ t("chats.deal.created") }}</p>
      <div class="flex gap-2">
        <UButton :to="`/crm/deals/${createdId}`" size="xs" icon="i-lucide-external-link" :label="t('chats.deal.open')" />
        <UButton size="xs" color="neutral" variant="outline" :label="t('chats.deal.another')" @click="reset" />
      </div>
    </div>
    <UButton v-else-if="!formVisible" color="neutral" variant="outline" icon="i-lucide-plus" :label="t('chats.deal.newAnyway')" block @click="wantNew = true" />
    <div v-else class="space-y-3">
      <p class="text-xs font-semibold text-toned">{{ t("chats.deal.new") }}</p>
      <template v-if="needsLead">
        <UFormField :label="t('common.name')" required><UInput v-model="name" size="sm" class="w-full" /></UFormField>
        <UFormField v-if="hidden" :label="t('common.phone')" required :help="t('chats.hiddenNote')"><PhoneInput v-model="phone" /></UFormField>
        <UFormField :label="t('cs.customers.area')"><AreaSelect v-model="areaId" /></UFormField>
      </template>
      <UFormField :label="t('chats.deal.categories')" required>
        <div class="max-h-36 space-y-1.5 overflow-y-auto rounded-[10px] border border-default p-2">
          <UCheckbox v-for="c in setup?.categories ?? []" :key="c.id" :model-value="categoryIds.includes(c.id)" :label="c.name" @update:model-value="(v: boolean | 'indeterminate') => toggleCategory(c.id, v === true)" />
        </div>
      </UFormField>
      <UFormField :label="t('crm.deals.pipeline')"><USelect v-model="pipelineId" :items="pipelineItems" value-key="value" size="sm" class="w-full" /></UFormField>
      <UFormField :label="t('crm.deals.stage')"><USelect v-model="stageId" :items="stageItems" value-key="value" size="sm" class="w-full" /></UFormField>
      <UFormField v-if="canAssign" :label="t('crm.deals.assignedTo')"><USelect v-model="assignee" :items="personItems" value-key="value" size="sm" class="w-full" /></UFormField>
      <UButton icon="i-lucide-plus" :label="t('chats.deal.create')" :loading="creating" :disabled="!valid" block @click="create" />
    </div>
  </aside>
</template>
