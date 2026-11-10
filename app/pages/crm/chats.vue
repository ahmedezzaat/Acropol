<script setup lang="ts">
// WhatsApp chats: the conversations the assistant is having with people who are not yet contacts,
// what it has learned, and a place for an agent to read, answer and (when the chat did not qualify)
// create the contact by hand.
definePageMeta({ layout: "dashboard", crmPermission: { module: "crm_chats" } });
useHead({ htmlAttrs: { class: "carbon kords" } });

const supabase = useSupabaseClient();
const route = useRoute();
const toast = useToast();
const { t, locale } = useI18n();
const { hasPermission } = usePermissions();
const canReply = computed(() => hasPermission("crm_chats", "reply"));
const canCreate = computed(() => hasPermission("crm_chats", "create_contact"));
// a deal can be created from the chat by someone who may create deals
const canDeal = computed(() => hasPermission("crm_deals", "create"));
const canFixLink = computed(() => hasPermission("settings", "integrations"));

interface Conversation {
  id: string; wa_id: string; display_name: string | null; status: "qualifying" | "qualified" | "handed_over" | "known" | "closed";
  ai_paused: boolean; collected: Record<string, string>; ai_replies: number; lead_id: string | null; customer_id: string | null;
  last_inbound_at: string | null; last_message_at: string; unread: boolean; provider: "cloud" | "waha";
  ai_draft: string | null; ai_deal_id: string | null;
}
interface Message { id: string; direction: "in" | "out"; sender: "customer" | "ai" | "agent"; body: string | null; created_at: string; media_path: string | null; media_type: string | null; media_name: string | null }

