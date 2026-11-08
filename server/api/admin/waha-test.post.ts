// "Test the connection": asks WAHA for the session and says how it is (WORKING, SCAN_QR_CODE, STOPPED ...).
export default defineEventHandler(async (event) => {
  await requireSetting(event, "integrations");
  const c = await getWahaConfig(event);
  const session = await wahaFetch<{ name?: string; status?: string; me?: { id?: string; pushName?: string } }>(event, `/api/sessions/${encodeURIComponent(c.session)}`);
  return { name: session.name ?? c.session, status: session.status ?? "unknown", number: session.me?.id?.split("@")[0] ?? null, pushName: session.me?.pushName ?? null };
});
