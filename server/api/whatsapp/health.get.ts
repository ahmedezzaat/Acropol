import { serverSupabaseClient, serverSupabaseServiceRole, serverSupabaseUser } from "#supabase/server";

// Is the WhatsApp (WAHA) link healthy? Used by the inbox to warn when messages cannot arrive, and to tell an agent
// how the assistant is set (the settings table itself is only for people who manage the assistant).
export default defineEventHandler(async (event) => {
  const user = await serverSupabaseUser(event);
  if (!user?.sub) throw createError({ statusCode: 401, statusMessage: "Not authenticated" });
  const allowed = await (await serverSupabaseClient(event)).rpc("has_any_module_permission", { p_module: "crm_chats" });
  if (!allowed.data) throw createError({ statusCode: 403, statusMessage: "Not allowed" });

  const admin = serverSupabaseServiceRole(event);
  const [{ data: s }, { data: last }] = await Promise.all([
    admin.from("whatsapp_ai_settings").select("waha_mode, max_ai_replies").eq("id", 1).maybeSingle(),
    admin.from("whatsapp_conversations").select("last_inbound_at").eq("provider", "waha").not("last_inbound_at", "is", null).order("last_inbound_at", { ascending: false }).limit(1).maybeSingle(),
  ]);

  // the WAHA side: connected? does its webhook point to a public address of this app?
  let problem: "unreachable" | "no_session" | "not_working" | "wrong_webhook" | null = null;
  let status: string | null = null;
  const cfg = await getWahaConfig(event);
  if (cfg.apiKey) {
    try {
      const session = await getWahaSession(event);
      if (!session) problem = "no_session";
      else {
        status = session.status ?? null;
        const hooks = session.config?.webhooks ?? [];
        if (status !== "WORKING") problem = "not_working";
        else if (!hooks.some((h) => typeof h.url === "string" && h.url.startsWith("https://") && h.url.endsWith("/api/webhooks/whatsapp"))) problem = "wrong_webhook";
      }
    } catch {
      problem = "unreachable";
    }
  }
  return { configured: !!cfg.apiKey, problem, status, mode: (s?.waha_mode ?? "off") as "off" | "draft" | "auto", maxAiReplies: s?.max_ai_replies ?? 0, lastInboundAt: last?.last_inbound_at ?? null };
});
