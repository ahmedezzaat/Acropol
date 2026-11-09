import * as z from "zod";
import { serverSupabaseClient, serverSupabaseServiceRole, serverSupabaseUser } from "#supabase/server";

const bodySchema = z.object({ conversation_id: z.uuid(), text: z.string().trim().min(1).max(4000), from_draft: z.boolean().optional() });

// An agent answers a chat from the inbox. A Cloud API chat goes out from the connected number (only inside
// the 24 hours after the customer's last message); a WAHA chat goes out through WAHA, with no such limit.
// The message is kept in the chat. The assistant stops
// answering that chat once a person writes in it.
export default defineEventHandler(async (event) => {
  const user = await serverSupabaseUser(event);
  if (!user?.sub) throw createError({ statusCode: 401, statusMessage: "Not authenticated" });
  const { conversation_id, text, from_draft } = await readValidatedBody(event, bodySchema.parse);

  const allowed = await (await serverSupabaseClient(event)).rpc("has_permission", { p_module: "crm_chats", p_action: "reply" });
  if (!allowed.data) throw createError({ statusCode: 403, statusMessage: "Not allowed" });

  const admin = serverSupabaseServiceRole(event);
  const { data: conv } = await admin.from("whatsapp_conversations").select("id, provider, phone_number_id, wa_id, chat_id, last_inbound_at").eq("id", conversation_id).maybeSingle();
  if (!conv) throw createError({ statusCode: 404, statusMessage: "Conversation not found" });
  if (conv.provider !== "waha" && (!conv.last_inbound_at || Date.now() - new Date(conv.last_inbound_at).getTime() > 24 * 3_600_000)) {
    throw createError({ statusCode: 409, statusMessage: "outside_window" });
  }

  const wamid =
    conv.provider === "waha"
      ? await sendWahaText(event, conv.phone_number_id, conv.wa_id, text, conv.chat_id)
      : await sendWhatsAppText(admin, conv.phone_number_id, conv.wa_id, text);
  await admin.from("whatsapp_messages").insert({ conversation_id: conv.id, direction: "out", sender: from_draft ? "ai" : "agent", body: text, wa_message_id: wamid });
  // sending the agent's own draft does not stop the agent; writing by hand does
  await admin
    .from("whatsapp_conversations")
    .update({ ai_draft: null, unread: false, last_message_at: new Date().toISOString(), ...(from_draft ? {} : { ai_paused: true }) })
    .eq("id", conv.id);
  return { sent: true };
});
