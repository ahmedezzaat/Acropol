<script setup lang="ts">
import * as z from "zod";
import type { FormSubmitEvent } from "@nuxt/ui";

definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "crm_leads" },
});

useHead({ htmlAttrs: { class: "carbon" } });

const supabase = useSupabaseClient();
const toast = useToast();
const { hasPermission, hasAnyModulePermission } = usePermissions();
const { t } = useI18n();

interface Lead {
  id: string;
  name: string;
  phone: string | null;
  phone2: string | null;
  email: string | null;
  status: string;
  assigned_to: string | null;
  created_at: string;
  lead_type: "individual" | "company";
  company_name: string | null;
  source: string | null;
  notes: string | null;
  customer_id: string | null;
}

interface Profile {
  id: string;
  full_name: string | null;
  email: string;
}

const search = ref("");
const statusFilter = ref("all");
// Quick filter above the list: everyone, individuals, or companies.
const typeFilter = ref<"all" | "individual" | "company">("all");
// Sentinel for "Unassigned" — null means "no assignee filter".
const UNASSIGNED = "__unassigned__";
const assigneeFilter = ref<string | null>(null);

const { data: leads, refresh, status: leadsStatus } = await useAsyncData<Lead[]>(
  "crm-leads",
  async () => {
    const { data, error } = await supabase
      .from("leads")
      .select("id, name, phone, phone2, email, status, assigned_to, created_at, lead_type, company_name, source, notes, customer_id")
      .order("created_at", { ascending: false });
    if (error) throw error;
    return data ?? [];
  },
);

// Only checked when the viewer can see deals at all — otherwise crm_deals
// RLS would return zero rows and every lead would falsely show as
// deal-less.
const canSeeDeals = computed(() => hasAnyModulePermission("crm_deals"));
const { data: leadIdsWithDeals, refresh: refreshDealFlags } = await useAsyncData<string[]>("crm-leads-deal-flags", async () => {
  if (!canSeeDeals.value) return [];
  const { data, error } = await supabase.from("deals").select("lead_id").not("lead_id", "is", null);
  if (error) throw error;
  return (data ?? []).map((d) => d.lead_id as string);
});
const leadIdsWithDealsSet = computed(() => new Set(leadIdsWithDeals.value ?? []));

const { data: profiles } = await useAsyncData<Profile[]>("crm-leads-profiles", async () => {
  const { data, error } = await supabase.from("profiles").select("id, full_name, email").eq("is_active", true);
  if (error) throw error;
  return data ?? [];
});

function profileLabel(id: string | null) {
  if (!id) return t("common.unassigned");
  const p = profiles.value?.find((p) => p.id === id);
  return p?.full_name || p?.email || "?";
}

const assigneeFilterOptions = computed(() => [
  { label: t("common.all"), value: null },
  { label: t("common.unassigned"), value: UNASSIGNED },
  ...(profiles.value ?? []).map((p) => ({ label: p.full_name || p.email, value: p.id })),
]);

const statusKeys = ["new", "contacted", "qualified", "converted", "lost"] as const;
const statusOptions = computed(() => [
  { label: t("common.all"), value: "all" },
  ...statusKeys.map((s) => ({ label: t(`crm.leads.status.${s}`), value: s })),
]);
const statusColors: Record<string, "neutral" | "info" | "warning" | "success" | "error"> = {
  new: "info",
  contacted: "warning",
  qualified: "warning",
  converted: "success",
  lost: "error",
};

const filteredLeads = computed(() => {
  return (leads.value ?? []).filter((lead) => {
    const matchesSearch =
      !search.value ||
      lead.name.toLowerCase().includes(search.value.toLowerCase()) ||
      (lead.email ?? "").toLowerCase().includes(search.value.toLowerCase()) ||
      phoneMatches(lead.phone, search.value) ||
      phoneMatches(lead.phone2, search.value);
    const matchesStatus = statusFilter.value === "all" || lead.status === statusFilter.value;
    const matchesAssignee =
      assigneeFilter.value === null ||
      (assigneeFilter.value === UNASSIGNED ? lead.assigned_to === null : lead.assigned_to === assigneeFilter.value);
    const matchesType = typeFilter.value === "all" || lead.lead_type === typeFilter.value;
    return matchesSearch && matchesStatus && matchesAssignee && matchesType;
  });
});

