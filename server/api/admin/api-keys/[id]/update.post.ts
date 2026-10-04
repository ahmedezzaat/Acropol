import * as z from "zod";

const bodySchema = z.object({
  name: z.string().trim().min(1).max(100).optional(),
  is_active: z.boolean().optional(),
  default_assignee_id: z.uuid().nullable().optional(),
});

export default defineEventHandler(async (event) => {
  const { adminClient } = await requireAdmin(event);
  const id = getRouterParam(event, "id");
  if (!id) throw createError({ statusCode: 400, statusMessage: "Missing key id" });
  const body = await readValidatedBody(event, bodySchema.parse);

  const { error } = await adminClient.from("api_keys").update(body).eq("id", id);
  if (error) throw createError({ statusCode: 500, statusMessage: error.message });
  return { ok: true };
});
