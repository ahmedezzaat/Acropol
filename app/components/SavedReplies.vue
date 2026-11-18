<script setup lang="ts">
// Saved replies (ردود جاهزة) in a chat's reply box: a button with the list (search, click to insert) and the "/" shortcut
// typed in the box. {name} and {agent} are filled in. Everyone with the inbox can also add / change / delete them here.
// The parent keeps the text (v-model) and passes the keys of its text box to handleKey().
const text = defineModel<string>("text", { required: true });
const props = defineProps<{ contactName?: string | null; disabled?: boolean }>();

const supabase = useSupabaseClient();
const me = useSupabaseUser();
const { t } = useI18n();
const { replies, load, used } = useSavedReplies();

const agentName = ref("");
onMounted(async () => {
  await load();
  if (me.value?.sub) {
    const { data } = await supabase.from("profiles").select("full_name, email").eq("id", me.value.sub).maybeSingle();
    agentName.value = (data?.full_name as string | null) || (data?.email as string | null) || "";
  }
});

const fill = (body: string) => body.replaceAll("{name}", props.contactName?.trim() || "").replaceAll("{agent}", agentName.value).replace(/ +([،,.!؟?])/g, "$1");

// ---- insert: a "/shortcut" being typed is replaced, otherwise the reply goes after what is already written
const slash = computed(() => /^\/([^\s/]*)$/.exec(text.value));
const slashMatches = computed(() => {
  if (!slash.value) return [];
  const q = slash.value[1]!.toLowerCase();
  return replies.value.filter((r) => !q || (r.shortcut ?? "").toLowerCase().startsWith(q) || r.title.toLowerCase().includes(q)).slice(0, 6);
});
const active = ref(0);
watch(slashMatches, () => (active.value = 0));
function insert(r: SavedReply) {
  const body = fill(r.body);
  text.value = slash.value || !text.value.trim() ? body : `${text.value.replace(/\s+$/, "")}\n${body}`;
  listOpen.value = false;
  used(r);
}
// Arrow keys and Enter / Tab pick from the "/" list while it is open
function handleKey(e: KeyboardEvent) {
  if (!slashMatches.value.length) return;
  if (e.key === "ArrowDown") (e.preventDefault(), (active.value = (active.value + 1) % slashMatches.value.length));
  else if (e.key === "ArrowUp") (e.preventDefault(), (active.value = (active.value + slashMatches.value.length - 1) % slashMatches.value.length));
  else if ((e.key === "Enter" || e.key === "Tab") && !e.ctrlKey && !e.metaKey) (e.preventDefault(), insert(slashMatches.value[active.value]!));
}
defineExpose({ handleKey });

// ---- the list behind the button
const listOpen = ref(false);
const search = ref("");
const shown = computed(() => {
  const q = search.value.trim().toLowerCase();
  return replies.value.filter((r) => !q || `${r.title} ${r.body} ${r.shortcut ?? ""}`.toLowerCase().includes(q));
});

const manageOpen = ref(false);
const prefill = ref("");
function openManager(withText = "") {
  prefill.value = withText;
  listOpen.value = false;
  manageOpen.value = true;
}
</script>

<template>
  <div class="relative">
    <!-- the "/" list, above the box -->
    <ul v-if="slashMatches.length" class="absolute bottom-full start-0 z-20 mb-1 w-80 max-w-[90vw] overflow-hidden rounded-[10px] border border-default bg-default shadow-lg" role="listbox">
      <li v-for="(r, i) in slashMatches" :key="r.id" role="option" :aria-selected="i === active">
        <button type="button" class="block w-full px-3 py-2 text-start text-sm" :class="i === active ? 'bg-primary/10' : 'hover:bg-elevated'" @mousedown.prevent="insert(r)">
          <span class="flex items-center gap-2"><span class="font-medium text-highlighted">{{ r.title }}</span><span v-if="r.shortcut" class="text-xs text-muted">/{{ r.shortcut }}</span></span>
          <span class="line-clamp-1 text-xs text-toned">{{ fill(r.body) }}</span>
        </button>
      </li>
    </ul>

    <UPopover v-model:open="listOpen" :content="{ side: 'top', align: 'start' }">
      <UButton icon="i-lucide-zap" color="neutral" variant="outline" :disabled="disabled" :aria-label="t('chats.saved.title')" :title="t('chats.saved.title')" />
      <template #content>
        <div class="w-80 max-w-[90vw] space-y-2 p-2">
          <UInput v-model="search" icon="i-lucide-search" size="sm" :placeholder="t('chats.saved.search')" class="w-full" />
          <p v-if="!shown.length" class="p-3 text-center text-xs text-muted">{{ replies.length ? t("chats.saved.noMatch") : t("chats.saved.empty") }}</p>
          <ul v-else class="max-h-64 divide-y divide-default overflow-y-auto">
            <li v-for="r in shown" :key="r.id">
              <button type="button" class="block w-full rounded-[8px] px-2 py-2 text-start text-sm hover:bg-elevated" @click="insert(r)">
                <span class="flex items-center gap-2"><span class="font-medium text-highlighted">{{ r.title }}</span><span v-if="r.shortcut" class="text-xs text-muted">/{{ r.shortcut }}</span></span>
                <span class="line-clamp-2 text-xs text-toned">{{ r.body }}</span>
              </button>
            </li>
          </ul>
          <div class="flex flex-wrap gap-1 border-t border-default pt-2">
            <UButton size="xs" color="neutral" variant="ghost" icon="i-lucide-settings-2" :label="t('chats.saved.manage')" @click="openManager()" />
            <UButton v-if="text.trim()" size="xs" color="neutral" variant="ghost" icon="i-lucide-bookmark-plus" :label="t('chats.saved.saveCurrent')" @click="openManager(text)" />
          </div>
        </div>
      </template>
    </UPopover>

    <SavedRepliesManager v-model:open="manageOpen" :prefill="prefill" />
  </div>
</template>
