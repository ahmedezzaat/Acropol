import * as z from "zod";

const bodySchema = z.object({
  email: z.email(),
  password: z.string().min(8),
  full_name: z.string().min(1),
  role_id: z.uuid().nullable().optional(),
  is_admin: z.boolean().optional(),
});

export default defineEventHandler(async (event) => {
  const { adminClient } = await requireAdmin(event);
  const body = await readValidatedBody(event, bodySchema.parse);

  const { data, error } = await adminClient.auth.admin.createUser({
    email: body.email,
    password: body.password,
    email_confirm: true,
  });

  if (error || !data.user) {
    throw createError({
      statusCode: 400,
      statusMessage: error?.message ?? "Failed to create user",
    });
  }

  // The handle_new_user trigger already inserted a bare profiles row
  // (id, email) on the auth.users insert above — this fills in the rest.
  const { data: profile, error: profileError } = await adminClient
    .from("profiles")
    .update({
      full_name: body.full_name,
      role_id: body.role_id ?? null,
      is_admin: body.is_admin ?? false,
    })
    .eq("id", data.user.id)
    .select()
    .single();

  if (profileError) {
    throw createError({ statusCode: 500, statusMessage: profileError.message });
  }

  return profile;
});