const filter = ref<"all" | "unread" | "waiting" | "handed_over" | "qualifying" | "qualified">("all");
// a chat waits for us when the customer wrote last (both times are set together when a message arrives)
const isWaiting = (c: Conversation) => !!c.last_inbound_at && c.status !== "closed" && new Date(c.last_message_at).getTime() - new Date(c.last_inbound_at).getTime() < 2000;
const { data: convs, refresh } = await useAsyncData<Conversation[]>("wa-conversations", async () => {
  const { data } = await supabase.from("whatsapp_conversations").select("*").order("last_message_at", { ascending: false }).limit(150);
  return (data ?? []) as Conversation[];
});
// ---- search: by name or number (here) and by message text (asked from the database, after a short pause)
const search = ref("");
const msgHits = ref<Record<string, string>>({});
let searchTimer: ReturnType<typeof setTimeout> | undefined;
watch(search, (q) => {
  clearTimeout(searchTimer);
  const term = q.trim();
  if (term.length < 2) {
    msgHits.value = {};
    return;
  }
  searchTimer = setTimeout(async () => {
    // % _ and \ are wildcards in a LIKE pattern: searched for literally
    const like = `%${term.replace(/[\\%_]/g, (m) => `\\${m}`)}%`;
    const { data } = await supabase.from("whatsapp_messages").select("conversation_id, body, created_at").ilike("body", like).order("created_at", { ascending: false }).limit(300);
    if (search.value.trim() !== term) return;
    const hits: Record<string, string> = {};
    for (const r of data ?? []) if (!hits[r.conversation_id]) hits[r.conversation_id] = r.body ?? "";
    msgHits.value = hits;
  }, 300);
});
const matchesSearch = (c: Conversation) => {
  const term = search.value.trim().toLowerCase();
  if (term.length < 1) return true;
  const digits = term.replace(/\D/g, "");
  return (c.display_name ?? "").toLowerCase().includes(term) || (digits.length >= 3 && c.wa_id.includes(digits)) || c.id in msgHits.value;
};
const snippet = (c: Conversation) => {
  const body = msgHits.value[c.id];
  const term = search.value.trim();
  if (!body || term.length < 2 || (c.display_name ?? "").toLowerCase().includes(term.toLowerCase())) return "";
  const i = body.toLowerCase().indexOf(term.toLowerCase());
  const from = Math.max(0, i - 20);
  return (from > 0 ? "…" : "") + body.slice(from, from + 70);
};
const matchesFilter = (c: Conversation) => filter.value === "all" || (filter.value === "unread" ? c.unread : filter.value === "waiting" ? isWaiting(c) : c.status === filter.value);
const shown = computed(() => {
  const list = (convs.value ?? []).filter((c) => matchesFilter(c) && matchesSearch(c));
  // the ones that have waited longest come first
  return filter.value === "waiting" ? [...list].sort((a, b) => new Date(a.last_inbound_at ?? 0).getTime() - new Date(b.last_inbound_at ?? 0).getTime()) : list;
});
// how long a chat has waited ("3 hours"), refreshed with the page's own timer
const now = ref(Date.now());
const rtf = computed(() => new Intl.RelativeTimeFormat(locale.value, { numeric: "always", style: "long" }));
function agoText(ms: number) {
  const mins = Math.max(0, Math.round(ms / 60_000));
  const [v, unit] = mins < 60 ? [mins, "minute"] : mins < 1440 ? [Math.floor(mins / 60), "hour"] : [Math.floor(mins / 1440), "day"];
  // the formatter only supplies the unit name and digits: its "ago" wording is removed
  return rtf.value.format(-(v as number), unit as Intl.RelativeTimeFormatUnit).replace(/^(منذ|قبل)\s*|\s*(ago|منذ|قبل)$/g, "").trim();
}
const waitedFor = (c: Conversation) => agoText(now.value - new Date(c.last_inbound_at ?? now.value).getTime());
// ---- the WhatsApp link: warns when messages cannot arrive, and says how the assistant is set
interface Health { configured: boolean; problem: "unreachable" | "no_session" | "not_working" | "wrong_webhook" | null; status: string | null; mode: "off" | "draft" | "auto"; maxAiReplies: number; lastInboundAt: string | null }
const health = ref<Health | null>(null);
async function loadHealth() {
  try {
    health.value = await $fetch<Health>("/api/whatsapp/health");
  } catch {
    /* no banner when it cannot be checked */
  }
}
// no message for this long is unusual for a company inbox (nights are quiet, a day is not)
const SILENT_AFTER_MS = 12 * 3_600_000;
const silentFor = computed(() => (health.value?.configured && health.value.lastInboundAt && now.value - new Date(health.value.lastInboundAt).getTime() > SILENT_AFTER_MS ? now.value - new Date(health.value.lastInboundAt).getTime() : 0));
const banner = computed(() => {
  const h = health.value;
  if (!h?.configured) return null;
  if (h.problem) return { color: "error" as const, text: t(`chats.health.${h.problem}`, { status: h.status ?? "" }), fixable: h.problem === "wrong_webhook" };
  if (silentFor.value) return { color: "warning" as const, text: t("chats.health.silent", { ago: agoText(silentFor.value) }), fixable: false };
  return null;
});
const fixing = ref(false);
async function fixWebhook() {
  fixing.value = true;
  try {
    await $fetch("/api/admin/waha-webhook-apply", { method: "POST" });
    toast.add({ title: t("chats.health.fixed"), color: "success" });
    await loadHealth();
  } catch (err: any) {
    toast.add({ title: t("chats.health.fixFailed"), description: err?.data?.statusMessage ?? err.message, color: "error" });
  } finally {
    fixing.value = false;
  }
}
const counts = computed(() => {
  const all = convs.value ?? [];
  return { all: all.length, unread: all.filter((c) => c.unread).length, waiting: all.filter(isWaiting).length, handed_over: all.filter((c) => c.status === "handed_over").length, qualifying: all.filter((c) => c.status === "qualifying").length, qualified: all.filter((c) => c.status === "qualified").length };
});
const tabs = computed(() => (["all", "unread", "waiting", "handed_over", "qualifying", "qualified"] as const).map((k) => ({ value: k, label: `${t(`chats.filter.${k}`)} (${counts.value[k]})` })));
const statusTone = { qualifying: "primary", qualified: "success", handed_over: "warning", known: "neutral", closed: "neutral" } as const;

