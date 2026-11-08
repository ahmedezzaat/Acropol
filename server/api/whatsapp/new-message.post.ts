import * as z from "zod";
import { serverSupabaseClient, serverSupabaseServiceRole, serverSupabaseUser } from "#supabase/server";

const bodySchema = z.object({ phone: z.string().trim().min(5).max(30), text: z.string().trim().min(1).max(4000) });

// Starts a chat with a number from the inbox ("new message"): the first message goes out through WAHA and
// the conversation is created, linked to the lead or customer who has that number.
export default defineEventHandler(async (event) => {
  const user = await serverSupabaseUser(event);
  if (!user?.sub) throw createError({ statusCode: 401, statusMessage: "Not authenticated" });
  const { phone, text } = await readValidatedBody(event, bodySchema.parse);

  const allowed = await (await serverSupabaseClient(event)).rpc("has_permission", { p_module: "crm_chats", p_action: "reply" });
  if (!allowed.data) throw createError({ statusCode: 403, statusMessage: "Not allowed" });

  const digits = canonicalPhone(phone);
  if (!digits || digits.length < 7 || digits.length > 15) throw createError({ statusCode: 400, statusMessage: "invalid_phone" });

  const c = await getWahaConfig(event);
  // is the number on WhatsApp? (a best-effort check: if WAHA cannot answer, the message is tried anyway)
  try {
    const r = await wahaFetch<{ numberExists?: boolean }>(event, `/api/contacts/check-exists?phone=${digits}&session=${encodeURIComponent(c.session)}`);
    if (r?.numberExists === false) throw createError({ statusCode: 422, statusMessage: "not_on_whatsapp" });
  } catch (err: any) {
    if (err?.statusMessage === "not_on_whatsapp") throw err;
  }

  const wamid = await sendWahaText(event, c.session, digits, text);
  const admin = serverSupabaseServiceRole(event);
  const conversationId = await recordWahaMessage(admin, { session: c.session, waId: digits, name: null, wamid, text, fromMe: true });
  if (!conversationId) throw createError({ statusCode: 500, statusMessage: "The message was sent but could not be saved in the inbox" });
  return { sent: true, conversation_id: conversationId };
});
