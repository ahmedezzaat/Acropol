// Sets the webhook of the WAHA session (this app's address, both events, signed with the key from the server's
// environment). For a number that is already connected: WAHA applies it to the running session.
export default defineEventHandler(async (event) => {
  await requireSetting(event, "integrations");
  const c = await getWahaConfig(event);
  const webhook = wahaWebhookConfig(getRequestURL(event).origin);
  if (!webhook) throw createError({ statusCode: 409, statusMessage: "webhook_key_missing" });
  if (!(await getWahaSession(event))) throw createError({ statusCode: 404, statusMessage: "session_missing" });
  await wahaFetch(event, `/api/sessions/${encodeURIComponent(c.session)}`, { method: "PUT", body: { name: c.session, config: { webhooks: [webhook] } } });
  return { ok: true };
});