const openId = ref<string | null>(typeof route.query.open === "string" ? route.query.open : null);
const current = computed(() => (convs.value ?? []).find((c) => c.id === openId.value) ?? null);
const messages = ref<Message[]>([]);
async function loadMessages() {
  if (!openId.value) {
    messages.value = [];
    return;
  }
  const { data } = await supabase.from("whatsapp_messages").select("id, direction, sender, body, created_at, media_path, media_type, media_name").eq("conversation_id", openId.value).order("created_at");
  messages.value = (data ?? []) as Message[];
  await loadMediaUrls();
  // opening a chat marks it read
  if (current.value?.unread && canReply.value) {
    await supabase.from("whatsapp_conversations").update({ unread: false }).eq("id", openId.value);
    await refresh();
  }
}
watch(openId, loadMessages, { immediate: true });

// ---- photos and files: shown from the private bucket through short-lived links
const mediaUrls = ref<Record<string, string>>({});
async function loadMediaUrls() {
  const need = [...new Set(messages.value.map((m) => m.media_path).filter((x): x is string => !!x && !mediaUrls.value[x]))];
  if (!need.length) return;
  const { data } = await supabase.storage.from("wa-media").createSignedUrls(need, 3600);
  for (const r of data ?? []) if (r.path && r.signedUrl) mediaUrls.value[r.path] = r.signedUrl;
}
const isImage = (m: Message) => !!m.media_type?.startsWith("image/");
const isVideo = (m: Message) => !!m.media_type?.startsWith("video/");
const isAudio = (m: Message) => !!m.media_type?.startsWith("audio/");

// ---- send a photo or file (WAHA chats): it goes to the bucket from here, then WAHA is told to send it
const fileInput = ref<HTMLInputElement | null>(null);
const picked = ref<File | null>(null);
const MAX_FILE = 16 * 1024 * 1024;
function onPick(e: Event) {
  const f = (e.target as HTMLInputElement).files?.[0] ?? null;
  (e.target as HTMLInputElement).value = "";
  if (f && f.size > MAX_FILE) {
    toast.add({ title: t("chats.media.tooBig"), color: "error" });
    return;
  }
  picked.value = f;
}
async function sendMedia() {
  if (!current.value || !picked.value) return;
  sending.value = true;
  const f = picked.value;
  try {
    const path = `out/${current.value.id}/${Date.now()}-${crypto.randomUUID().slice(0, 8)}${(f.name.match(/\.[A-Za-z0-9]{1,8}$/)?.[0] ?? "")}`;
    const { error } = await supabase.storage.from("wa-media").upload(path, f, { contentType: f.type || undefined });
    if (error) throw new Error(error.message);
    await $fetch("/api/whatsapp/send-media", { method: "POST", body: { conversation_id: current.value.id, path, name: f.name, type: f.type || "application/octet-stream", caption: text.value.trim() || undefined } });
    picked.value = null;
    text.value = "";
    await Promise.all([refresh(), loadMessages()]);
  } catch (err: any) {
    const code = err?.data?.statusMessage ?? err.message;
    toast.add({ title: t("chats.sendFailed"), description: code === "needs_waha_plus" ? t("chats.media.needsPlus") : code === "media_not_supported" ? t("chats.media.notSupported") : code, color: "error" });
  } finally {
    sending.value = false;
  }
}

// Arriving from a "WhatsApp" button (?phone=<digits>): open that person's chat, or start one
onMounted(async () => {
  const digits = typeof route.query.phone === "string" ? route.query.phone.replace(/\D/g, "") : "";
  if (!digits) return;
  const { data: found } = await supabase.from("whatsapp_conversations").select("id").eq("wa_id", digits).order("last_message_at", { ascending: false }).limit(1).maybeSingle();
  if (found) openId.value = found.id;
  else if (canReply.value) openNew(`+${digits}`);
});
// new messages arrive while the page is open
let timer: ReturnType<typeof setInterval> | undefined;
let ticks = 0;
onMounted(() => {
  loadHealth();
  timer = setInterval(() => {
    now.value = Date.now();
    if (++ticks % 4 === 0) loadHealth();
    refresh();
    loadMessages();
  }, 15_000);
});
onBeforeUnmount(() => clearInterval(timer));

