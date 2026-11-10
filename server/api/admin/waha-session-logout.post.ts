// Unlinks the number from WAHA (it can be connected again with a new QR code). The session's settings are set
// again right here, so the next scan links with the full chat history (WhatsApp sends the old messages only
// when a number is linked) and with the webhook pointed at this app.
export default defineEventHandler(async (event) => {
  const { userId } = await requireSetting(event, "integrations");
  const c = await getWahaConfig(event);
  const name = encodeURIComponent(c.session);
  await wahaFetch(event, `/api/sessions/${name}/logout`, { method: "POST" });

  let configured = false;
  let configError: string | null = null;
  try {
    const webhook = wahaWebhookConfig(publicOrigin(event), await ensureWahaWebhookKeys(event, userId));
    await wahaFetch(event, `/api/sessions/${name}`, {
      method: "PUT",
      body: { name: c.session, config: { webhooks: [webhook], noweb: { markOnline: true, store: { enabled: true, fullSync: true } } } },
    });
    configured = true;
  } catch (err: any) {
    configError = String(err?.statusMessage ?? err?.message ?? "").slice(0, 200) || "unknown";
    console.error("[waha-logout] could not set the session config", err);
  }
  return { ok: true, configured, configError };
});
