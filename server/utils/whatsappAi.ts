// The assistant that chats with a stranger on WhatsApp and finds out what they need before any
// contact is created. It uses the Claude API (Messages) with one forced tool, so the answer always
// has the same shape: the reply to send, what was learned, and what to do next.
export interface QualifierInput {
  model: string;
  businessDescription: string;
  // the details that must be known before the chat counts as qualified
  required: { need: boolean; area: boolean; timing: boolean; budget: boolean };
  collected: Record<string, string>;
  areas: string[];
  categories: string[];
  // notes the company wrote for each product category (may be empty)
  productNotes?: string;
  history: { role: "user" | "assistant"; text: string }[];
}
export interface QualifierOutput {
  reply: string;
  collected: Record<string, string>;
  decision: "continue" | "qualified" | "handover" | "not_a_lead";
}

function systemPrompt(i: QualifierInput) {
  const want = [
    i.required.need && "need: what the person needs (the product or service, e.g. a heater, solar, maintenance)",
    i.required.area && "area: where the work is (the city or neighbourhood)",
    i.required.timing && "timing: when they want it",
    i.required.budget && "budget: a rough budget, if they are willing to share it",
  ].filter(Boolean);
  return `You are the WhatsApp assistant of a company. A person you do not know has just written to the company's number.
Your only job is to find out, in a short friendly chat, what they need, so a colleague can follow up. Do not sell, do not negotiate.

About the company:
${i.businessDescription || "(no description set)"}
Products and services it offers: ${i.categories.join("، ") || "not listed"}.
Areas it serves: ${i.areas.join("، ") || "not listed"}.
${i.productNotes ? `\nProduct notes written by the company (you may use these facts if the person asks about a product):\n${i.productNotes}\n` : ""}
Find out these details, one or two questions at a time, never a long list:
${want.map((w) => `- ${w}`).join("\n") || "- (nothing required: just greet them and ask how you can help)"}

Already known: ${JSON.stringify(i.collected)}

Rules:
- Reply in the language the person writes in (usually Arabic, colloquial and polite). Keep each reply to 1-3 short sentences.
- Never promise or quote prices, discounts, delivery dates or technical guarantees. If asked, say a colleague will confirm.
- If they ask for a person, are upset, ask about an existing order or a complaint, or ask something you cannot answer from the above, set decision to "handover".
- If what they write has nothing to do with the company (spam, wrong number, a general question), set decision to "not_a_lead" and reply politely.
- Set decision to "qualified" only when every required detail above is known (from "Already known" or this message). Then thank them and say a colleague will contact them soon.
- Otherwise decision is "continue". Put every detail you learn into "collected" (short text values; also "name" if they give their name).
You must answer by calling the respond tool.`;
}

export async function runQualifier(input: QualifierInput): Promise<QualifierOutput> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw createError({ statusCode: 503, statusMessage: "ANTHROPIC_API_KEY is not set" });

  // the API wants alternating turns: join consecutive messages of the same side
  const messages: { role: "user" | "assistant"; content: string }[] = [];
  for (const m of input.history) {
    const last = messages[messages.length - 1];
    if (last && last.role === m.role) last.content += `\n${m.text}`;
    else messages.push({ role: m.role, content: m.text });
  }
  if (!messages.length || messages[0]!.role !== "user") messages.unshift({ role: "user", content: "(the person started the chat)" });

  const res = await $fetch<{ content: { type: string; name?: string; input?: any }[] }>("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": apiKey, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: {
      model: input.model,
      max_tokens: 700,
      system: systemPrompt(input),
      messages,
      tools: [
        {
          name: "respond",
          description: "The reply to send to the person, what was learned, and what happens next.",
          input_schema: {
            type: "object",
            properties: {
              reply: { type: "string", description: "The WhatsApp message to send." },
              collected: {
                type: "object",
                description: "Details learned so far (name, need, area, timing, budget).",
                properties: { name: { type: "string" }, need: { type: "string" }, area: { type: "string" }, timing: { type: "string" }, budget: { type: "string" } },
              },
              decision: { type: "string", enum: ["continue", "qualified", "handover", "not_a_lead"] },
            },
            required: ["reply", "decision"],
          },
        },
      ],
      tool_choice: { type: "tool", name: "respond" },
    },
  });
  const block = res.content.find((c) => c.type === "tool_use" && c.name === "respond");
  const out = block?.input as Partial<QualifierOutput> | undefined;
  if (!out?.reply) throw createError({ statusCode: 502, statusMessage: "The assistant gave no reply" });
  const collected: Record<string, string> = {};
  for (const [k, v] of Object.entries(out.collected ?? {})) if (typeof v === "string" && v.trim()) collected[k] = v.trim();
  return { reply: out.reply.trim(), collected, decision: out.decision ?? "continue" };
}