// a person whose WhatsApp number is hidden has no number to show
const isHidden = (c: Conversation) => c.wa_id.startsWith("lid-");
const idLabel = (c: Conversation) => (isHidden(c) ? t("chats.hiddenNumber") : `+${c.wa_id}`);
const title = (c: Conversation) => c.display_name || idLabel(c);
// WhatsApp's 24-hour rule is only for the Cloud API; a WAHA chat can always be answered
const insideWindow = computed(() => current.value?.provider === "waha" || !!current.value?.last_inbound_at && Date.now() - new Date(current.value.last_inbound_at).getTime() < 24 * 3_600_000);
const collectedLines = computed(() => Object.entries(current.value?.collected ?? {}).filter(([, v]) => v).map(([k, v]) => ({ label: t(`chats.fields.${k}`), value: v })));

// ---- Answer, pause the assistant, create the contact
// ---- New message: start a chat with a number
const newOpen = ref(false);
const newPhone = ref("");
function openNew(phone = "") {
  newPhone.value = phone;
  newOpen.value = true;
}
async function onNewSent(id: string) {
  filter.value = "all";
  await refresh();
  openId.value = id;
}

const text = ref("");
const sending = ref(false);
async function send() {
  if (!current.value || !text.value.trim()) return;
  sending.value = true;
  try {
    await $fetch("/api/whatsapp/reply", { method: "POST", body: { conversation_id: current.value.id, text: text.value.trim() } });
    text.value = "";
    await Promise.all([refresh(), loadMessages()]);
  } catch (err: any) {
    const code = err?.data?.statusMessage ?? err.message;
    toast.add({ title: t("chats.sendFailed"), description: code === "outside_window" ? t("chats.outsideWindow") : code, color: "error" });
  } finally {
    sending.value = false;
  }
}
// ---- the agent's suggested reply (draft mode): send it as it is, edit it first, or throw it away
const sendingDraft = ref(false);
async function sendDraft() {
  if (!current.value?.ai_draft) return;
  sendingDraft.value = true;
  try {
    await $fetch("/api/whatsapp/reply", { method: "POST", body: { conversation_id: current.value.id, text: current.value.ai_draft, from_draft: true } });
    await Promise.all([refresh(), loadMessages()]);
  } catch (err: any) {
    toast.add({ title: t("chats.sendFailed"), description: err?.data?.statusMessage ?? err.message, color: "error" });
  } finally {
    sendingDraft.value = false;
  }
}
function editDraft() {
  text.value = current.value?.ai_draft ?? "";
  discardDraft();
}
async function discardDraft() {
  if (!current.value) return;
  await supabase.from("whatsapp_conversations").update({ ai_draft: null }).eq("id", current.value.id);
  await refresh();
}
// ---- what the assistant does in this chat (WAHA chats), and taking it over / handing it back
const agentState = computed(() => {
  const c = current.value;
  const h = health.value;
  if (!c || c.provider !== "waha" || !h) return null;
  if (h.mode === "off") return { key: "off", icon: "i-lucide-bot-off", tone: "neutral" as const, canToggle: false };
  if (h.mode === "draft") return { key: "draft", icon: "i-lucide-pencil-line", tone: "primary" as const, canToggle: false };
  if (c.ai_paused) return { key: "paused", icon: "i-lucide-hand", tone: "warning" as const, canToggle: true };
  if (h.maxAiReplies && c.ai_replies >= h.maxAiReplies) return { key: "limit", icon: "i-lucide-octagon-alert", tone: "warning" as const, canToggle: false };
  return { key: "auto", icon: "i-lucide-bot", tone: "success" as const, canToggle: true };
});
async function setAi(paused: boolean) {
  if (!current.value) return;
  await supabase.from("whatsapp_conversations").update({ ai_paused: paused, ...(paused || current.value.provider === "waha" ? {} : { status: "qualifying" }) }).eq("id", current.value.id);
  await refresh();
}
const creating = ref(false);
async function createContact() {
  if (!current.value) return;
  creating.value = true;
  try {
    await $fetch("/api/whatsapp/create-contact", { method: "POST", body: { conversation_id: current.value.id } });
    toast.add({ title: t("chats.contactCreated"), color: "success" });
    await refresh();
  } catch (err: any) {
    toast.add({ title: t("chats.contactFailed"), description: err?.data?.statusMessage ?? err.message, color: "error" });
  } finally {
    creating.value = false;
  }
}
</script>

