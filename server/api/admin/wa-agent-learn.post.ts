import * as z from "zod";
import { serverSupabaseServiceRole } from "#supabase/server";

// "Learn from my chats": the agent's playbook is built from the WhatsApp chats already on the phone, in three
// short steps so each fits in one request:
//   list   -> the private chats WAHA knows, and which are not learned yet
//   digest -> a few chats at a time: Claude writes short notes on each (what was asked, what the team answered)
//   build  -> all the notes become one playbook (tone, common questions and answers, the usual flow)
const bodySchema = z.object({
  step: z.enum(["list", "digest", "build"]),
  chatIds: z.array(z.string().max(80)).max(4).optional(),
  relearn: z.boolean().optional(),
});

interface WahaMsg { fromMe?: boolean; body?: string; timestamp?: number; hasMedia?: boolean }

// phone numbers do not go to the model
const mask = (t: string) => t.replace(/\+?\d[\d\s-]{7,}\d/g, "[رقم]");

export default defineEventHandler(async (event) => {
  await requireSetting(event, "whatsapp_ai");
  const { step, chatIds, relearn } = await readValidatedBody(event, bodySchema.parse);
  const admin = serverSupabaseServiceRole(event);
  const { data: s } = await admin.from("whatsapp_ai_settings").select("model, business_description").eq("id", 1).single();
  const model = s?.model || "claude-sonnet-5-5";
  const { session } = await getWahaConfig(event);
  const enc = encodeURIComponent(session);

  if (step === "list") {
    let overview: any[] = [];
    try {
      overview = await wahaFetch<any[]>(event, `/api/${enc}/chats/overview?limit=200`);
    } catch {
      overview = await wahaFetch<any[]>(event, `/api/${enc}/chats?limit=200`);
    }
    const chats = (Array.isArray(overview) ? overview : [])
      .map((c) => ({ id: typeof c?.id === "string" ? c.id : (c?.id?._serialized as string | undefined) ?? "", name: String(c?.name ?? "") }))
      .filter((c) => c.id && !c.id.endsWith("@g.us") && !c.id.startsWith("status@") && !c.id.includes("broadcast"));
    if (relearn) await admin.from("wa_agent_notes").delete().neq("chat_id", "");
    const { data: done } = await admin.from("wa_agent_notes").select("chat_id");
    const have = new Set((done ?? []).map((d) => d.chat_id as string));
    return { total: chats.length, pending: chats.filter((c) => !have.has(c.id)).map((c) => c.id), learned: have.size };
  }

  if (step === "digest") {
    const results = await Promise.all(
      (chatIds ?? []).map(async (id) => {
        try {
          const msgs = await wahaFetch<WahaMsg[]>(event, `/api/${enc}/chats/${encodeURIComponent(id)}/messages?limit=120&downloadMedia=false`);
          const lines = (Array.isArray(msgs) ? msgs : [])
            .filter((m) => typeof m.body === "string" && m.body.trim())
            .sort((a, b) => (a.timestamp ?? 0) - (b.timestamp ?? 0))
            .map((m) => `${m.fromMe ? "الفريق" : "العميل"}: ${mask(m.body!.trim()).slice(0, 600)}`);
          const hasTeam = lines.some((l) => l.startsWith("الفريق"));
          // too short to teach anything: remembered as empty so it is not fetched again
          if (lines.length < 4 || !hasTeam) {
            await admin.from("wa_agent_notes").upsert({ chat_id: id, notes: "", messages: lines.length });
            return false;
          }
          const notes = await callClaude<string>({
            model,
            maxTokens: 500,
            system:
              "You read one WhatsApp chat between a company's team (الفريق) and a customer (العميل). Write SHORT notes in Arabic (max 150 words), only facts that are in the chat: " +
              "what the customer asked for; the questions they asked and the team's exact answers (including prices, conditions, timings, areas exactly as the team stated them); " +
              "how the team talks (tone, wording, greeting, closing); what the next step or outcome was (visit booked, quote sent, lost, ...). No names, no phone numbers.",
            messages: [{ role: "user", content: lines.join("\n").slice(0, 14_000) }],
          });
          await admin.from("wa_agent_notes").upsert({ chat_id: id, notes: notes.slice(0, 2000), messages: lines.length });
          return true;
        } catch (err) {
          console.error("[wa-agent-learn] a chat could not be read", id, err);
          return false;
        }
      }),
    );
    const { count } = await admin.from("wa_agent_notes").select("chat_id", { count: "exact", head: true }).neq("notes", "");
    return { read: results.filter(Boolean).length, learned: count ?? 0 };
  }

  // build
  const { data: notes } = await admin.from("wa_agent_notes").select("notes").neq("notes", "").order("created_at", { ascending: false }).limit(250);
  if (!notes?.length) throw createError({ statusCode: 409, statusMessage: "No chats were learned yet" });
  const playbook = await callClaude<string>({
    model,
    maxTokens: 3500,
    system:
      "You write the PLAYBOOK for a WhatsApp sales assistant of this company, from notes on its real chats. Write in Arabic, as clear sections with short bullets:\n" +
      "1) نبرة الفريق وأسلوبه (greeting, wording, length, emojis or not, with 3-5 real example sentences)\n" +
      "2) الأسئلة الشائعة وإجابات الفريق (each question with the answer the team actually gave; keep prices, conditions and timings only where the notes agree; mark disagreements 'يؤكدها الفريق')\n" +
      "3) مسار المحادثة المعتاد (what is asked first, what details are collected, when a visit or quote is offered)\n" +
      "4) متى يتحول الأمر لموظف (complaints, existing orders, special requests)\n" +
      "5) اعتراضات العملاء الشائعة وكيف يرد الفريق.\n" +
      "Use only what the notes support. Never invent prices or policies. No customer names or numbers.\n\nCompany: " + (s?.business_description || "-"),
    messages: [{ role: "user", content: notes.map((n, i) => `#${i + 1}\n${n.notes}`).join("\n\n").slice(0, 90_000) }],
  });
  await admin.from("whatsapp_ai_settings").update({ playbook, playbook_built_at: new Date().toISOString() }).eq("id", 1);
  return { built: true, from: notes.length };
});
