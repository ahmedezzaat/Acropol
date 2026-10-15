// Disconnects a number: stops the webhook for its business account when no other
// connected number uses it, and forgets the token.
export default defineEventHandler(async (event) => {
  const { adminClient } = await requireSetting(event, "integrations");
  const id = getRouterParam(event, "id");
  if (!id) throw createError({ statusCode: 400, statusMessage: "Missing id" });

  const { data: row } = await adminClient.from("whatsapp_connections").select("id, waba_id, access_token").eq("id", id).maybeSingle();
  if (!row) throw createError({ statusCode: 404, statusMessage: "Not found" });

  await adminClient.from("whatsapp_connections").delete().eq("id", id);

  const { count } = await adminClient.from("whatsapp_connections").select("id", { count: "exact", head: true }).eq("waba_id", row.waba_id);
  if (!count) {
    // best effort: the connection is already forgotten on our side
    try {
      await graph(`${row.waba_id}/subscribed_apps`, { method: "DELETE", token: row.access_token });
    } catch {
      /* the token may have been revoked by the business already */
    }
  }
  return { ok: true };
});
