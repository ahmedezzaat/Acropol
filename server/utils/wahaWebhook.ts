import { createHmac, timingSafeEqual } from "node:crypto";
import type { H3Event } from "h3";
import { serverSupabaseServiceRole } from "#supabase/server";

// WAHA (https://waha.devlike.pro) webhook -> lead. See docs/waha-webhook.md.
//
//  - Only "message" events from a person create leads. Our own messages, groups,
//    status broadcasts and every other event type are acknowledged and ignored.
//  - Duplicates are decided by the database (api_create_lead: one advisory lock
//    per phone number, checked against every lead and customer), so two messages
//    arriving at the same instant, or WAHA retrying a delivery, never create two
//    leads.
//  - Authentication is driven by environment variables (never hardcoded):
//      WAHA_WEBHOOK_HMAC_KEY  verifies X-Webhook-Hmac over the RAW body
//      WAHA_WEBHOOK_SECRET    compared with the X-Webhook-Secret header
//    Every one that is set must pass. With neither set the endpoint still
//    accepts calls (development mode) and logs a warning.

const MAX_BODY_BYTES = 256 * 1024;
const MAX_NAME = 200;
const MAX_TEXT = 1000;
const HMAC_ALGORITHMS = new Set(["sha512", "sha256"]);

type Action = "created" | "duplicate" | "ignored";
const reply = (action: Action, extra: Record<string, unknown> = {}) => ({ ok: true, action, ...extra });

function safeEqual(a: string, b: string) {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
}

function hmacMatches(rawBody: string, key: string, header: string | undefined, algorithmHeader: string | undefined) {
  const algorithm = (algorithmHeader || "sha512").toLowerCase();
  if (!header || !HMAC_ALGORITHMS.has(algorithm)) return false;
  const received = Buffer.from(header.trim(), "hex");
  const expected = createHmac(algorithm, key).update(rawBody).digest();
  return received.length === expected.length && timingSafeEqual(received, expected);
}

// Strip control characters and collapse whitespace; the value is stored and
// shown later, so nothing from the sender is trusted.
function clean(value: unknown, max: number): string {
  if (typeof value !== "string") return "";
  // eslint-disable-next-line no-control-regex
  return value.replace(/[\u0000-\u001F\u007F-\u009F‎‏‪-‮]/g, " ").replace(/\s+/g, " ").trim().slice(0, max);
}

const digitsOf = (jid: unknown) => (typeof jid === "string" ? jid.split("@")[0]!.split(":")[0]!.replace(/\D/g, "") : "");
const validPhoneDigits = (d: string) => d.length >= 7 && d.length <= 15;

interface WahaPayload {
  from?: unknown;
  fromMe?: unknown;
  body?: unknown;
  hasMedia?: unknown;
  _data?: { notifyName?: unknown; pushName?: unknown; key?: { remoteJidAlt?: unknown; senderPn?: unknown } };
}

// Where is the real phone number? "<digits>@c.us" is the number itself; "@lid"
// is a privacy id, so look for the number WAHA may carry beside it.
function phoneFrom(payload: WahaPayload): { digits: string } | { skip: string } {
  const from = typeof payload.from === "string" ? payload.from : "";
  if (from.endsWith("@c.us") || from.endsWith("@s.whatsapp.net")) {
    const d = digitsOf(from);
    return validPhoneDigits(d) ? { digits: d } : { skip: "invalid_phone" };
  }
  if (from.endsWith("@lid")) {
    for (const candidate of [payload._data?.key?.remoteJidAlt, payload._data?.key?.senderPn]) {
      if (typeof candidate === "string" && /@(c\.us|s\.whatsapp\.net)$/.test(candidate)) {
        const d = digitsOf(candidate);
        if (validPhoneDigits(d)) return { digits: d };
      }
    }
    return { skip: "lid_without_number" };
  }
  return { skip: "unsupported_sender" };
}

export async function handleWaha(event: H3Event) {
  // ---- body: size limit, raw text kept for the signature
  const declared = Number(getHeader(event, "content-length") ?? 0);
  if (declared > MAX_BODY_BYTES) throw createError({ statusCode: 413, statusMessage: "Payload too large" });
  const rawBody = (await readRawBody(event)) ?? "";
  if (Buffer.byteLength(rawBody) > MAX_BODY_BYTES) throw createError({ statusCode: 413, statusMessage: "Payload too large" });

  // ---- authentication (every configured mechanism must pass)
  const hmacKey = process.env.WAHA_WEBHOOK_HMAC_KEY || "";
  const secret = process.env.WAHA_WEBHOOK_SECRET || "";
  if (!hmacKey && !secret) {
    console.warn("[waha-webhook] WAHA_WEBHOOK_HMAC_KEY / WAHA_WEBHOOK_SECRET are not set: accepting unauthenticated calls (development mode only)");
  }
  if (hmacKey && !hmacMatches(rawBody, hmacKey, getHeader(event, "x-webhook-hmac"), getHeader(event, "x-webhook-hmac-algorithm"))) {
    throw createError({ statusCode: 401, statusMessage: "Invalid signature" });
  }
  if (secret && !safeEqual(getHeader(event, "x-webhook-secret") ?? "", secret)) {
    throw createError({ statusCode: 401, statusMessage: "Invalid secret" });
  }

  // ---- parse
  let body: { event?: unknown; payload?: WahaPayload };
  try {
    body = JSON.parse(rawBody);
  } catch {
    throw createError({ statusCode: 400, statusMessage: "Invalid JSON" });
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw createError({ statusCode: 400, statusMessage: "Invalid body" });
  }

  // ---- what to ignore (answered 200 so WAHA does not retry)
  if (body.event !== "message") return reply("ignored", { reason: "event" });
  const payload = body.payload;
  if (!payload || typeof payload !== "object") throw createError({ statusCode: 400, statusMessage: "Missing payload" });
  if (payload.fromMe === true) return reply("ignored", { reason: "from_me" });
  const from = typeof payload.from === "string" ? payload.from : "";
  if (!from) throw createError({ statusCode: 400, statusMessage: "Missing sender" });
  if (from.endsWith("@g.us")) return reply("ignored", { reason: "group" });
  if (from.startsWith("status@") || from === "status@broadcast") return reply("ignored", { reason: "status" });

  const phone = phoneFrom(payload);
  if ("skip" in phone) {
    console.info(`[waha-webhook] skipped a message from ${from}: ${phone.skip}`);
    return reply("ignored", { reason: phone.skip });
  }

  // ---- the lead
  const text = clean(payload.body, MAX_TEXT);
  const first = text || (payload.hasMedia === true ? "[media]" : "[no text]");
  const e164 = `+${phone.digits}`;
  const name = clean(payload._data?.notifyName, MAX_NAME) || clean(payload._data?.pushName, MAX_NAME) || e164;

  const config = await getWhatsappConfig(event);
  const assignee = process.env.WAHA_DEFAULT_ASSIGNEE_ID || config.defaultAssigneeId || null;

  // A failure here becomes a 500, so WAHA retries; the database dedupes by phone.
  const result = await ingestLead(
    serverSupabaseServiceRole(event),
    { name, phone: e164, source: "whatsapp", notes: `First message: ${first}` },
    assignee,
  );
  return result.status === "created" ? reply("created", { id: result.id }) : reply("duplicate", { entity: result.entity, id: result.id });
}