const typeCounts = computed(() => {
  const all = leads.value ?? [];
  return {
    all: all.length,
    individual: all.filter((l) => l.lead_type === "individual").length,
    company: all.filter((l) => l.lead_type === "company").length,
  };
});
const typeTabs = computed(() =>
  (["all", "individual", "company"] as const).map((k) => ({
    value: k,
    label: `${k === "all" ? t("common.all") : t(`crm.leads.type.${k}`)} (${typeCounts.value[k]})`,
  })),
);

// --- Create lead ---
const createOpen = ref(false);
const creating = ref(false);
const canAssign = computed(() => hasPermission("crm_leads", "assign"));

const leadTypeOptions = computed(() => [
  { label: t("crm.leads.type.individual"), value: "individual" },
  { label: t("crm.leads.type.company"), value: "company" },
]);

const sourceKeys = ["external_client", "facebook", "instagram", "meta", "google", "website", "event", "referral", "whatsapp", "api"] as const;
const sourceOptions = computed(() =>
  sourceKeys.map((s) => ({ label: t(`crm.leads.sourceValues.${s}`), value: s })),
);

const assigneeOptions = computed(() => [
  { label: t("common.unassigned"), value: null },
  ...(profiles.value ?? []).map((p) => ({ label: p.full_name || p.email, value: p.id })),
]);

const schema = computed(() =>
  z
    .object({
      lead_type: z.enum(["individual", "company"]),
      company_name: z.string().optional(),
      name: z.string().min(1, t("validation.required")),
      phone: z.string().min(1, t("validation.required")),
      phone2: z.string().optional(),
      email: z.string().optional(),
      source: z.enum(sourceKeys, t("validation.required")),
      notes: z.string().optional(),
      assigned_to: z.uuid().nullable().optional(),
    })
    .superRefine((data, ctx) => {
      if (data.lead_type === "company" && !data.company_name?.trim()) {
        ctx.addIssue({ message: t("validation.required"), path: ["company_name"] });
      }
    }),
);
type Schema = {
  lead_type: "individual" | "company";
  company_name?: string;
  name: string;
  phone: string;
  phone2?: string;
  email?: string;
  source: (typeof sourceKeys)[number];
  notes?: string;
  assigned_to?: string | null;
};
const state = reactive<Partial<Schema>>({
  lead_type: "individual",
  company_name: "",
  name: "",
  phone: "",
  phone2: "",
  email: "",
  source: undefined,
  notes: "",
  assigned_to: null,
});

function resetCreateState() {
  state.lead_type = "individual";
  state.company_name = "";
  state.name = "";
  state.phone = "";
  state.phone2 = "";
  state.email = "";
  state.source = undefined;
  state.notes = "";
  state.assigned_to = null;
}

// Catch the common case of a rep (re-)entering a lead someone already has,
// by matching on phone regardless of formatting (local "0...", "+20...",
// with/without spaces). Only checks leads this user can already see (same
// own/team/view_all scoping as everywhere else), not a global lookup.
const duplicateLead = computed(() => {
  const candidates = [phoneDigits(state.phone), phoneDigits(state.phone2)].filter((d): d is string => !!d);
  if (!candidates.length) return null;
  return (
    leads.value?.find((l) => {
      const existing = [phoneDigits(l.phone), phoneDigits(l.phone2)].filter((d): d is string => !!d);
      return existing.some((e) => candidates.includes(e));
    }) ?? null
  );
});

