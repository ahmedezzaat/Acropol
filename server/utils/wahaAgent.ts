import type { H3Event } from "h3";
import type { SupabaseClient } from "@supabase/supabase-js";

// The WhatsApp (WAHA) sales agent. For a message that just arrived it reads the chat, the playbook learned
// from past chats and what the company offers, and decides: the reply, what it learned about the person, and
// whether the chat is ready for a deal. In "draft" mode the reply waits for a person in the inbox; in "auto" mode it
// is sent. A deal is opened (once) when the chat is ready. Anything the agent cannot answer goes to a person.
interface AgentOut {
  reply: string;
  collected?: Record<string, string>;
  decision?: "continue" | "ready_for_deal" | "handover";
}

export async function runWahaAgent(event: H3Event, admin: SupabaseClient, conversationId: string) {
  const { data: s } = await admin.from("whatsapp_ai_settings").select("*").eq("id", 1).maybeSingle();
  if (!s || s.waha_mode === "off") return;
  const { data: conv } = await admin.from("whatsapp_conversations").select("*").eq("id", conversationId).maybeSingle();
  if (!conv || conv.provider !== "waha") return;
  // a person took the chat over (auto mode only: drafts are harmless)
  if (s.waha_mode === "auto" && conv.ai_paused) return;
  if (conv.ai_replies >= s.max_ai_replies && s.waha_mode === "auto") return;

  const [{ data: rows }, { data: areas }, { data: categories }] = await Promise.all([
    admin.from("whatsapp_messages").select("sender, body, created_at, direction").eq("conversation_id", conv.id).order("created_at", { ascending: false }).limit(30),
    admin.from("service_areas").select("name").order("sort_order"),
    admin.from("product_categories").select("name, ai_notes").order("sort_order"),
  ]);
  const history = (rows ?? []).reverse();
  // the agent answers a customer message: the chat must end with one
  if (!history.length || history[history.length - 1]!.direction !== "in") return;
  const lastAt = history[history.length - 1]!.created_at;

  const system = `You are the WhatsApp sales assistant of a company, chatting with a customer on the company's own number.
Reply exactly the way the team writes (see the playbook), in the customer's language (usually colloquial Arabic), 1-3 short sentences.

About the company:
${s.business_description || "(no description set)"}
Products and services: ${(categories ?? []).map((c) => c.name).join("، ") || "not listed"}.
Areas served: ${(areas ?? []).map((a) => a.name).join("، ") || "not listed"}.
${productNotesBlock(categories) ? `\nPRODUCT NOTES (written by the company for each product category; use these facts when the customer asks about them):\n${productNotesBlock(categories)}\n` : ""}
PLAYBOOK (learned from the team's real chats; follow its tone, answers and flow):
${s.playbook || "(empty: be polite and short, ask what the person needs)"}

Already known about this person: ${JSON.stringify(conv.collected ?? {})}
${conv.customer_id ? "This person is an EXISTING CUSTOMER." : conv.lead_id ? "This person is already a lead." : ""}

Rules:
- Answer only from the company description, the product notes and the playbook. Never invent prices, discounts, dates or guarantees: if the playbook has no answer, say a colleague will confirm and set decision "handover".
- Find out, one or two questions at a time: what they need, the area/location, when, and their name. Put everything learned in "collected" (name, need, area, timing, budget).
- decision "ready_for_deal" only when the need AND the area are known and the person wants to go ahead or asked for a visit/quote. Then tell them a colleague will contact them.
- decision "handover" for complaints, existing orders, anger, requests for a person, or anything you cannot answer.
- Otherwise decision "continue".
Answer by calling the respond tool.`;

  let out: AgentOut;
  try {
    out = await callClaude<AgentOut>({
      model: s.model,
      system,
      messages: alternate(history.map((r) => ({ role: r.direction === "in" ? "user" : "assistant", text: r.body ?? "" }))),
      maxTokens: 700,
      tool: {
        name: "respond",
        description: "The reply to send, what was learned, and what happens next.",
        input_schema: {
          type: "object",
          properties: {
            reply: { type: "string" },
            collected: { type: "object", properties: { name: { type: "string" }, need: { type: "string" }, area: { type: "string" }, timing: { type: "string" }, budget: { type: "string" } } },
            decision: { type: "string", enum: ["continue", "ready_for_deal", "handover"] },
          },
          required: ["reply", "decision"],
        },
      },
    });
  } catch (err) {
    console.error("[waha-agent] the model failed", err);
    return;
  }
  const reply = (out.reply ?? "").trim();
  if (!reply) return;

  // a newer customer message arrived while the model was thinking: that one will be answered instead
  const { data: newer } = await admin.from("whatsapp_messages").select("id").eq("conversation_id", conv.id).eq("direction", "in").gt("created_at", lastAt).limit(1);
  if (newer?.length) return;

  const collected = { ...(conv.collected ?? {}) } as Record<string, string>;
  for (const [k, v] of Object.entries(out.collected ?? {})) if (typeof v === "string" && v.trim()) collected[k] = v.trim();
  const decision = out.decision ?? "continue";
  const patch: Record<string, unknown> = { collected };

  if (s.waha_mode === "draft") {
    patch.ai_draft = reply;
    patch.ai_draft_at = new Date().toISOString();
  } else {
    try {
      const wamid = await sendWahaText(event, conv.phone_number_id, conv.wa_id, reply, conv.chat_id);
      await admin.from("whatsapp_messages").insert({ conversation_id: conv.id, direction: "out", sender: "ai", body: reply, wa_message_id: wamid });
      patch.ai_replies = conv.ai_replies + 1;
      patch.last_message_at = new Date().toISOString();
      patch.ai_draft = null;
    } catch (err) {
      console.error("[waha-agent] the reply did not go out", err);
      patch.ai_draft = reply;
      patch.ai_draft_at = new Date().toISOString();
    }
  }

  if (decision === "handover") {
    if (s.waha_mode === "auto") patch.ai_paused = true;
    patch.status = "handed_over";
  }
  await admin.from("whatsapp_conversations").update(patch).eq("id", conv.id);

  if (decision === "handover") await notifyAgentHandover(event, admin, conv.id, conv.display_name ?? `+${conv.wa_id}`);
  if (decision === "ready_for_deal" && !conv.ai_deal_id) await openDealFromChat(event, admin, { ...conv, collected }, s);
}

