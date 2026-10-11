import * as z from "zod";

const bodySchema = z.object({
  // A new key; leave out (or empty) to keep the saved one.
  api_key: z.string().trim().max(300).optional(),
  clear_key: z.boolean().optional(),
  from: z.string().trim().max(200).optional(),
});

export default defineEventHandler(async (event) => {
  const { userId } = await requireSetting(event, "notification_emails");
  const body = await readValidatedBody(event, bodySchema.parse);

  if (body.clear_key) {
    await deleteSecret(event, "resend_api_key");
  } else if (body.api_key) {
    await saveSecret(event, userId, "resend_api_key", body.api_key);
  }

  if (body.from !== undefined) {
    if (body.from) await saveSecret(event, userId, "email_from", body.from);
    else await deleteSecret(event, "email_from");
  }

  return { ok: true };
});
