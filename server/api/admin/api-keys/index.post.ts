import * as z from "zod";

const bodySchema = z.object({
  name: z.string().trim().min(1).max(100),
  default_assignee_id: z.uuid().nullable().optional(),
});

// Creates a key and returns the full secret ONCE — only its hash is stored,
// so it can never be shown again.
export default defineEventHandler(async (event) => {
  const { userId, adminClient } = await requireAdmin(event);
  const body = await readValidatedBody(event, bodySchema.parse);
  const { key, prefix, hash } = generateApiKey();

  const { data, error } = await adminClient
    .from("api_keys")
    .insert({
      name: body.name,
      key_prefix: prefix,
      key_hash: hash,
      default_assignee_id: body.default_assignee_id ?? null,
      created_by: userId,
    })
    .select("id, name, key_prefix, default_assignee_id, is_active, last_used_at, created_at")
    .single();

  if (error) throw createError({ statusCode: 500, statusMessage: error.message });
  return { ...data, key };
});
