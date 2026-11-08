import type { H3Event } from "h3";

// The WAHA (self-hosted WhatsApp HTTP API) connection: saved in Settings -> Integrations, with the
// environment as a fallback. The API key is write-only: it never goes back to the browser.
export async function getWahaConfig(event: H3Event) {
  const stored = await readSecrets(event, ["waha_url", "waha_api_key", "waha_session"]);
  return {
    url: (stored.get("waha_url") || process.env.WAHA_URL || "https://waha.sirmatechnology.com").replace(/\/+$/, ""),
    apiKey: stored.get("waha_api_key") || process.env.WAHA_API_KEY || "",
    session: stored.get("waha_session") || process.env.WAHA_SESSION || "default",
    sources: {
      apiKey: stored.get("waha_api_key") ? ("settings" as const) : process.env.WAHA_API_KEY ? ("env" as const) : null,
    },
  };
}

// A call to WAHA with the saved key. A failure becomes a readable error.
export async function wahaFetch<T>(event: H3Event, path: string, opts: { method?: "GET" | "POST"; body?: Record<string, unknown> } = {}): Promise<T> {
  const c = await getWahaConfig(event);
  if (!c.apiKey) throw createError({ statusCode: 400, statusMessage: "WAHA API key is not set (Settings -> Integrations)" });
  try {
    return await $fetch<T>(`${c.url}${path}`, {
      method: opts.method ?? "GET",
      headers: { "X-Api-Key": c.apiKey, Accept: "application/json" },
      body: opts.body,
      timeout: 20_000,
    });
  } catch (err: any) {
    const reason = err?.data?.message ?? err?.statusMessage ?? err?.message ?? "WAHA call failed";
    throw createError({ statusCode: 502, statusMessage: `WAHA: ${reason}` });
  }
}

// The message id WAHA gives back, whichever shape this version uses.
export function wahaMessageId(res: any): string | null {
  const id = res?.id ?? res?._data?.id;
  if (typeof id === "string") return id;
  return id?._serialized ?? null;
}

// Sends a text to a private chat (the number, digits only) from the session.
export async function sendWahaText(event: H3Event, session: string, waId: string, text: string): Promise<string | null> {
  const res = await wahaFetch<any>(event, "/api/sendText", { method: "POST", body: { session, chatId: `${waId}@c.us`, text } });
  return wahaMessageId(res);
}
