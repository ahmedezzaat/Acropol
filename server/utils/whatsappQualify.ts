import type { H3Event } from "h3";
import type { SupabaseClient } from "@supabase/supabase-js";

interface Inbound {
  phoneNumberId: string;
  waId: string;
  name: string | null;
  wamid: string;
  text: string;
}

const REQUIRED_LABELS: Record<string, string> = { need: "المطلوب", area: "المنطقة", timing: "الموعد", budget: "الميزانية" };

// A message from a stranger on a connected number. When the assistant is on, it chats and asks what
// the person needs, and only a qualified chat becomes a lead. Returns false when the assistant is
// off, so the old behaviour (every new number becomes a lead) still applies.
export async function handleInboundChat(event: H3Event, admin: SupabaseClient, m: Inbound): Promise<boolean> {
  const { data: settings } = await admin.from("whatsapp_ai_settings").select("*").eq("id", 1).maybeSingle();
  if (!settings?.enabled) return false;

  // the conversation (one per number and customer)
  let { data: conv } = await admin
    .from("whatsapp_conversations")
    .select("*")
    .eq("phone_number_id", m.phoneNumberId)
    .eq("wa_id", m.waId)
    .maybeSingle();
  if (!conv) {
    const known = (await admin.rpc("whatsapp_known_contact", { p_digits: m.waId })).data as { entity: "lead" | "customer"; id: string } | null;
    const { data: created, error } = await admin
      .from("whatsapp_conversations")
      .insert({
        phone_number_id: m.phoneNumberId,
        wa_id: m.waId,
        display_name: m.name,
        // someone who is already a lead or customer is for the team, not for the assistant
        status: known ? "known" : "qualifying",
        lead_id: known?.entity === "lead" ? known.id : null,
        customer_id: known?.entity === "customer" ? known.id : null,
      })
      .select("*")
      .single();
    if (error || !created) throw createError({ statusCode: 500, statusMessage: error?.message ?? "Could not save the conversation" });
    conv = created;
  }

  // the message (a delivery Meta repeats is stored once)
  const { error: dupe } = await admin
    .from("whatsapp_messages")
    .insert({ conversation_id: conv.id, direction: "in", sender: "customer", body: m.text, wa_message_id: m.wamid });
  if (dupe) return true;
  await admin
    .from("whatsapp_conversations")
    .update({ last_inbound_at: new Date().toISOString(), last_message_at: new Date().toISOString(), unread: true, ...(m.name && !conv.display_name ? { display_name: m.name } : {}) })
    .eq("id", conv.id);

  if (conv.status !== "qualifying" || conv.ai_paused) return true;

  // ---- ask the assistant
  const [{ data: rows }, { data: areas }, { data: categories }] = await Promise.all([
    admin.from("whatsapp_messages").select("sender, body, created_at").eq("conversation_id", conv.id).order("created_at", { ascending: false }).limit(20),
    admin.from("service_areas").select("name").order("sort_order"),
    admin.from("product_categories").select("name").order("sort_order"),
  ]);
  const history = (rows ?? []).reverse().map((r) => ({ role: (r.sender === "customer" ? "user" : "assistant") as "user" | "assistant", text: r.body ?? "" }));
  const required = { need: settings.qualify_need, area: settings.qualify_area, timing: settings.qualify_timing, budget: settings.qualify_budget };

  let out;
  try {
    out = await runQualifier({
      model: settings.model,
      businessDescription: settings.business_description,
      required,
      collected: conv.collected ?? {},
      areas: [...new Set((areas ?? []).map((a) => a.name as string))],
      categories: (categories ?? []).map((c) => c.name as string),
      history,
    });
  } catch (err) {
    // the assistant failed: do not leave the person unanswered silently, let a person take over
    await admin.from("whatsapp_conversations").update({ status: "handed_over" }).eq("id", conv.id);
    await notifyHandover(event, admin, conv.id, conv.display_name ?? m.name ?? `+${m.waId}`);
    console.error("whatsapp assistant failed", err);
    return true;
  }

  const collected = { ...(conv.collected ?? {}), ...out.collected };
  const missing = (Object.keys(required) as (keyof typeof required)[]).filter((k) => required[k] && !collected[k]);
  let decision = out.decision;
  // "qualified" only counts when every required detail really is known
  if (decision === "qualified" && missing.length) decision = "continue";
  const replies = conv.ai_replies + 1;
  if (decision === "continue" && replies >= settings.max_ai_replies) decision = "handover";

  // what to say
  let reply = out.reply;
  if (decision === "handover" && !reply) reply = settings.handover_message;
  if (decision === "qualified" && !reply) reply = settings.done_message;

  let wamid: string | null;
  try {
    wamid = await sendWhatsAppText(admin, m.phoneNumberId, m.waId, reply);
  } catch (err) {
    // the reply did not go out: a person must see this chat (Meta repeats the delivery, which is stored once)
    await admin.from("whatsapp_conversations").update({ status: "handed_over", collected }).eq("id", conv.id);
    await notifyHandover(event, admin, conv.id, conv.display_name ?? m.name ?? `+${m.waId}`);
    console.error("whatsapp reply failed", err);
    return true;
  }
  await admin.from("whatsapp_messages").insert({ conversation_id: conv.id, direction: "out", sender: "ai", body: reply, wa_message_id: wamid });

  const patch: Record<string, unknown> = { collected, ai_replies: replies, last_message_at: new Date().toISOString() };
  if (decision === "not_a_lead") patch.status = "closed";
  if (decision === "handover") patch.status = "handed_over";
  if (decision === "qualified") {
    const lead = await createLeadFromChat(event, admin, { ...conv, collected }, m.name);
    patch.status = lead.status === "created" ? "qualified" : "known";
    patch.lead_id = lead.id;
  }
  await admin.from("whatsapp_conversations").update(patch).eq("id", conv.id);
  if (decision === "handover") await notifyHandover(event, admin, conv.id, conv.display_name ?? m.name ?? `+${m.waId}`);
  return true;
}

