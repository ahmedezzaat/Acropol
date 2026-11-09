import type { SupabaseClient } from "@supabase/supabase-js";

interface WahaMessage {
  session: string;
  waId: string;
  name: string | null;
  wamid: string | null;
  text: string;
  fromMe: boolean;
  // the full WAHA chat id, for a person whose number is hidden ("<id>@lid")
  chatId?: string | null;
  // a photo or file kept in the wa-media bucket
  media?: { path: string; type: string | null; name: string | null } | null;
}

// Keeps a WAHA message in the inbox (conversation + message). Messages arrive twice when WAHA sends both
// "message" and "message.any", and our own replies come back as "message.any": each is stored once.
export async function recordWahaMessage(admin: SupabaseClient, m: WahaMessage): Promise<string | null> {
  const find = () =>
    admin.from("whatsapp_conversations").select("id, display_name").eq("provider", "waha").eq("phone_number_id", m.session).eq("wa_id", m.waId).maybeSingle();
  let { data: conv } = await find();
  if (!conv) {
    // a hidden number cannot be matched to a lead or customer
    const known = m.chatId ? null : ((await admin.rpc("whatsapp_known_contact", { p_digits: m.waId })).data as { entity: "lead" | "customer"; id: string } | null);
    const { data: created } = await admin
      .from("whatsapp_conversations")
      .insert({
        provider: "waha",
        phone_number_id: m.session,
        wa_id: m.waId,
        ...(m.chatId ? { chat_id: m.chatId } : {}),
        display_name: m.fromMe ? null : m.name,
        status: known ? "known" : "handed_over",
        lead_id: known?.entity === "lead" ? known.id : null,
        customer_id: known?.entity === "customer" ? known.id : null,
        unread: !m.fromMe,
      })
      .select("id, display_name")
      .single();
    // two messages at once: the other one made it first
    conv = created ?? (await find()).data;
  }
  if (!conv) return null;

  if (m.wamid) {
    const { data: dup } = await admin.from("whatsapp_messages").select("id").eq("wa_message_id", m.wamid).limit(1);
    if (dup?.length) return conv.id;
  }
  if (m.fromMe) {
    // a reply sent from the inbox comes back with its own id: do not store it twice
    const since = new Date(Date.now() - 90_000).toISOString();
    const { data: same } = await admin
      .from("whatsapp_messages")
      .select("id")
      .eq("conversation_id", conv.id)
      .eq("direction", "out")
      .eq("body", m.text)
      .gte("created_at", since)
      .limit(1);
    if (same?.length) return conv.id;
  }

  await admin.from("whatsapp_messages").insert({
    conversation_id: conv.id,
    direction: m.fromMe ? "out" : "in",
    sender: m.fromMe ? "agent" : "customer",
    body: m.text,
    wa_message_id: m.wamid,
    ...(m.media ? { media_path: m.media.path, media_type: m.media.type, media_name: m.media.name } : {}),
  });
  const now = new Date().toISOString();
  await admin
    .from("whatsapp_conversations")
    .update({
      last_message_at: now,
      // a reply typed on the phone: a person is in this chat, so the agent (auto mode) stops answering it
      // (the agent's own messages never get here: they are stored when sent and the echo is skipped above)
      ...(m.fromMe ? { ai_paused: true } : { last_inbound_at: now, unread: true }),
      ...(!m.fromMe && m.name && !conv.display_name ? { display_name: m.name } : {}),
    })
    .eq("id", conv.id);
  return conv.id;
}
