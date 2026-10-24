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
  created_by: string | null;
  created_at: string;
}
interface FileRow {
  id: string;
  work_item_id: string;
  file_name: string;
  storage_path: string;
  from_work_pipeline_id: string | null;
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
const loading = ref(true);

async function load() {
  const id = pipelineId.value;
  const [p, s, i, pr] = await Promise.all([
    supabase.from("work_pipelines").select("name").eq("id", id).maybeSingle(),
    supabase.from("work_pipeline_stages").select("id, name, sort_order").eq("work_pipeline_id", id).order("sort_order"),
    supabase.from("work_items").select("id, stage_id, deal_id, title, assigned_to, stage_changed_at, request_note, deadline, created_by, created_at").eq("work_pipeline_id", id).order("stage_changed_at"),
    supabase.from("profiles").select("id, full_name, email").eq("is_active", true).order("full_name"),
  ]);
  pipelineName.value = p.data?.name ?? "";
  stages.value = (s.data ?? []) as Stage[];
  items.value = (i.data ?? []) as Item[];
  people.value = (pr.data ?? []) as Person[];
  const ids = items.value.map((x) => x.id);
  files.value = ids.length ? (((await supabase.from("deal_attachments").select("id, work_item_id, file_name, storage_path, from_work_pipeline_id").in("work_item_id", ids)).data ?? []) as FileRow[]) : [];
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
const filesOf = (itemId: string) => files.value.filter((f) => f.work_item_id === itemId);
// People who work this board attach files to an item; they are tagged as coming from it
const uploadingId = ref<string | null>(null);
async function uploadFiles(item: Item, event: Event) {
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
      .insert({ deal_id: item.deal_id, file_name: file.name, storage_path: path, work_item_id: item.id, from_work_pipeline_id: pipelineId.value });
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
              <article v-for="it in itemsOf(stage.id)" :key="it.id" class="kords-card space-y-2 p-3 text-sm">
                <NuxtLink :to="`/crm/deals/${it.deal_id}`" class="block font-semibold text-highlighted hover:text-primary">{{ it.title }}</NuxtLink>
                <p v-if="it.request_note" class="whitespace-pre-line rounded-[8px] bg-muted p-2 text-xs text-toned">{{ it.request_note }}</p>
                <div v-if="it.deadline" class="flex items-center gap-1.5 text-xs" :class="overdue(it) ? 'font-semibold text-error' : 'text-muted'">
                  <UIcon name="i-lucide-calendar-clock" class="size-3.5" />{{ t("crm.work.deadline") }}: {{ formatDMYTime(it.deadline, locale) }}
                  <KBadge v-if="overdue(it)" :label="t('crm.work.overdue')" tone="error" />
                </div>
                <div v-if="filesOf(it.id).length" class="flex flex-wrap gap-1.5">
                  <button v-for="f in filesOf(it.id)" :key="f.id" type="button" class="flex max-w-full items-center gap-1 rounded-full border px-2 py-0.5 text-xs" :class="f.from_work_pipeline_id ? 'border-success/50 bg-success/10 text-success' : 'border-default text-primary'" @click="openFile(f)">
                    <UIcon :name="f.from_work_pipeline_id ? 'i-lucide-git-fork' : 'i-lucide-paperclip'" class="size-3.5 shrink-0" /><span class="truncate">{{ f.file_name }}</span>
                  </button>
                </div>
                <div v-if="canEdit">
                  <input :id="`up-${it.id}`" type="file" multiple class="hidden" @change="uploadFiles(it, $event)" />
                  <label :for="`up-${it.id}`" class="inline-flex cursor-pointer items-center gap-1 text-xs text-primary">
                    <UIcon :name="uploadingId === it.id ? 'i-lucide-loader-2' : 'i-lucide-paperclip'" class="size-3.5" :class="uploadingId === it.id && 'animate-spin'" />{{ t("crm.work.addFiles") }}
                  </label>
                </div>
                <p v-if="personName(it.created_by)" class="text-xs text-muted">{{ t("crm.work.requestedBy", { name: personName(it.created_by) ?? "" }) }} · {{ formatDMY(it.created_at) }}</p>
                <div class="flex items-center justify-between gap-2 text-xs text-muted">
                  <span class="flex items-center gap-1"><UIcon name="i-lucide-clock" class="size-3.5" />{{ t("crm.work.daysIn", { n: daysIn(it) }) }}</span>
                  <span v-if="!canEdit">{{ personName(it.assigned_to) || t("crm.work.unassigned") }}</span>
                </div>
                <USelect
                  v-if="canEdit"
                  :model-value="it.assigned_to"
                  :items="personOptions"
                  value-key="value"
                  size="sm"
                  icon="i-lucide-user"
                  class="w-full"
                  @update:model-value="(v: unknown) => assign(it, v)"
                />
                <div v-if="canEdit" class="flex items-center justify-between gap-2">
                  <UButton icon="i-lucide-chevron-right" color="neutral" variant="soft" size="sm" :disabled="si === 0" :aria-label="t('crm.work.back')" class="rtl:rotate-0 ltr:rotate-180" @click="step(it, -1)" />
                  <UButton icon="i-lucide-chevron-left" color="primary" variant="soft" size="sm" :disabled="si === stages.length - 1" :aria-label="t('crm.work.forward')" class="rtl:rotate-0 ltr:rotate-180" @click="step(it, 1)" />
                </div>
              </article>
            </div>
          </section>
        </div>
      </template>
    </template>
  </UDashboardPanel>
</template>
