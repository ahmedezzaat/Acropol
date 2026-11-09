// One call to the Claude Messages API. With `tool`, the answer is that tool's input (always the same
// shape); without it, the text. Used by the WhatsApp agent and by its learning from past chats.
export async function callClaude<T = string>(opts: {
  model: string;
  system: string;
  messages: { role: "user" | "assistant"; content: string }[];
  maxTokens?: number;
  tool?: { name: string; description: string; input_schema: Record<string, unknown> };
}): Promise<T> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw createError({ statusCode: 503, statusMessage: "ANTHROPIC_API_KEY is not set" });
  const res = await $fetch<{ content: { type: string; text?: string; name?: string; input?: unknown }[] }>("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": apiKey, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: {
      model: opts.model,
      max_tokens: opts.maxTokens ?? 1500,
      system: opts.system,
      messages: opts.messages,
      ...(opts.tool ? { tools: [opts.tool], tool_choice: { type: "tool", name: opts.tool.name } } : {}),
    },
    timeout: 55_000,
  });
  if (opts.tool) {
    const block = res.content.find((c) => c.type === "tool_use" && c.name === opts.tool!.name);
    if (!block?.input) throw createError({ statusCode: 502, statusMessage: "The assistant gave no answer" });
    return block.input as T;
  }
  return res.content.filter((c) => c.type === "text").map((c) => c.text ?? "").join("\n").trim() as T;
}

// The API wants alternating turns: join consecutive messages of the same side.
export function alternate(history: { role: "user" | "assistant"; text: string }[]) {
  const messages: { role: "user" | "assistant"; content: string }[] = [];
  for (const m of history) {
    const last = messages[messages.length - 1];
    if (last && last.role === m.role) last.content += `\n${m.text}`;
    else messages.push({ role: m.role, content: m.text });
  }
  if (!messages.length || messages[0]!.role !== "user") messages.unshift({ role: "user", content: "(the person started the chat)" });
  return messages;
}