// A message the team sent from the phone app (Coexistence): kept in the chat, and the assistant stops
// answering that person.
export async function recordAgentEcho(admin: SupabaseClient, e: { phoneNumberId: string; waId: string; wamid: string; text: string }) {
  const { data: settings } = await admin.from("whatsapp_ai_settings").select("enabled").eq("id", 1).maybeSingle();
  if (!settings?.enabled) return;
  const { data: conv } = await admin
    .from("whatsapp_conversations")
    .upsert({ phone_number_id: e.phoneNumberId, wa_id: e.waId, ai_paused: true }, { onConflict: "phone_number_id,wa_id" })
    .select("id")
    .single();
  if (!conv) return;
  await admin.from("whatsapp_messages").insert({ conversation_id: conv.id, direction: "out", sender: "agent", body: e.text, wa_message_id: e.wamid });
  await admin.from("whatsapp_conversations").update({ last_message_at: new Date().toISOString() }).eq("id", conv.id);
}

// Turns a chat into a lead (qualified by the assistant, or made by an agent by hand).
export async function createLeadFromChat(event: H3Event, admin: SupabaseClient, conv: { wa_id: string; display_name: string | null; collected: Record<string, string> }, fallbackName: string | null) {
  const { defaultAssigneeId } = await getWhatsappConfig(event);
  const c = conv.collected ?? {};
  const lines = (Object.keys(REQUIRED_LABELS) as string[]).filter((k) => c[k]).map((k) => `${REQUIRED_LABELS[k]}: ${c[k]}`);
  const result = await ingestLead(
    admin,
    {
      name: c.name || conv.display_name || fallbackName || `+${conv.wa_id}`,
      phone: `+${conv.wa_id}`,
      source: "whatsapp",
      notes: ["محادثة واتساب (تم تأهيلها)", ...lines].join("\n"),
    },
    defaultAssigneeId || null,
  );
  // the area the person named, matched to the service areas
  if (result.status === "created" && c.area) {
    const { data: area } = await admin.from("service_areas").select("id").ilike("name", `%${c.area}%`).limit(1).maybeSingle();
    if (area) await admin.from("leads").update({ area_id: area.id }).eq("id", result.id);
  }
  return result;
}

async function notifyHandover(event: H3Event, admin: SupabaseClient, conversationId: string, name: string) {
  const { defaultAssigneeId } = await getWhatsappConfig(event);
  if (!defaultAssigneeId) return;
  await admin.rpc("notify_user", { p_user: defaultAssigneeId, p_type: "chat_handover", p_params: { conversation_id: conversationId, name } });
}
