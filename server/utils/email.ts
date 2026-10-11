import type { H3Event } from "h3";

export interface EmailResult {
  ok: boolean;
  reason?: "not_configured" | "failed";
  detail?: string;
}

// The email service settings: entered in Settings -> Notification emails (stored
// in app_secrets), with the environment as a fallback.
export async function getEmailConfig(event: H3Event) {
  const stored = await readSecrets(event, ["resend_api_key", "email_from"]);
  const env = useRuntimeConfig(event).email;
  const apiKey = stored.get("resend_api_key") || env.resendApiKey || "";
  const from = stored.get("email_from") || env.from || "";
  return {
    apiKey,
    from,
    keySource: stored.get("resend_api_key") ? ("settings" as const) : env.resendApiKey ? ("env" as const) : null,
    fromSource: stored.get("email_from") ? ("settings" as const) : env.from ? ("env" as const) : null,
  };
}

// Sends one email through Resend. When the service isn't set up (no key / from
// address in the environment) nothing is sent and the caller is told, so the
// app keeps working before email is switched on.
export async function sendEmail(event: H3Event, message: { to: string; subject: string; html: string }): Promise<EmailResult> {
  const { apiKey: resendApiKey, from } = await getEmailConfig(event);
  if (!resendApiKey || !from) return { ok: false, reason: "not_configured" };

  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${resendApiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from, to: [message.to], subject: message.subject, html: message.html }),
    });
    if (!res.ok) {
      return { ok: false, reason: "failed", detail: `${res.status} ${await res.text().catch(() => "")}`.slice(0, 300) };
    }
    return { ok: true };
  } catch (err) {
    return { ok: false, reason: "failed", detail: err instanceof Error ? err.message : String(err) };
  }
}

export function escapeHtml(value: unknown) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
