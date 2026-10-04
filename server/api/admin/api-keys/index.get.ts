export default defineEventHandler(async (event) => {
  const { adminClient } = await requireAdmin(event);
  const { data, error } = await adminClient
    .from("api_keys")
    .select("id, name, key_prefix, default_assignee_id, is_active, last_used_at, created_at")
    .order("created_at", { ascending: false });
  if (error) throw createError({ statusCode: 500, statusMessage: error.message });
  return data;
});
