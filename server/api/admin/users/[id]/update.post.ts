import * as z from "zod";

const bodySchema = z.object({
  full_name: z.string().min(1).optional(),
  role_id: z.uuid().nullable().optional(),
  is_admin: z.boolean().optional(),
  is_active: z.boolean().optional(),
});

export default defineEventHandler(async (event) => {
  const { adminClient } = await requireAdmin(event);
  const id = getRouterParam(event, "id");
  if (!id) throw createError({ statusCode: 400, statusMessage: "Missing user id" });

  const body = await readValidatedBody(event, bodySchema.parse);

  // profiles RLS only allows self-updates (see supabase/migrations/0002) —
  // editing another user's role/admin/active status is deliberately only
  // possible through this service-role route, not the regular client.
  const { data: profile, error } = await adminClient
    .from("profiles")
    .update(body)
    .eq("id", id)
    .select()
    .single();

  if (error) {
    throw createError({ statusCode: 500, statusMessage: error.message });
  }

  if (body.is_active !== undefined) {
    // Belt-and-suspenders: block/unblock at the Supabase Auth level too, not
    // just the app-level is_active flag, so a deactivated user can't still
    // sign in and mint a valid session.
    await adminClient.auth.admin.updateUserById(id, {
      ban_duration: body.is_active ? "none" : "876000h",
    });
  }

  return profile;
});