async function onCreate(event: FormSubmitEvent<Schema>) {
  if (duplicateLead.value) return;
  creating.value = true;
  const payload: Record<string, unknown> = {
    lead_type: event.data.lead_type,
    company_name: event.data.lead_type === "company" ? event.data.company_name || null : null,
    name: event.data.name,
    phone: event.data.phone.trim(),
    phone2: trimOrNull(event.data.phone2),
    email: event.data.email || null,
    source: event.data.source,
    notes: event.data.notes || null,
  };
  if (canAssign.value) payload.assigned_to = event.data.assigned_to || null;

  const { error } = await supabase.from("leads").insert(payload);
  creating.value = false;

  if (error) {
    toast.add({ title: t("crm.leads.createLeadFailed"), description: error.message, color: "error" });
    return;
  }

  toast.add({ title: t("crm.leads.leadCreated"), color: "success" });
  createOpen.value = false;
  resetCreateState();
  refresh();
}

// --- Master / detail ---------------------------------------------------
// The list sits on one side and the selected lead's details on the other (on
// a phone they take turns full-screen). The selection lives in ?id= so it
// survives a refresh and notifications can open straight to a lead.
const route = useRoute();
const router = useRouter();
const selectedId = ref<string | null>(typeof route.query.id === "string" ? route.query.id : null);

function selectLead(id: string | null) {
  selectedId.value = id;
  const query = { ...route.query };
  if (id) query.id = id;
  else delete query.id;
  router.replace({ query });
}
watch(
  () => route.query.id,
  (id) => {
    selectedId.value = typeof id === "string" ? id : null;
  },
);

const selectedLead = computed(() => leads.value?.find((l) => l.id === selectedId.value) ?? null);

// On a wide screen there is room for both panes, so open the first lead
// instead of an empty details pane.
onMounted(() => {
  if (!selectedId.value && window.innerWidth >= 1024 && filteredLeads.value[0]) {
    selectedId.value = filteredLeads.value[0].id;
  }
});

function primaryName(lead: Lead) {
  return lead.lead_type === "company" && lead.company_name ? lead.company_name : lead.name;
}
function secondaryName(lead: Lead) {
  return lead.lead_type === "company" && lead.company_name ? lead.name : null;
}
function initial(lead: Lead) {
  return primaryName(lead).trim().charAt(0).toUpperCase() || "?";
}
function formatDate(value: string) {
  return new Date(value).toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" });
}
function ago(value: string) {
  const rtf = new Intl.RelativeTimeFormat(undefined, { numeric: "auto" });
  const days = Math.round((new Date(value).getTime() - Date.now()) / 86_400_000);
  if (Math.abs(days) >= 30) return rtf.format(Math.round(days / 30), "month");
  if (Math.abs(days) >= 1) return rtf.format(days, "day");
  const hours = Math.round((new Date(value).getTime() - Date.now()) / 3_600_000);
  return rtf.format(hours, "hour");
}

// --- The selected lead's deals ---
interface PipelineStageInfo {
  id: string;
  name: string;
  pipeline_id: string;
  system_key: string | null;
}
interface LeadDeal {
  id: string;
  title: string;
  value: number | null;
  pipeline_id: string;
  stage_id: string;
  assigned_to: string | null;
  created_at: string;
}

const { data: stageInfo } = await useAsyncData<PipelineStageInfo[]>("crm-leads-stages", async () => {
  if (!canSeeDeals.value) return [];
  const { data, error } = await supabase.from("pipeline_stages").select("id, name, pipeline_id, system_key");
  if (error) throw error;
  return data ?? [];
});
const { data: pipelineInfo } = await useAsyncData<{ id: string; name: string }[]>("crm-leads-pipelines", async () => {
  if (!canSeeDeals.value) return [];
  const { data, error } = await supabase.from("pipelines").select("id, name");
  if (error) throw error;
  return data ?? [];
});

const { data: leadDeals, refresh: refreshLeadDeals, status: leadDealsStatus } = await useAsyncData<LeadDeal[]>(
  "crm-lead-deals",
  async () => {
    if (!canSeeDeals.value || !selectedId.value) return [];
    const { data, error } = await supabase
      .from("deals")
      .select("id, title, value, pipeline_id, stage_id, assigned_to, created_at")
      .eq("lead_id", selectedId.value)
      .order("created_at", { ascending: false });
    if (error) throw error;
    return data ?? [];
  },
  { watch: [selectedId] },
);

