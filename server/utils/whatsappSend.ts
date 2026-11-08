import type { SupabaseClient } from "@supabase/supabase-js";

// Sends a text message from a connected WhatsApp number (Cloud API). Inside the 24 hours after the
// customer's last message a free-text reply is allowed; outside it Meta needs an approved template.
export async function sendWhatsAppText(admin: SupabaseClient, phoneNumberId: string, to: string, body: string): Promise<string | null> {
  const { data: connection } = await admin.from("whatsapp_connections").select("access_token").eq("phone_number_id", phoneNumberId).maybeSingle();
  if (!connection?.access_token) {
    throw createError({ statusCode: 400, statusMessage: "This WhatsApp number is not connected" });
  }
  try {
    const res = await $fetch<{ messages?: { id: string }[] }>(graphUrl(`${phoneNumberId}/messages`), {
      method: "POST",
      headers: { Authorization: `Bearer ${connection.access_token}` },
      body: { messaging_product: "whatsapp", to, type: "text", text: { body, preview_url: false } },
    });
    return res.messages?.[0]?.id ?? null;
  } catch (err: any) {
    const reason = err?.data?.error?.message ?? err?.message ?? "Sending failed";
    throw createError({ statusCode: 502, statusMessage: `Meta: ${reason}` });
  }
}
