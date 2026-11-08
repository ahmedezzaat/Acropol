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
export async function wahaFetch<T>(event: H3Event, path: string, opts: { method?: "GET" | "POST" | "PUT"; body?: Record<string, unknown>; accept?: string } = {}): Promise<T> {
  const c = await getWahaConfig(event);
  if (!c.apiKey) throw createError({ statusCode: 400, statusMessage: "WAHA API key is not set (Settings -> Integrations)" });
  try {
    return await $fetch<T>(`${c.url}${path}`, {
      method: opts.method ?? "GET",
      headers: { "X-Api-Key": c.apiKey, Accept: opts.accept ?? "application/json" },
      body: opts.body,
      timeout: 20_000,
    });
  } catch (err: any) {
    const reason = err?.data?.message ?? err?.statusMessage ?? err?.message ?? "WAHA call failed";
    // the status WAHA answered with travels along (404: no such session)
    throw createError({ statusCode: 502, statusMessage: `WAHA: ${reason}`, data: { upstreamStatus: err?.status ?? err?.statusCode ?? null } });
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

export interface WahaSession {
  name?: string;
  status?: string;
  me?: { id?: string; pushName?: string };
}

// The session as it is now; null when it does not exist yet.
export async function getWahaSession(event: H3Event): Promise<WahaSession | null> {
  const c = await getWahaConfig(event);
  try {
    return await wahaFetch<WahaSession>(event, `/api/sessions/${encodeURIComponent(c.session)}`);
  } catch (err: any) {
    if (err?.data?.upstreamStatus === 404) return null;
    throw err;
  }
}

// What WAHA calls when a message arrives: this app's webhook, signed with the key the app already checks.
// Without a key or secret set on the server the webhook would accept anyone, so it is not configured then.
export function wahaWebhookConfig(origin: string) {
  const hmacKey = process.env.WAHA_WEBHOOK_HMAC_KEY || "";
  const secret = process.env.WAHA_WEBHOOK_SECRET || "";
  if (!hmacKey && !secret) return null;
  return {
    url: `${origin}/api/webhooks/whatsapp`,
    events: ["message", "message.any"],
    ...(hmacKey ? { hmac: { key: hmacKey } } : {}),
    ...(secret ? { customHeaders: [{ name: "X-Webhook-Secret", value: secret }] } : {}),
  };
}
