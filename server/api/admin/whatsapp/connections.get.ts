// The connected WhatsApp numbers (never the access token).
export default defineEventHandler(async (event) => {
  const { adminClient } = await requireSetting(event, "integrations");
  const { data, error } = await adminClient
    .from("whatsapp_connections")
    .select("id, waba_id, phone_number_id, display_phone_number, verified_name, coexistence, subscribed, connected_at")
    .order("connected_at", { ascending: false });
  if (error) throw createError({ statusCode: 500, statusMessage: error.message });
  return data;
});
