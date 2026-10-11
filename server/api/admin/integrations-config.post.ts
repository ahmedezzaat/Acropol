import * as z from "zod";

const bodySchema = z.object({
  verify_token: z.string().trim().max(200).optional(),
  // A new secret; leave out (or empty) to keep the saved one.
  app_secret: z.string().trim().max(300).optional(),
  clear_app_secret: z.boolean().optional(),
  default_assignee_id: z.uuid().nullable().optional(),
});

export default defineEventHandler(async (event) => {
  const { userId } = await requireSetting(event, "integrations");
  const body = await readValidatedBody(event, bodySchema.parse);

  if (body.verify_token !== undefined) {
    if (body.verify_token) await saveSecret(event, userId, "whatsapp_verify_token", body.verify_token);
    else await deleteSecret(event, "whatsapp_verify_token");
  }
  if (body.clear_app_secret) await deleteSecret(event, "whatsapp_app_secret");
  else if (body.app_secret) await saveSecret(event, userId, "whatsapp_app_secret", body.app_secret);

  if (body.default_assignee_id !== undefined) {
    if (body.default_assignee_id) await saveSecret(event, userId, "whatsapp_default_assignee_id", body.default_assignee_id);
    else await deleteSecret(event, "whatsapp_default_assignee_id");
  }
  return { ok: true };
});