// The deal for a chat that is ready: not when the person already has one open. The chat's lead (made when the
// first message arrived) or customer owns it.
async function openDealFromChat(event: H3Event, admin: SupabaseClient, conv: any, s: any) {
  if (!conv.lead_id && !conv.customer_id) return;
  const ors = [conv.lead_id && `lead_id.eq.${conv.lead_id}`, conv.customer_id && `customer_id.eq.${conv.customer_id}`].filter(Boolean).join(",");
  const [{ data: deals }, { data: stages }] = await Promise.all([
    admin.from("deals").select("id, stage_id").or(ors),
    admin.from("pipeline_stages").select("id, pipeline_id, sort_order, is_closed"),
  ]);
  const open = (deals ?? []).find((d) => !(stages ?? []).find((x) => x.id === d.stage_id)?.is_closed);
  if (open) {
    await admin.from("whatsapp_conversations").update({ ai_deal_id: open.id }).eq("id", conv.id);
    return;
  }
  // where it goes: the pipeline/stage chosen in Settings, else the first stage of the first pipeline
  let pipelineId: string | null = s.deal_pipeline_id;
  let stageId: string | null = s.deal_stage_id;
  if (!pipelineId || !stageId) {
    const { data: p } = await admin.from("pipelines").select("id").order("sort_order").limit(1).maybeSingle();
    pipelineId = p?.id ?? null;
    stageId = (stages ?? []).filter((x) => x.pipeline_id === pipelineId && !x.is_closed).sort((a, b) => a.sort_order - b.sort_order)[0]?.id ?? null;
  }
  if (!pipelineId || !stageId) return;
  const { defaultAssigneeId } = await getWhatsappConfig(event);
  const assignee = process.env.WAHA_DEFAULT_ASSIGNEE_ID || defaultAssigneeId || null;
  if (!assignee) return;
  const c = conv.collected ?? {};
  const { data: deal, error } = await admin
    .from("deals")
    .insert({
      title: c.need || conv.display_name || `+${conv.wa_id}`,
      lead_id: conv.lead_id,
      customer_id: conv.customer_id,
      pipeline_id: pipelineId,
      stage_id: stageId,
      assigned_to: assignee,
      created_by: assignee,
    })
    .select("id")
    .single();
  if (error || !deal) {
    console.error("[waha-agent] could not open the deal", error?.message);
    return;
  }
  await admin.from("whatsapp_conversations").update({ ai_deal_id: deal.id, status: "qualified" }).eq("id", conv.id);
  // what the agent learned goes onto the lead
  if (conv.lead_id) {
    const lines = Object.entries(c).filter(([, v]) => v).map(([k, v]) => `${k}: ${v}`);
    const { data: lead } = await admin.from("leads").select("notes").eq("id", conv.lead_id).maybeSingle();
    await admin.from("leads").update({ notes: [lead?.notes, "— مساعد واتساب:", ...lines].filter(Boolean).join("\n") }).eq("id", conv.lead_id);
    if (c.area) {
      const { data: area } = await admin.from("service_areas").select("id").ilike("name", `%${c.area}%`).limit(1).maybeSingle();
      if (area) await admin.from("leads").update({ area_id: area.id }).eq("id", conv.lead_id).is("area_id", null);
    }
  }
}

async function notifyAgentHandover(event: H3Event, admin: SupabaseClient, conversationId: string, name: string) {
  const { defaultAssigneeId } = await getWhatsappConfig(event);
  if (!defaultAssigneeId) return;
  await admin.rpc("notify_user", { p_user: defaultAssigneeId, p_type: "chat_handover", p_params: { conversation_id: conversationId, name } });
}
