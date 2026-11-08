// Unlinks the number from WAHA (it can be connected again with a new QR code).
export default defineEventHandler(async (event) => {
  await requireSetting(event, "integrations");
  const c = await getWahaConfig(event);
  await wahaFetch(event, `/api/sessions/${encodeURIComponent(c.session)}/logout`, { method: "POST" });
  return { ok: true };
});
