import type { H3Event } from "h3";
import { serverSupabaseServiceRole } from "#supabase/server";

// Settings saved from the Settings pages (table app_secrets), read on the
// server only. Anything not saved there falls back to the environment, so an
// existing setup keeps working.
export async function readSecrets(event: H3Event, keys: string[]) {
  const { data } = await serverSupabaseServiceRole(event).from("app_secrets").select("key, value").in("key", keys);
  return new Map((data ?? []).map((r) => [r.key as string, r.value as string]));
}

export async function saveSecret(event: H3Event, userId: string, key: string, value: string) {
  const { error } = await serverSupabaseServiceRole(event)
    .from("app_secrets")
    .upsert({ key, value, updated_at: new Date().toISOString(), updated_by: userId }, { onConflict: "key" });
  if (error) throw createError({ statusCode: 500, statusMessage: error.message });
}

export async function deleteSecret(event: H3Event, key: string) {
  await serverSupabaseServiceRole(event).from("app_secrets").delete().eq("key", key);
}

// The WhatsApp webhook settings: entered in Settings -> Integrations, with the
// environment as a fallback.
export async function getWhatsappConfig(event: H3Event) {
  const stored = await readSecrets(event, ["whatsapp_verify_token", "whatsapp_app_secret", "whatsapp_default_assignee_id"]);
  const env = useRuntimeConfig(event).whatsapp;
  return {
    verifyToken: stored.get("whatsapp_verify_token") || env.verifyToken || "",
    appSecret: stored.get("whatsapp_app_secret") || env.appSecret || "",
    defaultAssigneeId: stored.get("whatsapp_default_assignee_id") || env.defaultAssigneeId || "",
    sources: {
      verifyToken: stored.get("whatsapp_verify_token") ? ("settings" as const) : env.verifyToken ? ("env" as const) : null,
      appSecret: stored.get("whatsapp_app_secret") ? ("settings" as const) : env.appSecret ? ("env" as const) : null,
      defaultAssigneeId: stored.get("whatsapp_default_assignee_id") ? ("settings" as const) : env.defaultAssigneeId ? ("env" as const) : null,
    },
  };
}
