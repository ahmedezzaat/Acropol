export default defineEventHandler(async (event) => {
  const { adminClient } = await requireSetting(event, "integrations");
  const id = getRouterParam(event, "id");
  if (!id) throw createError({ statusCode: 400, statusMessage: "Missing key id" });

  const { error } = await adminClient.from("api_keys").delete().eq("id", id);
  if (error) throw createError({ statusCode: 500, statusMessage: error.message });
  return { ok: true };
});
