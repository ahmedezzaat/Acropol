// The state of the WAHA session: NOT_CREATED, STOPPED, STARTING, SCAN_QR_CODE, WORKING or FAILED, and the
// number linked to it once it works.
export default defineEventHandler(async (event) => {
  await requireSetting(event, "integrations");
  const s = await getWahaSession(event);
  return { status: s?.status ?? "NOT_CREATED", number: s?.me?.id?.split("@")[0] ?? null, pushName: s?.me?.pushName ?? null };
});
