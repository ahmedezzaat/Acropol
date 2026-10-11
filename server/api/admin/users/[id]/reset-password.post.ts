import * as z from "zod";

const bodySchema = z.object({
  password: z.string().min(8),
});

export default defineEventHandler(async (event) => {
  const { userId, isAdmin, adminClient } = await requireSetting(event, "users");
  const id = getRouterParam(event, "id");
  if (!id) throw createError({ statusCode: 400, statusMessage: "Missing user id" });
  await guardNonAdmin(adminClient, isAdmin, userId, id);

  const body = await readValidatedBody(event, bodySchema.parse);

  const { error } = await adminClient.auth.admin.updateUserById(id, {
    password: body.password,
  });

  if (error) {
    throw createError({ statusCode: 400, statusMessage: error.message });
  }

  return { success: true };
});
