// What the Settings page shows about the email service. The key itself is never
// sent back to the browser, only whether one is set and its last characters.
export default defineEventHandler(async (event) => {
  await requireSetting(event, "notification_emails");
  const config = await getEmailConfig(event);
  return {
    hasKey: !!config.apiKey,
    keyHint: config.apiKey ? config.apiKey.slice(-4) : null,
    keySource: config.keySource,
    from: config.from,
    fromSource: config.fromSource,
  };
});
