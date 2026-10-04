import { createHash, randomBytes } from "node:crypto";
import type { H3Event } from "h3";
import { serverSupabaseServiceRole } from "#supabase/server";

export function hashApiKey(key: string) {
  return createHash("sha256").update(key).digest("hex");
}

// Keys look like "acr_" + 32 url-safe chars. Only the hash is stored; the
// prefix (first 8 chars) is kept so admins can tell keys apart in the list.
export function generateApiKey() {
  const key = `acr_${randomBytes(24).toString("base64url")}`;
  return { key, prefix: key.slice(0, 8), hash: hashApiKey(key) };
}

// Accepts "Authorization: Bearer <key>" or "X-API-Key: <key>".
export async function requireApiKey(event: H3Event) {
  const header = getHeader(event, "authorization");
  const key = header?.toLowerCase().startsWith("bearer ")
    ? header.slice(7).trim()
    : getHeader(event, "x-api-key")?.trim();

  if (!key) {
    throw createError({ statusCode: 401, statusMessage: "Missing API key" });
  }

  const adminClient = serverSupabaseServiceRole(event);
  const { data: apiKey } = await adminClient
    .from("api_keys")
    .select("id, name, default_assignee_id, is_active")
    .eq("key_hash", hashApiKey(key))
    .maybeSingle();

  if (!apiKey || !apiKey.is_active) {
    throw createError({ statusCode: 401, statusMessage: "Invalid or revoked API key" });
  }

  // Best-effort usage stamp — never blocks or fails the request.
  adminClient
    .from("api_keys")
    .update({ last_used_at: new Date().toISOString() })
    .eq("id", apiKey.id)
    .then(() => {}, () => {});

  return { apiKey, adminClient };
}
