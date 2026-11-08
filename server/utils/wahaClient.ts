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

// Sends a text to a private chat from the session. The chat is a number (digits only) or a full WAHA chat id
// (a person whose number is hidden behind a privacy id is answered at "<id>@lid").
export async function sendWahaText(event: H3Event, session: string, waId: string, text: string, chatId?: string | null): Promise<string | null> {
  const res = await wahaFetch<any>(event, "/api/sendText", { method: "POST", body: { session, chatId: chatId || `${waId}@c.us`, text } });
  return wahaMessageId(res);
}

// The real number behind a privacy id ("<id>@lid"), when WAHA knows it (it needs the NOWEB store); else null.
export async function resolveWahaLid(event: H3Event, session: string, lidJid: string): Promise<string | null> {
  for (const lid of [lidJid, lidJid.split("@")[0]!]) {
    try {
      const r = await wahaFetch<{ pn?: string | null }>(event, `/api/${encodeURIComponent(session)}/lids/${encodeURIComponent(lid)}`);
      const digits = typeof r?.pn === "string" ? r.pn.split("@")[0]!.replace(/\D/g, "") : "";
      if (digits.length >= 7 && digits.length <= 15) return digits;
    } catch {
      /* not known (or the store is off): try the next spelling */
    }
  }
  return null;
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

// The key (and/or secret) a WAHA webhook is signed with. The environment wins (WAHA_WEBHOOK_HMAC_KEY /
// WAHA_WEBHOOK_SECRET); otherwise the key Acropol made for itself and saved in Settings.
export async function getWahaWebhookKeys(event: H3Event) {
  const hmacKey = process.env.WAHA_WEBHOOK_HMAC_KEY || "";
  const secret = process.env.WAHA_WEBHOOK_SECRET || "";
  if (hmacKey || secret) return { hmacKey, secret };
  const stored = await readSecrets(event, ["waha_webhook_key"]);
  return { hmacKey: stored.get("waha_webhook_key") ?? "", secret: "" };
}

// The same, made and saved when there is none yet (when the webhook is being set up).
export async function ensureWahaWebhookKeys(event: H3Event, userId: string) {
  const keys = await getWahaWebhookKeys(event);
  if (keys.hmacKey || keys.secret) return keys;
  const { randomBytes } = await import("node:crypto");
  const key = randomBytes(32).toString("hex");
  await saveSecret(event, userId, "waha_webhook_key", key);
  return { hmacKey: key, secret: "" };
}

// What WAHA calls when a message arrives: this app's webhook, signed with the key the app checks.
export function wahaWebhookConfig(origin: string, keys: { hmacKey: string; secret: string }) {
  return {
    url: `${origin}/api/webhooks/whatsapp`,
    events: ["message", "message.any"],
    ...(keys.hmacKey ? { hmac: { key: keys.hmacKey } } : {}),
    ...(keys.secret ? { customHeaders: [{ name: "X-Webhook-Secret", value: keys.secret }] } : {}),
  };
}
