import * as z from "zod";
import { serverSupabaseClient, serverSupabaseServiceRole, serverSupabaseUser } from "#supabase/server";

const bodySchema = z.object({ conversation_id: z.uuid() });

// An agent turns a chat into a contact (a lead) by hand — for a conversation the assistant did not qualify.
export default defineEventHandler(async (event) => {
  const user = await serverSupabaseUser(event);
  if (!user?.sub) throw createError({ statusCode: 401, statusMessage: "Not authenticated" });
  const { conversation_id } = await readValidatedBody(event, bodySchema.parse);

  const allowed = await (await serverSupabaseClient(event)).rpc("has_permission", { p_module: "crm_chats", p_action: "create_contact" });
  if (!allowed.data) throw createError({ statusCode: 403, statusMessage: "Not allowed" });

  const admin = serverSupabaseServiceRole(event);
  const { data: conv } = await admin.from("whatsapp_conversations").select("*").eq("id", conversation_id).maybeSingle();
  if (!conv) throw createError({ statusCode: 404, statusMessage: "Conversation not found" });
  if (conv.lead_id || conv.customer_id) throw createError({ statusCode: 409, statusMessage: "already_a_contact" });

  const result = await createLeadFromChat(event, admin, conv, null);
  await admin.from("whatsapp_conversations").update({ lead_id: result.id, status: "qualified", ai_paused: true }).eq("id", conv.id);
  return { status: result.status, id: result.id };
});
