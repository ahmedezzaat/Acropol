<script setup lang="ts">
// "New message": start a WhatsApp chat with a number — typed, or picked from the leads and customers.
const props = defineProps<{ initialPhone?: string }>();
const open = defineModel<boolean>("open", { default: false });
const emit = defineEmits<{ sent: [conversationId: string] }>();

const supabase = useSupabaseClient();
const toast = useToast();
const { t } = useI18n();

const phone = ref("");
const text = ref("");
const sending = ref(false);

// pick a contact by name or number
interface Hit { key: string; name: string; phone: string; kind: "lead" | "customer" }
const search = ref("");
const hits = ref<Hit[]>([]);
let timer: ReturnType<typeof setTimeout> | undefined;
watch(search, (q) => {
  clearTimeout(timer);
  const term = q.trim();
  if (term.length < 2) {
    hits.value = [];
    return;
  }
  timer = setTimeout(async () => {
    const pattern = `name.ilike.%${term}%,phone.ilike.%${term}%`;
    const [leads, customers] = await Promise.all([
      supabase.from("leads").select("id, name, phone").or(pattern).not("phone", "is", null).limit(6),
      supabase.from("customers").select("id, name, phone").or(pattern).not("phone", "is", null).limit(6),
    ]);
    hits.value = [
      ...(customers.data ?? []).map((c) => ({ key: `c${c.id}`, name: c.name as string, phone: c.phone as string, kind: "customer" as const })),
      ...(leads.data ?? []).map((l) => ({ key: `l${l.id}`, name: l.name as string, phone: l.phone as string, kind: "lead" as const })),
    ];
  }, 250);
});
function pick(h: Hit) {
  phone.value = h.phone;
  search.value = "";
  hits.value = [];
}

watch(open, (isOpen) => {
  if (!isOpen) return;
  phone.value = props.initialPhone ?? "";
  text.value = "";
  search.value = "";
  hits.value = [];
});

const valid = computed(() => phone.value.replace(/\D/g, "").length >= 7 && !!text.value.trim());
async function send() {
  if (!valid.value) return;
  sending.value = true;
  try {
    const r = await $fetch<{ conversation_id: string }>("/api/whatsapp/new-message", { method: "POST", body: { phone: phone.value, text: text.value.trim() } });
    toast.add({ title: t("chats.newSent"), color: "success" });
    open.value = false;
    emit("sent", r.conversation_id);
  } catch (err: any) {
    const code = err?.data?.statusMessage ?? err.message;
    const known: Record<string, string> = { invalid_phone: t("chats.errInvalidPhone"), not_on_whatsapp: t("chats.errNotOnWhatsapp") };
    toast.add({ title: t("chats.sendFailed"), description: known[code] ?? code, color: "error" });
  } finally {
    sending.value = false;
  }
}
</script>

<template>
  <UModal v-model:open="open" :title="t('chats.newMessage')">
    <template #body>
      <div class="space-y-4">
        <UFormField :label="t('chats.findContact')">
          <UInput v-model="search" icon="i-lucide-search" :placeholder="t('chats.findContactHint')" class="w-full" />
          <ul v-if="hits.length" class="mt-2 max-h-44 divide-y divide-default overflow-y-auto rounded-[10px] border border-default">
            <li v-for="h in hits" :key="h.key">
              <button type="button" class="flex w-full items-center justify-between gap-3 px-3 py-2 text-start text-sm hover:bg-muted" @click="pick(h)">
                <span class="min-w-0 truncate font-medium text-highlighted">{{ h.name }}</span>
                <span class="flex shrink-0 items-center gap-2 text-xs text-muted"><span dir="ltr">{{ h.phone }}</span><KBadge :label="t(`chats.kind.${h.kind}`)" tone="neutral" /></span>
              </button>
            </li>
          </ul>
        </UFormField>
        <UFormField :label="t('common.phone')" required>
          <PhoneInput v-model="phone" />
        </UFormField>
        <UFormField :label="t('chats.firstMessage')" required>
          <UTextarea v-model="text" :rows="4" class="w-full" @keydown.ctrl.enter="send" @keydown.meta.enter="send" />
        </UFormField>
        <UButton icon="i-lucide-send" :label="t('chats.send')" :loading="sending" :disabled="!valid" size="lg" block @click="send" />
      </div>
    </template>
  </UModal>
</template>
