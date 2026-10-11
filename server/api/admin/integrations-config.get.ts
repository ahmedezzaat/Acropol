// The WhatsApp webhook settings for the Integrations page. The app secret is
// never sent back, only whether it is set and its last characters.
export default defineEventHandler(async (event) => {
  await requireSetting(event, "integrations");
  const c = await getWhatsappConfig(event);
  return {
    verifyToken: c.verifyToken,
    hasAppSecret: !!c.appSecret,
    appSecretHint: c.appSecret ? c.appSecret.slice(-4) : null,
    defaultAssigneeId: c.defaultAssigneeId || null,
    sources: c.sources,
  };
});
