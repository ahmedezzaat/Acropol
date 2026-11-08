// "Connect the number": creates the WAHA session if it is not there, points its webhook at this app, and starts
// it, so WAHA shows a QR code to scan. Nothing is removed from an existing session.
export default defineEventHandler(async (event) => {
  const { userId } = await requireSetting(event, "integrations");
  const c = await getWahaConfig(event);
  const webhook = wahaWebhookConfig(getRequestURL(event).origin, await ensureWahaWebhookKeys(event, userId));
  // the NOWEB store lets WAHA turn a privacy id (LID) into the real number
  const config = { webhooks: [webhook], noweb: { store: { enabled: true, fullSync: false } } };

  const existing = await getWahaSession(event);
  if (!existing) {
    await wahaFetch(event, "/api/sessions", { method: "POST", body: { name: c.session, start: true, config } });
  } else {
    // an existing session keeps its settings, except that the webhook is set (best effort)
    if (existing.status !== "WORKING") {
      try {
        await wahaFetch(event, `/api/sessions/${encodeURIComponent(c.session)}`, { method: "PUT", body: { name: c.session, config } });
      } catch {
        /* an older WAHA may not allow it: the webhook can still be pasted by hand */
      }
    }
    if (existing.status === "STOPPED" || existing.status === "FAILED") {
      await wahaFetch(event, `/api/sessions/${encodeURIComponent(c.session)}/start`, { method: "POST" });
    }
  }
  return { ok: true, webhook: "set" };
});
