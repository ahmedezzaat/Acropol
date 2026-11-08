// The last calls WAHA made to the app and what the app did with each (newest first).
export default defineEventHandler(async (event) => {
  const { adminClient } = await requireSetting(event, "integrations");
  const { data, error } = await adminClient.from("whatsapp_webhook_log").select("id, received_at, event, chat, from_me, outcome, detail").order("id", { ascending: false }).limit(15);
  if (error) return { rows: [], unavailable: true };
  return { rows: data ?? [], unavailable: false };
});
