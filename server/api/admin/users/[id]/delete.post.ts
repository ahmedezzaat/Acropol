export default defineEventHandler(async (event) => {
  const { userId, adminClient } = await requireAdmin(event);
  const id = getRouterParam(event, "id");
  if (!id) throw createError({ statusCode: 400, statusMessage: "Missing user id" });

  if (id === userId) {
    throw createError({ statusCode: 400, statusMessage: "cannot_delete_self" });
  }

  // Every assignment/authorship FK to profiles is a plain restrict (no
  // cascade), so a user can only be deleted once none of their data trail
  // is left — checked up front for a clear reason instead of a raw FK
  // error surfacing from the cascade delete below.
  const dataChecks: Array<[table: string, column: string]> = [
    ["leads", "assigned_to"],
    ["leads", "created_by"],
    ["deals", "assigned_to"],
    ["deals", "created_by"],
    ["customers", "assigned_to"],
    ["customers", "created_by"],
    ["quotes", "created_by"],
    ["deal_activities", "created_by"],
    ["teams", "leader_id"],
  ];

  for (const [table, column] of dataChecks) {
    const { count, error } = await adminClient
      .from(table)
      .select("id", { count: "exact", head: true })
      .eq(column, id);
    if (error) throw createError({ statusCode: 500, statusMessage: error.message });
    if (count && count > 0) {
      throw createError({ statusCode: 409, statusMessage: `has_data:${table}` });
    }
  }

  // Cascades to the profiles row (profiles.id references auth.users
  // on delete cascade) — nothing else to clean up.
  const { error } = await adminClient.auth.admin.deleteUser(id);
  if (error) {
    throw createError({ statusCode: 500, statusMessage: error.message });
  }

  return { success: true };
});