<template>
  <UDashboardPanel :ui="{ body: 'kords-canvas !p-3 sm:!p-6' }">
    <template #header>
      <UDashboardNavbar :title="t('chats.title')">
        <template #leading>
          <UDashboardSidebarCollapse />
        </template>
        <template #right>
          <UButton v-if="canReply" icon="i-lucide-square-pen" :label="t('chats.newMessage')" @click="openNew()" />
        </template>
      </UDashboardNavbar>
    </template>

    <template #body>
      <UAlert v-if="banner" :color="banner.color" variant="subtle" icon="i-lucide-triangle-alert" :title="banner.text" class="mb-4">
        <template v-if="canFixLink" #actions>
          <UButton v-if="banner.fixable" size="xs" color="neutral" variant="outline" icon="i-lucide-wrench" :label="t('chats.health.fix')" :loading="fixing" @click="fixWebhook" />
          <UButton to="/admin/integrations" size="xs" color="neutral" variant="outline" :label="t('chats.health.openSettings')" />
        </template>
      </UAlert>
      <div class="grid gap-4 lg:grid-cols-[20rem_1fr] xl:grid-cols-[20rem_1fr_20rem]">
        <!-- The conversations -->
        <div class="space-y-3">
          <UInput v-model="search" icon="i-lucide-search" :placeholder="t('chats.search')" size="sm" class="w-full" :ui="{ trailing: 'pe-1' }">
            <template v-if="search" #trailing>
              <UButton color="neutral" variant="link" size="xs" icon="i-lucide-x" :aria-label="t('common.close')" @click="search = ''" />
            </template>
          </UInput>
          <div class="flex flex-wrap gap-1.5">
            <button v-for="tab in tabs" :key="tab.value" type="button" class="rounded-full border px-3 py-1 text-xs transition" :class="filter === tab.value ? 'border-primary bg-primary text-white' : 'border-default text-muted hover:border-primary'" @click="filter = tab.value">{{ tab.label }}</button>
          </div>
          <p v-if="!shown.length" class="kords-card p-6 text-center text-sm text-muted">{{ search.trim() ? t("chats.noResults") : t("chats.empty") }}</p>
          <ul v-else class="space-y-2">
            <li v-for="c in shown" :key="c.id">
              <button type="button" class="kords-card flex w-full items-start gap-3 p-3 text-start transition hover:border-primary" :class="openId === c.id && 'border-primary'" @click="openId = c.id">
                <span class="mt-1.5 size-2 shrink-0 rounded-full" :class="c.unread ? 'bg-primary' : 'bg-transparent'" />
                <span class="min-w-0 flex-1">
                  <span class="flex items-center justify-between gap-2">
                    <span class="flex min-w-0 items-center gap-1.5"><span class="truncate font-medium text-highlighted">{{ title(c) }}</span><UIcon v-if="c.provider === 'waha' && health?.mode === 'auto' && c.ai_paused" name="i-lucide-hand" class="size-3.5 shrink-0 text-warning" :title="t('chats.agentState.paused')" /><UIcon v-if="c.provider === 'waha'" name="i-lucide-smartphone" class="size-3.5 shrink-0 text-muted" :title="t('chats.viaPhone')" /></span>
                    <KBadge :label="t(`chats.status.${c.status}`)" :tone="statusTone[c.status]" class="shrink-0" />
                  </span>
                  <span class="mt-0.5 block truncate text-xs text-muted"><bdi dir="ltr">{{ idLabel(c) }}</bdi> · {{ formatDMYTime(c.last_message_at, locale) }}</span>
                  <span v-if="isWaiting(c)" class="mt-0.5 flex items-center gap-1 text-xs font-medium text-warning"><UIcon name="i-lucide-clock" class="size-3.5" />{{ t("chats.waitingFor", { ago: waitedFor(c) }) }}</span>
                  <span v-if="snippet(c)" class="mt-0.5 block truncate text-xs text-muted">{{ t("chats.foundInMessage") }} <bdi>{{ snippet(c) }}</bdi></span>
                </span>
              </button>
            </li>
          </ul>
        </div>

        <!-- The chat -->
        <div v-if="current" class="kords-card flex min-h-[32rem] flex-col">
          <header class="space-y-2 border-b border-default p-4">
            <div class="flex flex-wrap items-center justify-between gap-2">
              <div>
                <h3 class="font-semibold text-highlighted">{{ title(current) }}</h3>
                <p class="text-xs text-muted"><bdi dir="ltr">{{ idLabel(current) }}</bdi></p>
              </div>
              <div class="flex flex-wrap items-center gap-2">
                <KBadge :label="t(`chats.status.${current.status}`)" :tone="statusTone[current.status]" />
                <UButton v-if="current.lead_id" :to="`/crm/leads?id=${current.lead_id}`" size="xs" color="neutral" variant="outline" icon="i-lucide-user-round" :label="t('chats.openLead')" />
                <UButton v-if="canCreate && !current.lead_id && !current.customer_id && !isHidden(current)" size="xs" icon="i-lucide-user-plus" :label="t('chats.createContact')" :loading="creating" @click="createContact" />
                <span v-if="agentState" class="inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-medium" :class="{ 'bg-success/10 text-success': agentState.tone === 'success', 'bg-warning/10 text-warning': agentState.tone === 'warning', 'bg-primary/10 text-primary': agentState.tone === 'primary', 'bg-muted text-muted': agentState.tone === 'neutral' }"><UIcon :name="agentState.icon" class="size-3.5" />{{ t(`chats.agentState.${agentState.key}`) }}</span>
                <UButton v-if="canReply && agentState?.canToggle" size="xs" color="neutral" variant="outline" :icon="current.ai_paused ? 'i-lucide-bot' : 'i-lucide-hand'" :label="current.ai_paused ? t('chats.resumeAi') : t('chats.takeOver')" @click="setAi(!current.ai_paused)" />
                <UButton v-if="canReply && current.provider === 'cloud' && current.status !== 'known'" size="xs" color="neutral" variant="outline" :icon="current.ai_paused ? 'i-lucide-bot' : 'i-lucide-hand'" :label="current.ai_paused ? t('chats.resumeAi') : t('chats.takeOver')" @click="setAi(!current.ai_paused)" />
              </div>
            </div>
            <div v-if="collectedLines.length" class="flex flex-wrap gap-1.5">
              <span v-for="l in collectedLines" :key="l.label" class="rounded-full bg-primary/10 px-2 py-0.5 text-xs text-primary">{{ l.label }}: {{ l.value }}</span>
            </div>
            <p v-else-if="current.status === 'qualifying'" class="text-xs text-muted">{{ t("chats.nothingYet") }}</p>
          </header>

          <div class="flex-1 space-y-2 overflow-y-auto p-4" style="max-height: 28rem">
            <div v-for="m in messages" :key="m.id" class="flex" :class="m.direction === 'in' ? 'justify-start' : 'justify-end'">
              <div class="max-w-[80%] whitespace-pre-line rounded-[14px] px-3 py-2 text-sm" :class="m.direction === 'in' ? 'bg-muted text-highlighted' : m.sender === 'ai' ? 'bg-primary/10 text-highlighted' : 'bg-primary text-white'">
                <p v-if="m.direction === 'out'" class="mb-0.5 text-[10px] opacity-70">{{ m.sender === "ai" ? t("chats.assistant") : t("chats.agent") }}</p>
                <template v-if="m.media_path">
                  <a v-if="isImage(m) && mediaUrls[m.media_path]" :href="mediaUrls[m.media_path]" target="_blank" rel="noopener"><img :src="mediaUrls[m.media_path]" :alt="m.media_name ?? ''" class="mb-1 max-h-64 rounded-[10px] object-cover" loading="lazy" /></a>
                  <video v-else-if="isVideo(m) && mediaUrls[m.media_path]" :src="mediaUrls[m.media_path]" controls class="mb-1 max-h-64 rounded-[10px]" />
                  <audio v-else-if="isAudio(m) && mediaUrls[m.media_path]" :src="mediaUrls[m.media_path]" controls class="mb-1" />
                  <a v-else-if="mediaUrls[m.media_path]" :href="mediaUrls[m.media_path]" target="_blank" rel="noopener" :download="m.media_name ?? true" class="mb-1 flex items-center gap-1.5 underline"><UIcon name="i-lucide-paperclip" class="size-4" /><bdi dir="ltr">{{ m.media_name || t("chats.media.file") }}</bdi></a>
                </template>
                <span v-if="m.body && m.body !== '[media]' && m.body !== '[no text]'">{{ m.body }}</span>
                <span v-else-if="m.body === '[media]' || m.body === '[no text]'" class="inline-flex items-center gap-1 italic opacity-80"><UIcon name="i-lucide-image" class="size-3.5" />{{ t("chats.media.unavailable") }}</span>
                <p class="mt-1 text-[10px] opacity-60">{{ formatDMYTime(m.created_at, locale) }}</p>
              </div>
            </div>
          </div>

          <footer v-if="canReply" class="space-y-2 border-t border-default p-3">
            <div v-if="current.ai_draft" class="space-y-2 rounded-[10px] border border-primary/40 bg-primary/5 p-3">
              <p class="flex items-center gap-1.5 text-xs font-medium text-primary"><UIcon name="i-lucide-bot" class="size-3.5" />{{ t("chats.draft.title") }}</p>
              <p class="whitespace-pre-line text-sm text-highlighted">{{ current.ai_draft }}</p>
              <div class="flex flex-wrap gap-2">
                <UButton size="xs" icon="i-lucide-send" :label="t('chats.draft.send')" :loading="sendingDraft" @click="sendDraft" />
                <UButton size="xs" color="neutral" variant="outline" icon="i-lucide-pencil" :label="t('chats.draft.edit')" @click="editDraft" />
                <UButton size="xs" color="neutral" variant="ghost" :label="t('chats.draft.discard')" @click="discardDraft" />
              </div>
            </div>
            <p v-if="!insideWindow" class="text-xs text-warning">{{ t("chats.outsideWindow") }}</p>
            <p v-if="picked" class="flex items-center gap-2 rounded-[10px] bg-muted px-3 py-1.5 text-xs"><UIcon name="i-lucide-paperclip" class="size-3.5 shrink-0 text-primary" /><bdi dir="ltr" class="min-w-0 flex-1 truncate">{{ picked.name }}</bdi><button type="button" class="text-muted hover:text-highlighted" :aria-label="t('common.cancel')" @click="picked = null"><UIcon name="i-lucide-x" class="size-3.5" /></button></p>
            <div class="flex items-end gap-2">
              <input ref="fileInput" type="file" class="hidden" @change="onPick" />
              <UButton v-if="current.provider === 'waha'" icon="i-lucide-paperclip" color="neutral" variant="outline" :disabled="sending" :aria-label="t('chats.media.attach')" @click="fileInput?.click()" />
              <UTextarea v-model="text" :rows="2" :disabled="!insideWindow" :placeholder="picked ? t('chats.media.caption') : t('chats.writeReply')" class="min-w-0 flex-1" @keydown.ctrl.enter="picked ? sendMedia() : send()" @keydown.meta.enter="picked ? sendMedia() : send()" />
              <UButton icon="i-lucide-send" :loading="sending" :disabled="!insideWindow || (!picked && !text.trim())" :aria-label="t('chats.send')" @click="picked ? sendMedia() : send()" />
            </div>
            <p v-if="current.provider === 'cloud' && !current.ai_paused && current.status === 'qualifying'" class="text-xs text-muted">{{ t("chats.replyPausesAi") }}</p>
          </footer>
        </div>
        <p v-else class="kords-card hidden p-10 text-center text-sm text-muted lg:block">{{ t("chats.pick") }}</p>

        <!-- Next to the chat: create a deal from it -->
        <ChatDealPanel v-if="current && canDeal" :key="current.id" :chat="current" @changed="refresh" />
      </div>
    </template>
  </UDashboardPanel>

  <NewChatModal v-model:open="newOpen" :initial-phone="newPhone" @sent="onNewSent" />
</template>
