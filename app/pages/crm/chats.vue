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

interface Conversation {
  id: string; wa_id: string; display_name: string | null; status: "qualifying" | "qualified" | "handed_over" | "known" | "closed";
  ai_paused: boolean; collected: Record<string, string>; ai_replies: number; lead_id: string | null; customer_id: string | null;
  last_inbound_at: string | null; last_message_at: string; unread: boolean; provider: "cloud" | "waha";
}
interface Message { id: string; direction: "in" | "out"; sender: "customer" | "ai" | "agent"; body: string | null; created_at: string }

const filter = ref<"all" | "unread" | "handed_over" | "qualifying" | "qualified">("all");
const { data: convs, refresh } = await useAsyncData<Conversation[]>("wa-conversations", async () => {
  const { data } = await supabase.from("whatsapp_conversations").select("*").order("last_message_at", { ascending: false }).limit(150);
  return (data ?? []) as Conversation[];
});
const shown = computed(() => (convs.value ?? []).filter((c) => filter.value === "all" || (filter.value === "unread" ? c.unread : c.status === filter.value)));
const counts = computed(() => {
  const all = convs.value ?? [];
  return { all: all.length, unread: all.filter((c) => c.unread).length, handed_over: all.filter((c) => c.status === "handed_over").length, qualifying: all.filter((c) => c.status === "qualifying").length, qualified: all.filter((c) => c.status === "qualified").length };
});
const tabs = computed(() => (["all", "unread", "handed_over", "qualifying", "qualified"] as const).map((k) => ({ value: k, label: `${t(`chats.filter.${k}`)} (${counts.value[k]})` })));
const statusTone = { qualifying: "primary", qualified: "success", handed_over: "warning", known: "neutral", closed: "neutral" } as const;

const openId = ref<string | null>(typeof route.query.open === "string" ? route.query.open : null);
const current = computed(() => (convs.value ?? []).find((c) => c.id === openId.value) ?? null);
const messages = ref<Message[]>([]);
async function loadMessages() {
  if (!openId.value) {
    messages.value = [];
    return;
  }
  const { data } = await supabase.from("whatsapp_messages").select("id, direction, sender, body, created_at").eq("conversation_id", openId.value).order("created_at");
  messages.value = (data ?? []) as Message[];
  // opening a chat marks it read
  if (current.value?.unread && canReply.value) {
    await supabase.from("whatsapp_conversations").update({ unread: false }).eq("id", openId.value);
    await refresh();
  }
}
watch(openId, loadMessages, { immediate: true });

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
onMounted(() => {
  timer = setInterval(() => {
    refresh();
    loadMessages();
  }, 15_000);
});
onBeforeUnmount(() => clearInterval(timer));

const title = (c: Conversation) => c.display_name || `+${c.wa_id}`;
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
async function setAi(paused: boolean) {
  if (!current.value) return;
  await supabase.from("whatsapp_conversations").update({ ai_paused: paused, ...(paused ? {} : { status: "qualifying" }) }).eq("id", current.value.id);
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
      <div class="grid gap-4 lg:grid-cols-[22rem_1fr]">
        <!-- The conversations -->
        <div class="space-y-3">
          <UTabs v-model="filter" :items="tabs" value-key="value" variant="link" size="sm" :content="false" class="kords-pilltabs" />
          <p v-if="!shown.length" class="kords-card p-6 text-center text-sm text-muted">{{ t("chats.empty") }}</p>
          <ul v-else class="space-y-2">
            <li v-for="c in shown" :key="c.id">
              <button type="button" class="kords-card flex w-full items-start gap-3 p-3 text-start transition hover:border-primary" :class="openId === c.id && 'border-primary'" @click="openId = c.id">
                <span class="mt-1.5 size-2 shrink-0 rounded-full" :class="c.unread ? 'bg-primary' : 'bg-transparent'" />
                <span class="min-w-0 flex-1">
                  <span class="flex items-center justify-between gap-2">
                    <span class="flex min-w-0 items-center gap-1.5"><span class="truncate font-medium text-highlighted">{{ title(c) }}</span><UIcon v-if="c.provider === 'waha'" name="i-lucide-smartphone" class="size-3.5 shrink-0 text-muted" :title="t('chats.viaPhone')" /></span>
                    <KBadge :label="t(`chats.status.${c.status}`)" :tone="statusTone[c.status]" class="shrink-0" />
                  </span>
                  <span class="mt-0.5 block truncate text-xs text-muted" dir="ltr">+{{ c.wa_id }} · {{ formatDMYTime(c.last_message_at, locale) }}</span>
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
                <p class="text-xs text-muted" dir="ltr">+{{ current.wa_id }}</p>
              </div>
              <div class="flex flex-wrap items-center gap-2">
                <KBadge :label="t(`chats.status.${current.status}`)" :tone="statusTone[current.status]" />
                <UButton v-if="current.lead_id" :to="`/crm/leads?id=${current.lead_id}`" size="xs" color="neutral" variant="outline" icon="i-lucide-user-round" :label="t('chats.openLead')" />
                <UButton v-if="canCreate && !current.lead_id && !current.customer_id" size="xs" icon="i-lucide-user-plus" :label="t('chats.createContact')" :loading="creating" @click="createContact" />
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
                {{ m.body }}
                <p class="mt-1 text-[10px] opacity-60">{{ formatDMYTime(m.created_at, locale) }}</p>
              </div>
            </div>
          </div>

          <footer v-if="canReply" class="space-y-2 border-t border-default p-3">
            <p v-if="!insideWindow" class="text-xs text-warning">{{ t("chats.outsideWindow") }}</p>
            <div class="flex items-end gap-2">
              <UTextarea v-model="text" :rows="2" :disabled="!insideWindow" :placeholder="t('chats.writeReply')" class="min-w-0 flex-1" @keydown.ctrl.enter="send" @keydown.meta.enter="send" />
              <UButton icon="i-lucide-send" :loading="sending" :disabled="!insideWindow || !text.trim()" :aria-label="t('chats.send')" @click="send" />
            </div>
            <p v-if="current.provider === 'cloud' && !current.ai_paused && current.status === 'qualifying'" class="text-xs text-muted">{{ t("chats.replyPausesAi") }}</p>
          </footer>
        </div>
        <p v-else class="kords-card hidden p-10 text-center text-sm text-muted lg:block">{{ t("chats.pick") }}</p>
      </div>
    </template>
  </UDashboardPanel>

  <NewChatModal v-model:open="newOpen" :initial-phone="newPhone" @sent="onNewSent" />
</template>
