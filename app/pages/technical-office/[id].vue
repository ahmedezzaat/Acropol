<script setup lang="ts">
// The board of a sub-workflow (e.g. the technical office): one column per stage, a
// card per deal handed to it. Cards move between stages and are assigned from here.
definePageMeta({
  layout: "dashboard",
  crmPermission: { module: "crm_work" },
});

useHead({ htmlAttrs: { class: "carbon" } });

const route = useRoute();
const supabase = useSupabaseClient();
const toast = useToast();
const { t, locale } = useI18n();
const { hasPermission } = usePermissions();
const pipelineId = computed(() => route.params.id as string);
const canEdit = computed(() => hasPermission("crm_work", "edit"));
const canAddFiles = computed(() => canEdit.value && hasPermission("crm_work_files", "create"));
const canSeeWorkFiles = computed(() => hasPermission("crm_work_files", "view"));
// a board is seen with its own permission, or "see every board"
if (!hasPermission("crm_work", "view") && !hasPermission("crm_work", pipelineId.value)) await navigateTo("/403", { replace: true });

interface Stage {
  id: string;
  name: string;
  sort_order: number;
}
interface Item {
  id: string;
  stage_id: string;
  deal_id: string;
  title: string;
  assigned_to: string | null;
  stage_changed_at: string;
  request_note: string | null;
  deadline: string | null;
  product_category_id: string | null;
  created_by: string | null;
  created_at: string;
}
interface FileRow {
  id: string;
  work_item_id: string;
  file_name: string;
  storage_path: string;
  from_work_pipeline_id: string | null;
  kind: string | null;
}
interface Person {
  id: string;
  full_name: string | null;
  email: string;
}

const pipelineName = ref("");
const stages = ref<Stage[]>([]);
const items = ref<Item[]>([]);
const people = ref<Person[]>([]);
const files = ref<FileRow[]>([]);
const categories = ref<Record<string, string>>({});
const categoryOf = (i: Item) => (i.product_category_id ? categories.value[i.product_category_id] ?? null : null);
// the deal behind each card: its agent, and the lead's (or customer's) name and phone
const contacts = ref<Record<string, { deal_agent_id: string | null; contact_name: string | null; contact_phone: string | null }>>({});
const loading = ref(true);

async function load() {
  const id = pipelineId.value;
  const [p, s, i, pr, ct] = await Promise.all([
    supabase.from("work_pipelines").select("name").eq("id", id).maybeSingle(),
    supabase.from("work_pipeline_stages").select("id, name, sort_order").eq("work_pipeline_id", id).order("sort_order"),
    supabase.from("work_items").select("id, stage_id, deal_id, title, assigned_to, stage_changed_at, request_note, deadline, created_by, created_at").eq("work_pipeline_id", id).order("stage_changed_at"),
    supabase.from("profiles").select("id, full_name, email").eq("is_active", true).order("full_name"),
    supabase.rpc("work_item_contacts", { p_pipeline_id: id }),
  ]);
  const { data: cats } = await supabase.from("product_categories").select("id, name");
  categories.value = Object.fromEntries((cats ?? []).map((c) => [c.id, c.name]));
  contacts.value = Object.fromEntries((ct.data ?? []).map((c) => [c.work_item_id, c]));
  pipelineName.value = p.data?.name ?? "";
  stages.value = (s.data ?? []) as Stage[];
  items.value = (i.data ?? []) as Item[];
  // the product category is read on its own, so a board still loads where that column is not there yet
  const { data: itemCats } = await supabase.from("work_items").select("id, product_category_id").eq("work_pipeline_id", id);
  const catOf = new Map((itemCats ?? []).map((r) => [r.id, r.product_category_id]));
  for (const it of items.value) it.product_category_id = catOf.get(it.id) ?? null;
  people.value = (pr.data ?? []) as Person[];
  const ids = items.value.map((x) => x.id);
  files.value = ids.length ? (((await supabase.from("deal_attachments").select("id, work_item_id, file_name, storage_path, from_work_pipeline_id, kind").in("work_item_id", ids)).data ?? []) as FileRow[]) : [];
  loading.value = false;
}
await load();
watch(pipelineId, load);

