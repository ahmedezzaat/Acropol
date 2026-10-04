import { createHmac, timingSafeEqual } from "node:crypto";
import { serverSupabaseServiceRole } from "#supabase/server";

interface WhatsAppMessage {
  from: string;
  id: string;
  type: string;
  text?: { body?: string };
  image?: { caption?: string };
  video?: { caption?: string };
  document?: { caption?: string; filename?: string };
  button?: { text?: string };
  interactive?: { button_reply?: { title?: string }; list_reply?: { title?: string } };
}

interface WhatsAppValue {
  contacts?: Array<{ wa_id: string; profile?: { name?: string } }>;
  messages?: WhatsAppMessage[];
}

function verifySignature(rawBody: string, header: string | undefined, appSecret: string) {
  if (!header?.startsWith("sha256=")) return false;
  const expected = createHmac("sha256", appSecret).update(rawBody).digest();
  const received = Buffer.from(header.slice(7), "hex");
  return received.length === expected.length && timingSafeEqual(received, expected);
}

function messageText(m: WhatsAppMessage) {
  return (
    m.text?.body ??
    m.image?.caption ??
    m.video?.caption ??
    m.document?.caption ??
    m.button?.text ??
    m.interactive?.button_reply?.title ??
    m.interactive?.list_reply?.title ??
    null
  );
}

// WhatsApp Cloud API webhook. Every inbound message creates a lead for the
// sender — unless that phone number already belongs to a lead or customer,
// in which case nothing is created (same rule as creating one in the app).
// The request is authenticated by Meta's X-Hub-Signature-256 HMAC over the
// raw body, keyed with the app secret, so nobody else can post leads here.
export default defineEventHandler(async (event) => {
  const { appSecret, defaultAssigneeId } = useRuntimeConfig(event).whatsapp;
  if (!appSecret) {
    throw createError({ statusCode: 503, statusMessage: "WhatsApp webhook is not configured" });
  }

  const rawBody = (await readRawBody(event)) ?? "";
  if (!verifySignature(rawBody, getHeader(event, "x-hub-signature-256"), appSecret)) {
    throw createError({ statusCode: 401, statusMessage: "Invalid signature" });
  }

  let payload: { object?: string; entry?: Array<{ changes?: Array<{ value?: WhatsAppValue }> }> };
  try {
    payload = JSON.parse(rawBody);
  } catch {
    throw createError({ statusCode: 400, statusMessage: "Invalid JSON" });
  }
  if (payload.object !== "whatsapp_business_account") return { received: true };

  const adminClient = serverSupabaseServiceRole(event);
  const assignee = defaultAssigneeId || null;
  let created = 0;
  let duplicates = 0;

  for (const entry of payload.entry ?? []) {
    for (const change of entry.changes ?? []) {
      const value = change.value;
      // Delivery/read receipts arrive as "statuses" with no messages — ignored.
      for (const message of value?.messages ?? []) {
        const profileName = value?.contacts?.find((c) => c.wa_id === message.from)?.profile?.name?.trim();
        const text = messageText(message);

        // A failure throws -> 500 -> Meta retries the delivery. That is safe
        // because the database dedupes by phone number.
        const result = await ingestLead(
          adminClient,
          {
            name: profileName || `+${message.from}`,
            phone: `+${message.from}`,
            source: "whatsapp",
            notes: text ? `WhatsApp: ${text}` : `WhatsApp: [${message.type}]`,
          },
          assignee,
        );
        if (result.status === "created") created++;
        else duplicates++;
      }
    }
  }

  return { received: true, created, duplicates };
});