function stageOf(id: string) {
  return stageInfo.value?.find((s) => s.id === id);
}
function stageColor(id: string): "success" | "error" | "neutral" | "primary" {
  const key = stageOf(id)?.system_key;
  if (key === "won") return "success";
  if (key === "competitor") return "error";
  if (key === "archive") return "neutral";
  return "primary";
}
function pipelineName(id: string) {
  return pipelineInfo.value?.find((p) => p.id === id)?.name ?? "";
}
function formatMoney(value: number | null) {
  return value ? `${value.toLocaleString("en-US")} ${t("common.currency")}` : null;
}

const dealModalOpen = ref(false);
function openDealModal() {
  dealModalOpen.value = true;
}
async function onDealCreated() {
  await Promise.all([refreshLeadDeals(), refreshDealFlags()]);
}
function openDeal(id: string) {
  navigateTo(`/crm/deals/${id}`);
}
function backToList() {
  selectLead(null);
}
</script>

<template>
  <!-- One screen tall with its body padding removed, so the list and the
  details each scroll on their own instead of the whole page. -->
  <UDashboardPanel :ui="{ root: 'h-svh', body: 'gap-0 overflow-hidden p-0 sm:p-0' }">
    <template #header>
      <UDashboardNavbar>
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #title>
          <span class="flex items-center gap-2">
            {{ t("crm.leads.title") }}
            <UBadge :label="String(leads?.length ?? 0)" color="neutral" variant="subtle" class="cds-tag" />
          </span>
        </template>
        <template #right>
          <UButton
            v-if="hasPermission('crm_leads', 'create')"
            icon="i-lucide-plus"
            :label="t('crm.leads.newLead')"
            @click="createOpen = true"
          />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <div class="flex min-h-0 flex-1">
        <!-- ===== Contact list ===== -->
        <aside
          class="min-h-0 w-full flex-col border-default lg:w-96 lg:shrink-0 lg:border-e"
          :class="selectedLead ? 'hidden lg:flex' : 'flex'"
        >
          <div class="shrink-0 space-y-3 border-b border-default p-3">
            <UInput v-model="search" icon="i-lucide-search" :placeholder="t('crm.leads.searchPlaceholder')" class="w-full" />
            <UTabs v-model="typeFilter" :items="typeTabs" value-key="value" variant="pill" size="sm" :content="false" class="w-full" />
            <div class="grid grid-cols-2 gap-2">
              <USelectMenu
                v-model="assigneeFilter"
                :items="assigneeFilterOptions"
                value-key="value"
                icon="i-lucide-user"
                :placeholder="t('crm.leads.assignedTo')"
                searchable
                class="w-full"
              />
              <USelect v-model="statusFilter" :items="statusOptions" value-key="value" class="w-full" />
            </div>
          </div>

          <div v-if="leadsStatus === 'pending' || leadsStatus === 'idle'" class="flex justify-center py-10">
            <UIcon name="i-lucide-loader-2" class="size-5 animate-spin text-muted" />
          </div>
          <p v-else-if="!filteredLeads.length" class="p-8 text-center text-sm text-muted">{{ t("crm.leads.noResults") }}</p>

          <ul v-else class="min-h-0 flex-1 divide-y divide-default overflow-y-auto overscroll-contain">
            <li v-for="lead in filteredLeads" :key="lead.id">
              <button
                type="button"
                class="flex w-full items-center gap-3 px-3 py-3 text-start transition-colors hover:bg-elevated"
                :class="lead.id === selectedId && 'bg-primary/10'"
                @click="selectLead(lead.id)"
              >
                <UAvatar
                  :text="lead.lead_type === 'company' ? undefined : initial(lead)"
                  :icon="lead.lead_type === 'company' ? 'i-lucide-building-2' : undefined"
                  size="md"
                />
                <span class="min-w-0 flex-1">
                  <span class="flex items-center gap-2">
                    <span class="truncate font-medium text-highlighted">{{ primaryName(lead) }}</span>
                    <UBadge
                      v-if="canSeeDeals && !leadIdsWithDealsSet.has(lead.id)"
                      :label="t('crm.leads.noDeal')"
                      color="warning"
                      variant="subtle"
                      size="sm"
                      class="cds-tag shrink-0"
                    />
                  </span>
                  <span v-if="secondaryName(lead)" class="block truncate text-xs text-toned">{{ secondaryName(lead) }}</span>
                  <span class="mt-0.5 flex items-center gap-1.5 text-xs text-muted">
                    <bdi v-if="lead.phone" dir="ltr">{{ lead.phone }}</bdi>
                    <span v-if="lead.phone">·</span>
                    <span>{{ ago(lead.created_at) }}</span>
                  </span>
                </span>
                <span class="flex shrink-0 items-center gap-2">
                  <UBadge
                    :label="t(`crm.leads.status.${lead.status}`)"
                    :color="statusColors[lead.status]"
                    variant="subtle"
                    size="sm"
                    class="cds-tag hidden sm:inline-flex"
                  />
                  <a
                    v-if="toWhatsAppLink(lead.phone)"
                    :href="toWhatsAppLink(lead.phone)!"
                    target="_blank"
                    rel="noopener noreferrer"
                    :aria-label="t('crm.deals.chatOnWhatsApp')"
                    class="flex size-8 items-center justify-center text-[#25D366] hover:opacity-80"
                    @click.stop
                  >
                    <UIcon name="i-simple-icons-whatsapp" class="size-5" />
                  </a>
                </span>
              </button>
            </li>
          </ul>
        </aside>

        <!-- ===== Details ===== -->
        <section
          class="min-h-0 min-w-0 flex-1 flex-col overflow-y-auto"
          :class="selectedLead ? 'flex' : 'hidden lg:flex'"
        >
          <div v-if="!selectedLead" class="flex flex-1 flex-col items-center justify-center gap-2 p-8 text-center text-muted">
            <UIcon name="i-lucide-user-round-search" class="size-10" />
            <p class="text-sm">{{ t("crm.leads.selectLead") }}</p>
          </div>

          <template v-else>
            <div class="space-y-6 p-4 sm:p-6">
              <!-- Header -->
              <div class="flex flex-wrap items-start gap-3">
                <UButton
                  icon="i-lucide-arrow-right"
                  color="neutral"
                  variant="ghost"
                  class="lg:hidden rtl:rotate-0 ltr:rotate-180"
                  :aria-label="t('crm.leads.backToList')"
                  @click="backToList"
                />
                <UAvatar
                  :text="selectedLead.lead_type === 'company' ? undefined : initial(selectedLead)"
                  :icon="selectedLead.lead_type === 'company' ? 'i-lucide-building-2' : undefined"
                  size="xl"
                />
                <div class="min-w-0 flex-1">
                  <h2 class="truncate text-xl font-semibold text-highlighted">{{ primaryName(selectedLead) }}</h2>
                  <p v-if="secondaryName(selectedLead)" class="truncate text-sm text-toned">{{ secondaryName(selectedLead) }}</p>
                  <div class="mt-1.5 flex flex-wrap items-center gap-1.5">
                    <UBadge
                      :label="t(`crm.leads.type.${selectedLead.lead_type}`)"
                      color="neutral"
                      variant="subtle"
                      size="sm"
                      class="cds-tag"
                    />
                    <UBadge
                      :label="t(`crm.leads.status.${selectedLead.status}`)"
                      :color="statusColors[selectedLead.status]"
                      variant="subtle"
                      size="sm"
                      class="cds-tag"
                    />
                    <UBadge
                      v-if="selectedLead.customer_id"
                      :label="t('crm.leads.converted')"
                      color="success"
                      variant="subtle"
                      size="sm"
                      class="cds-tag"
                    />
                  </div>
                </div>
                <div class="flex shrink-0 items-center gap-1">
                  <UButton
                    v-if="selectedLead.phone"
                    :to="`tel:${selectedLead.phone}`"
                    icon="i-lucide-phone"
                    color="neutral"
                    variant="outline"
                    :aria-label="t('crm.deals.callContact')"
                  />
                  <UButton
                    v-if="toWhatsAppLink(selectedLead.phone)"
                    :to="toWhatsAppLink(selectedLead.phone)!"
                    target="_blank"
                    rel="noopener noreferrer"
                    icon="i-simple-icons-whatsapp"
                    color="neutral"
                    variant="outline"
                    :aria-label="t('crm.deals.chatOnWhatsApp')"
                  />
                  <UButton
                    :to="`/crm/leads/${selectedLead.id}`"
                    icon="i-lucide-pencil"
                    color="neutral"
                    variant="outline"
                    :label="t('crm.leads.openProfile')"
                  />
                </div>
              </div>

              <!-- Facts -->
              <dl class="grid gap-x-6 gap-y-4 text-sm sm:grid-cols-2 xl:grid-cols-3">
                <div>
                  <dt class="text-xs text-muted">{{ t("common.phone") }}</dt>
                  <dd class="font-medium text-highlighted"><bdi dir="ltr">{{ selectedLead.phone || "—" }}</bdi></dd>
                </div>
                <div v-if="selectedLead.phone2">
                  <dt class="text-xs text-muted">{{ t("crm.leads.phone2") }}</dt>
                  <dd class="font-medium text-highlighted"><bdi dir="ltr">{{ selectedLead.phone2 }}</bdi></dd>
                </div>
                <div>
                  <dt class="text-xs text-muted">{{ t("common.email") }}</dt>
                  <dd class="font-medium text-highlighted">{{ selectedLead.email || "—" }}</dd>
                </div>
                <div>
                  <dt class="text-xs text-muted">{{ t("crm.leads.source") }}</dt>
                  <dd class="font-medium text-highlighted">
                    {{ selectedLead.source ? t(`crm.leads.sourceValues.${selectedLead.source}`) : "—" }}
                  </dd>
                </div>
                <div>
                  <dt class="text-xs text-muted">{{ t("crm.leads.assignedTo") }}</dt>
                  <dd class="font-medium text-highlighted">{{ profileLabel(selectedLead.assigned_to) }}</dd>
                </div>
                <div>
                  <dt class="text-xs text-muted">{{ t("crm.leads.createdAt") }}</dt>
                  <dd class="font-medium text-highlighted">{{ formatDate(selectedLead.created_at) }}</dd>
                </div>
              </dl>

              <div>
                <h3 class="mb-1 text-xs font-semibold uppercase tracking-wide text-muted">{{ t("crm.leads.notes") }}</h3>
                <p class="whitespace-pre-line bg-muted p-3 text-sm" :class="selectedLead.notes ? 'text-toned' : 'text-muted'">
                  {{ selectedLead.notes || t("crm.leads.noNotes") }}
                </p>
              </div>

              <!-- Deals -->
              <div v-if="canSeeDeals" class="border-t border-default pt-5">
                <div class="mb-3 flex items-center justify-between gap-2">
                  <h3 class="flex items-center gap-2 font-semibold text-highlighted">
                    {{ t("crm.leads.dealsTitle") }}
                    <UBadge :label="String(leadDeals?.length ?? 0)" color="neutral" variant="subtle" size="sm" class="cds-tag" />
                  </h3>
                  <UButton
                    v-if="hasPermission('crm_deals', 'create')"
                    icon="i-lucide-plus"
                    :label="t('crm.leads.createDeal')"
                    size="sm"
                    @click="openDealModal"
                  />
                </div>

                <div v-if="leadDealsStatus === 'pending'" class="flex justify-center py-6">
                  <UIcon name="i-lucide-loader-2" class="size-5 animate-spin text-muted" />
                </div>
                <p v-else-if="!leadDeals?.length" class="border border-dashed border-default p-6 text-center text-sm text-muted">
                  {{ t("crm.leads.noDealsYet") }}
                </p>
                <ul v-else class="space-y-2">
                  <li v-for="deal in leadDeals" :key="deal.id">
                    <button
                      type="button"
                      class="flex w-full flex-wrap items-center justify-between gap-2 border border-default p-3 text-start transition-colors hover:border-primary hover:bg-elevated"
                      @click="openDeal(deal.id)"
                    >
                      <span class="min-w-0">
                        <span class="block truncate font-medium text-highlighted">{{ deal.title || "—" }}</span>
                        <span class="block text-xs text-muted">
                          {{ pipelineName(deal.pipeline_id) }} · {{ profileLabel(deal.assigned_to) }} · {{ formatDate(deal.created_at) }}
                        </span>
                      </span>
                      <span class="flex items-center gap-2">
                        <span v-if="formatMoney(deal.value)" class="text-sm font-semibold text-success">{{ formatMoney(deal.value) }}</span>
                        <UBadge
                          :label="stageOf(deal.stage_id)?.name ?? '—'"
                          :color="stageColor(deal.stage_id)"
                          variant="subtle"
                          size="sm"
                          class="cds-tag"
                        />
                      </span>
                    </button>
                  </li>
                </ul>
              </div>
            </div>
          </template>
        </section>
      </div>
    </template>
  </UDashboardPanel>

  <LeadDealModal v-model:open="dealModalOpen" :lead="selectedLead" @created="onDealCreated" />

  <UModal v-model:open="createOpen" :title="t('crm.leads.newLead')">
    <template #body>
      <UForm :schema="schema" :state="state" class="space-y-4" @submit="onCreate">
        <UFormField name="lead_type" :label="t('crm.leads.leadType')">
          <URadioGroup v-model="state.lead_type" orientation="horizontal" :items="leadTypeOptions" value-key="value" />
        </UFormField>

        <UFormField v-if="state.lead_type === 'company'" name="company_name" :label="t('crm.leads.companyName')">
          <UInput v-model="state.company_name" class="w-full" />
        </UFormField>

        <UFormField name="name" :label="state.lead_type === 'company' ? t('crm.leads.contactPerson') : t('common.name')">
          <UInput v-model="state.name" class="w-full" />
        </UFormField>

        <UFormField name="phone" :label="t('common.phone')">
          <PhoneInput v-model="state.phone" />
        </UFormField>
        <UFormField name="phone2" :label="t('crm.leads.phone2')">
          <PhoneInput v-model="state.phone2" />
        </UFormField>
        <UAlert
          v-if="duplicateLead"
          color="warning"
          variant="subtle"
          icon="i-lucide-triangle-alert"
          :title="t('crm.leads.duplicatePhone')"
        >
          <template #description>
            <ULink :to="`/crm/leads?id=${duplicateLead.id}`" class="inline-flex items-center gap-1 font-medium text-primary">
              {{ duplicateLead.name }}
              <UIcon name="i-lucide-arrow-left" class="size-3" />
            </ULink>
          </template>
        </UAlert>
        <UFormField name="email" :label="t('common.email')">
          <UInput v-model="state.email" type="email" class="w-full" />
        </UFormField>
        <UFormField name="source" :label="t('crm.leads.source')">
          <USelect v-model="state.source" :items="sourceOptions" value-key="value" class="w-full" />
        </UFormField>

        <UFormField v-if="canAssign" name="assigned_to" :label="t('crm.leads.assignedTo')">
          <USelect v-model="state.assigned_to" :items="assigneeOptions" value-key="value" class="w-full" />
        </UFormField>
        <p v-else class="text-xs text-muted">
          {{ t("crm.leads.assignHint") }}
        </p>

        <UFormField name="notes" :label="t('crm.leads.notes')">
          <UTextarea v-model="state.notes" class="w-full" :rows="3" />
        </UFormField>

        <UButton type="submit" :label="t('crm.leads.createLead')" :loading="creating" :disabled="!!duplicateLead" block />
      </UForm>
    </template>
  </UModal>
</template>
