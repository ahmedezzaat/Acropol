// Meta's webhook verification handshake: when you register the callback URL
// in the WhatsApp app dashboard, Meta calls it once with hub.* query params
// and expects the challenge echoed back if the verify token matches.
export default defineEventHandler(async (event) => {
  const query = getQuery(event);
  const { verifyToken } = await getWhatsappConfig(event);

  if (
    verifyToken &&
    query["hub.mode"] === "subscribe" &&
    query["hub.verify_token"] === verifyToken &&
    typeof query["hub.challenge"] === "string"
  ) {
    setResponseHeader(event, "content-type", "text/plain");
    return query["hub.challenge"];
  }

  throw createError({ statusCode: 403, statusMessage: "Verification failed" });
});
