// The QR code to scan, as an image (base64). It expires after about 20 seconds, so the page asks again.
export default defineEventHandler(async (event) => {
  await requireSetting(event, "integrations");
  const c = await getWahaConfig(event);
  const res = await wahaFetch<{ mimetype?: string; data?: string }>(event, `/api/${encodeURIComponent(c.session)}/auth/qr`, { accept: "application/json" });
  if (!res?.data) throw createError({ statusCode: 409, statusMessage: "No QR code right now" });
  return { mimetype: res.mimetype ?? "image/png", data: res.data };
});