useHead({ title: computed(() => pipelineName.value) });

const personOptions = computed(() => [
  { label: t("crm.work.unassigned"), value: null as string | null },
  ...people.value.map((p) => ({ label: p.full_name || p.email, value: p.id as string | null })),
]);
const personName = (id: string | null) => {
  const p = people.value.find((x) => x.id === id);
  return p ? p.full_name || p.email : null;
};
const itemsOf = (stageId: string) => items.value.filter((i) => i.stage_id === stageId);
const overdue = (i: Item) => !!i.deadline && new Date(i.deadline).getTime() < Date.now();
const filesOf = (itemId: string) => files.value.filter((f) => f.work_item_id === itemId && (!f.from_work_pipeline_id || canSeeWorkFiles.value));
// People who work this board attach files to an item; they are tagged as coming from it
const uploadingId = ref<string | null>(null);
async function uploadFiles(item: Item, event: Event, kind: "quote" | null = null) {
  const input = event.target as HTMLInputElement;
  const picked = Array.from(input.files ?? []);
  input.value = "";
  if (!picked.length) return;
  uploadingId.value = item.id;
  for (const file of picked) {
    const path = `${item.deal_id}/${Date.now()}-${file.name}`;
    const { error: uploadError } = await supabase.storage.from("deal-attachments").upload(path, file);
    if (uploadError) {
      toast.add({ title: t("crm.work.uploadFailed"), description: `${file.name}: ${uploadError.message}`, color: "error" });
      continue;
    }
    const { error } = await supabase
      .from("deal_attachments")
      .insert({ deal_id: item.deal_id, file_name: file.name, storage_path: path, work_item_id: item.id, from_work_pipeline_id: pipelineId.value, kind });
    if (error) {
      await supabase.storage.from("deal-attachments").remove([path]);
      toast.add({ title: t("crm.work.uploadFailed"), description: `${file.name}: ${error.message}`, color: "error" });
    }
  }
  uploadingId.value = null;
  await load();
}
async function openFile(f: FileRow) {
  const { data } = await supabase.storage.from("deal-attachments").createSignedUrl(f.storage_path, 60);
  if (data) window.open(data.signedUrl, "_blank");
}
// the card opened in the modal
const openId = ref<string | null>(null);
const selected = computed(() => items.value.find((i) => i.id === openId.value) ?? null);
const detailOpen = computed({ get: () => !!selected.value, set: (v) => { if (!v) openId.value = null; } });
const stageOf = (i: Item) => stages.value.find((s) => s.id === i.stage_id);
// the files of the open card: the technical office's own, and the requester's
const fileGroups = computed(() => {
  const rows = selected.value ? filesOf(selected.value.id) : [];
  return [
    // the quote (عرض السعر) is added from here and belongs to the deal's quote section
    { key: "quote", labelKey: "crm.work.quoteFiles", icon: "i-lucide-file-text", rows: rows.filter((f) => f.kind === "quote") },
    { key: "office", labelKey: "crm.work.officeFiles", icon: "i-lucide-git-fork", rows: rows.filter((f) => f.kind !== "quote" && !!f.from_work_pipeline_id) },
    { key: "requester", labelKey: "crm.work.requesterFiles", icon: "i-lucide-paperclip", rows: rows.filter((f) => f.kind !== "quote" && !f.from_work_pipeline_id) },
  ];
});
const daysIn = (i: Item) => Math.max(0, Math.floor((Date.now() - new Date(i.stage_changed_at).getTime()) / 86_400_000));

