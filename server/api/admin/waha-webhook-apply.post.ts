// Sets the webhook of the WAHA session (this app's address, both events, signed with the key from the server's
// environment, or made by the app and saved on the server if there is none). For a number that is already
// connected: WAHA applies it to the running session.
export default defineEventHandler(async (event) => {
  const { userId } = await requireSetting(event, "integrations");
  const c = await getWahaConfig(event);
  const webhook = wahaWebhookConfig(getRequestURL(event).origin, await ensureWahaWebhookKeys(event, userId));
  if (!(await getWahaSession(event))) throw createError({ statusCode: 404, statusMessage: "session_missing" });
  await wahaFetch(event, `/api/sessions/${encodeURIComponent(c.session)}`, { method: "PUT", body: { name: c.session, config: { webhooks: [webhook], noweb: { store: { enabled: true, fullSync: false } } } } });
  return { ok: true };
});
