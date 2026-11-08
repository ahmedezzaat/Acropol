import * as z from "zod";

const bodySchema = z.object({
  url: z.string().trim().url().max(300).optional(),
  session: z.string().trim().min(1).max(80).optional(),
  // a new key; leave out (or empty) to keep the saved one
  api_key: z.string().trim().max(300).optional(),
  clear_api_key: z.boolean().optional(),
});

export default defineEventHandler(async (event) => {
  const { userId } = await requireSetting(event, "integrations");
  const body = await readValidatedBody(event, bodySchema.parse);
  if (body.url) await saveSecret(event, userId, "waha_url", body.url.replace(/\/+$/, ""));
  if (body.session) await saveSecret(event, userId, "waha_session", body.session);
  if (body.clear_api_key) await deleteSecret(event, "waha_api_key");
  else if (body.api_key) await saveSecret(event, userId, "waha_api_key", body.api_key);
  return { ok: true };
});