async function moveTo(item: Item, stageId: string) {
  if (!canEdit.value || stageId === item.stage_id) return;
  const before = { stage: item.stage_id, at: item.stage_changed_at };
  item.stage_id = stageId;
  item.stage_changed_at = new Date().toISOString();
  const { error } = await supabase.from("work_items").update({ stage_id: stageId }).eq("id", item.id);
  if (error) {
    item.stage_id = before.stage;
    item.stage_changed_at = before.at;
    toast.add({ title: t("crm.work.moveFailed"), description: error.message, color: "error" });
  }
}
function step(item: Item, dir: -1 | 1) {
  const index = stages.value.findIndex((s) => s.id === item.stage_id);
  const target = stages.value[index + dir];
  if (target) moveTo(item, target.id);
}
async function assign(item: Item, v: unknown) {
  const id = typeof v === "string" && v ? v : null;
  const before = item.assigned_to;
  item.assigned_to = id;
  const { error } = await supabase.from("work_items").update({ assigned_to: id }).eq("id", item.id);
  if (error) {
    item.assigned_to = before;
    toast.add({ title: t("crm.work.moveFailed"), description: error.message, color: "error" });
  }
}
</script>

<template>
  <UDashboardPanel :ui="{ body: 'kords-canvas !p-3 sm:!p-6' }">
    <template #header>
      <UDashboardNavbar :title="pipelineName">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <KBadge :label="t('crm.work.items', { count: items.length })" tone="primary" />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <div v-if="loading" class="flex justify-center py-16">
        <UIcon name="i-lucide-loader-2" class="size-6 animate-spin text-muted" />
      </div>
      <template v-else>
        <p v-if="!items.length" class="mb-4 text-sm text-muted">{{ t("crm.work.noItems") }}</p>
        <div class="flex items-start gap-3 overflow-x-auto pb-4">
          <section v-for="(stage, si) in stages" :key="stage.id" class="w-72 shrink-0 space-y-2">
            <header class="flex items-center justify-between px-1">
              <h3 class="text-sm font-semibold text-highlighted">{{ stage.name }}</h3>
              <KBadge :label="String(itemsOf(stage.id).length)" tone="neutral" />
            </header>
            <div class="min-h-24 space-y-2 rounded-[14px] bg-muted p-2">
              <p v-if="!itemsOf(stage.id).length" class="px-2 py-4 text-center text-xs text-muted">{{ t("crm.work.empty") }}</p>
              <article v-for="it in itemsOf(stage.id)" :key="it.id" class="kords-card cursor-pointer space-y-2 p-3 text-sm transition hover:border-primary" @click="openId = it.id">
                <div class="font-semibold text-highlighted">{{ it.title }}</div>
                <div class="space-y-1 text-xs text-toned">
                  <div v-if="categoryOf(it)" class="flex items-center gap-1.5">
                    <UIcon name="i-lucide-tags" class="size-3.5 shrink-0 text-muted" />
                    <span class="truncate">{{ categoryOf(it) }}</span>
                  </div>
                  <div v-if="contacts[it.id] && personName(contacts[it.id]!.deal_agent_id)" class="flex items-center gap-1.5">
                    <UIcon name="i-lucide-briefcase" class="size-3.5 shrink-0 text-muted" />
                    <span class="text-muted">{{ t("crm.work.dealAgent") }}:</span>
                    <span class="truncate">{{ personName(contacts[it.id]!.deal_agent_id) }}</span>
                  </div>
                </div>
                <div v-if="it.deadline" class="flex items-center gap-1.5 text-xs" :class="overdue(it) ? 'font-semibold text-error' : 'text-muted'">
                  <UIcon name="i-lucide-calendar-clock" class="size-3.5" />{{ formatDMYTime(it.deadline, locale) }}
                  <KBadge v-if="overdue(it)" :label="t('crm.work.overdue')" tone="error" />
                </div>
                <div class="flex items-center justify-between gap-2 text-xs text-muted">
                  <span class="flex items-center gap-1"><UIcon name="i-lucide-clock" class="size-3.5" />{{ t("crm.work.daysIn", { n: daysIn(it) }) }}</span>
                  <span class="flex items-center gap-2">
                    <span v-if="filesOf(it.id).length" class="flex items-center gap-0.5"><UIcon name="i-lucide-paperclip" class="size-3.5" />{{ filesOf(it.id).length }}</span>
                    <span class="truncate">{{ personName(it.assigned_to) || t("crm.work.unassigned") }}</span>
                  </span>
                </div>
                <div v-if="canEdit" class="flex items-center justify-between gap-2">
                  <UButton icon="i-lucide-chevron-right" color="neutral" variant="soft" size="sm" :disabled="si === 0" :aria-label="t('crm.work.back')" class="rtl:rotate-0 ltr:rotate-180" @click.stop="step(it, -1)" />
                  <UButton icon="i-lucide-chevron-left" color="primary" variant="soft" size="sm" :disabled="si === stages.length - 1" :aria-label="t('crm.work.forward')" class="rtl:rotate-0 ltr:rotate-180" @click.stop="step(it, 1)" />
                </div>
              </article>
            </div>
          </section>
        </div>
      </template>
    </template>
  </UDashboardPanel>

  <!-- The full card: opens over the board instead of a separate page -->
  <UModal v-model:open="detailOpen" :ui="{ content: 'max-w-2xl' }">
    <template #header>
      <div v-if="selected" class="min-w-0 flex-1 space-y-3">
        <div class="space-y-1">
          <div class="flex flex-wrap items-center gap-2">
            <KBadge :label="stageOf(selected)?.name ?? ''" tone="primary" />
            <KBadge v-if="overdue(selected)" :label="t('crm.work.overdue')" tone="error" icon="i-lucide-alarm-clock" />
            <span class="flex items-center gap-1 text-xs text-muted"><UIcon name="i-lucide-clock" class="size-3.5" />{{ t("crm.work.daysIn", { n: daysIn(selected) }) }}</span>
          </div>
          <h2 class="truncate text-lg font-semibold text-highlighted">{{ selected.title }}</h2>
          <p v-if="personName(selected.created_by)" class="text-xs text-muted">{{ t("crm.work.requestedBy", { name: personName(selected.created_by) ?? "" }) }} · {{ formatDMY(selected.created_at) }}</p>
        </div>
        <!-- where the card is in the workflow -->
        <div class="flex gap-1" role="img" :aria-label="stageOf(selected)?.name">
          <span v-for="s in stages" :key="s.id" class="h-1.5 flex-1 rounded-full" :class="s.sort_order <= (stageOf(selected)?.sort_order ?? 0) ? 'bg-primary' : 'bg-muted'" :title="s.name" />
        </div>
      </div>
    </template>
    <template #body>
      <div v-if="selected" class="space-y-4 text-sm">
        <!-- At a glance: category, deal agent, contact, deadline -->
        <div class="grid grid-cols-2 gap-2">
          <div v-if="categoryOf(selected)" class="rounded-[12px] bg-muted p-3">
            <p class="flex items-center gap-1.5 text-xs text-muted"><UIcon name="i-lucide-tags" class="size-3.5" />{{ t("crm.work.productCategory") }}</p>
            <p class="mt-1 truncate font-medium text-highlighted">{{ categoryOf(selected) }}</p>
          </div>
          <div v-if="contacts[selected.id] && personName(contacts[selected.id]!.deal_agent_id)" class="rounded-[12px] bg-muted p-3">
            <p class="flex items-center gap-1.5 text-xs text-muted"><UIcon name="i-lucide-briefcase" class="size-3.5" />{{ t("crm.work.dealAgent") }}</p>
            <p class="mt-1 truncate font-medium text-highlighted">{{ personName(contacts[selected.id]!.deal_agent_id) }}</p>
          </div>
          <div v-if="selected.deadline" class="rounded-[12px] p-3" :class="overdue(selected) ? 'bg-error/10' : 'bg-muted'">
            <p class="flex items-center gap-1.5 text-xs" :class="overdue(selected) ? 'text-error' : 'text-muted'"><UIcon name="i-lucide-calendar-clock" class="size-3.5" />{{ t("crm.work.deadline") }}</p>
            <p class="mt-1 font-medium" :class="overdue(selected) ? 'text-error' : 'text-highlighted'">{{ formatDMYTime(selected.deadline, locale) }}</p>
          </div>
          <div v-if="contacts[selected.id] && (contacts[selected.id]!.contact_name || contacts[selected.id]!.contact_phone)" class="flex items-center gap-2 rounded-[12px] bg-muted p-3">
            <div class="min-w-0 flex-1">
              <p class="flex items-center gap-1.5 text-xs text-muted"><UIcon name="i-lucide-user-round" class="size-3.5" />{{ t("crm.work.contact") }}</p>
              <p class="mt-1 truncate font-medium text-highlighted">{{ contacts[selected.id]!.contact_name || "—" }}</p>
              <a v-if="contacts[selected.id]!.contact_phone" :href="`tel:${contacts[selected.id]!.contact_phone}`" dir="ltr" class="text-xs text-primary">{{ contacts[selected.id]!.contact_phone }}</a>
            </div>
            <UButton v-if="contacts[selected.id]!.contact_phone" :to="`tel:${contacts[selected.id]!.contact_phone}`" icon="i-lucide-phone" color="primary" variant="soft" size="sm" :aria-label="t('crm.work.call')" />
          </div>
        </div>

        <!-- The request, with the files the requester attached right under it -->
        <section class="space-y-3 rounded-[14px] border border-default p-3">
          <p class="text-xs font-semibold text-toned">{{ t("crm.work.note") }}</p>
          <p v-if="selected.request_note" class="whitespace-pre-line text-toned">{{ selected.request_note }}</p>
          <WorkFileGroup
            v-for="g in fileGroups.filter((x) => x.key === 'requester')"
            :key="g.key"
            :label="t(g.labelKey)"
            :icon="g.icon"
            :rows="g.rows"
            :input-id="`up-${g.key}-${selected.id}`"
            @open="openFile"
          />
        </section>

        <!-- The technical office's side: the quote and its own files -->
        <section class="space-y-4 rounded-[14px] border border-default p-3">
          <WorkFileGroup
            v-for="g in fileGroups.filter((x) => x.key !== 'requester')"
            :key="g.key"
            :label="t(g.labelKey)"
            :icon="g.icon"
            :rows="g.rows"
            :input-id="`up-${g.key}-${selected.id}`"
            :can-upload="canAddFiles"
            :uploading="uploadingId === selected.id"
            @pick="(e: Event) => uploadFiles(selected!, e, g.key === 'quote' ? 'quote' : null)"
            @open="openFile"
          />
        </section>
      </div>
    </template>
    <template #footer>
      <div v-if="selected" class="w-full space-y-3">
        <div class="grid gap-3 sm:grid-cols-2">
          <div class="space-y-1">
            <p class="text-xs text-muted">{{ t("crm.work.assignedTo") }}</p>
            <USelect
              v-if="canEdit"
              :model-value="selected.assigned_to"
              :items="personOptions"
              value-key="value"
              icon="i-lucide-user"
              class="w-full"
              @update:model-value="(v: unknown) => assign(selected!, v)"
            />
            <p v-else class="font-medium text-highlighted">{{ personName(selected.assigned_to) || t("crm.work.unassigned") }}</p>
          </div>
          <div class="space-y-1">
            <p class="text-xs text-muted">{{ t("crm.work.stage") }}</p>
            <USelect
              v-if="canEdit"
              :model-value="selected.stage_id"
              :items="stages.map((s) => ({ label: s.name, value: s.id }))"
              value-key="value"
              icon="i-lucide-kanban"
              class="w-full"
              @update:model-value="(v: unknown) => typeof v === 'string' && moveTo(selected!, v)"
            />
            <p v-else class="font-medium text-highlighted">{{ stageOf(selected)?.name }}</p>
          </div>
        </div>
        <UButton :to="`/crm/deals/${selected.deal_id}`" target="_blank" icon="i-lucide-external-link" color="neutral" variant="outline" :label="t('crm.work.openDeal')" block />
      </div>
    </template>
  </UModal>
</template>
