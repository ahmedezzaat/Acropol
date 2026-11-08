// The WAHA settings for the Integrations page. The API key is never sent back: only whether it is set
// and its last characters.
export default defineEventHandler(async (event) => {
  await requireSetting(event, "integrations");
  const c = await getWahaConfig(event);
  return { url: c.url, session: c.session, hasApiKey: !!c.apiKey, apiKeyHint: c.apiKey ? c.apiKey.slice(-4) : null, sources: c.sources };
});
