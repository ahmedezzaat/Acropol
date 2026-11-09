import * as z from "zod";
import { serverSupabaseClient, serverSupabaseServiceRole, serverSupabaseUser } from "#supabase/server";

// Sends a photo or file to a WhatsApp (WAHA) chat. The browser has already put the file in the private wa-media
// bucket; WAHA is given a short-lived link to it, so the file never passes through this server.
// Needs WAHA Plus (Core cannot send media).
const bodySchema = z.object({
  conversation_id: z.uuid(),
  path: z.string().min(3).max(300).regex(/^out\/[\w./-]+$/),
  name: z.string().trim().min(1).max(200),
  type: z.string().trim().max(100).default("application/octet-stream"),
  caption: z.string().trim().max(1000).optional(),
});

export default defineEventHandler(async (event) => {
  const user = await serverSupabaseUser(event);
  if (!user?.sub) throw createError({ statusCode: 401, statusMessage: "Not authenticated" });
  const { conversation_id, path, name, type, caption } = await readValidatedBody(event, bodySchema.parse);

  const allowed = await (await serverSupabaseClient(event)).rpc("has_permission", { p_module: "crm_chats", p_action: "reply" });
  if (!allowed.data) throw createError({ statusCode: 403, statusMessage: "Not allowed" });

  const admin = serverSupabaseServiceRole(event);
  const { data: conv } = await admin.from("whatsapp_conversations").select("id, provider, phone_number_id, wa_id, chat_id").eq("id", conversation_id).maybeSingle();
  if (!conv) throw createError({ statusCode: 404, statusMessage: "Conversation not found" });
  if (conv.provider !== "waha") throw createError({ statusCode: 409, statusMessage: "media_not_supported" });

  const { data: signed, error: signError } = await admin.storage.from("wa-media").createSignedUrl(path, 600);
  if (signError || !signed?.signedUrl) throw createError({ statusCode: 404, statusMessage: "File not found" });

  const isImage = type.startsWith("image/") && !type.includes("svg");
  let res: any;
  try {
    res = await wahaFetch<any>(event, isImage ? "/api/sendImage" : "/api/sendFile", {
      method: "POST",
      body: {
        session: conv.phone_number_id,
        chatId: conv.chat_id || `${conv.wa_id}@c.us`,
        file: { mimetype: type, filename: name, url: signed.signedUrl },
        ...(caption ? { caption } : {}),
      },
    });
  } catch (err: any) {
    // WAHA Core answers with an error for media: say so plainly
    const msg = String(err?.statusMessage ?? "");
    throw createError({ statusCode: 502, statusMessage: /plus|not available|not supported|501|422/i.test(msg) ? "needs_waha_plus" : msg });
  }

  await admin.from("whatsapp_messages").insert({
    conversation_id: conv.id,
    direction: "out",
    sender: "agent",
    body: caption ?? "",
    wa_message_id: wahaMessageId(res),
    media_path: path,
    media_type: type,
    media_name: name,
  });
  await admin.from("whatsapp_conversations").update({ ai_paused: true, unread: false, ai_draft: null, last_message_at: new Date().toISOString() }).eq("id", conv.id);
  return { sent: true };
});
