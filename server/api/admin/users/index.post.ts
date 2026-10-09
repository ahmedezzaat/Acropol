import * as z from "zod";

const bodySchema = z.object({
  email: z.email().optional(),
  password: z.string().min(8).optional(),
  full_name: z.string().min(1),
  role_id: z.uuid().nullable().optional(),
  is_admin: z.boolean().optional(),
  // false: a record-only user (e.g. for migrated data) that can never sign in.
  can_login: z.boolean().optional(),
});

export default defineEventHandler(async (event) => {
  const { adminClient } = await requireAdmin(event);
  const body = await readValidatedBody(event, bodySchema.parse);
  const canLogin = body.can_login ?? true;

  if (canLogin && (!body.email || !body.password)) {
    throw createError({ statusCode: 400, statusMessage: "email and password are required" });
  }

  // A record-only user still needs an auth row (profiles.id references it):
  // a throwaway password nobody knows, a placeholder address if none was given,
  // and a ban so no session can ever be minted.
  const email = body.email ?? `nologin-${crypto.randomUUID()}@no-login.acropol.invalid`;
  const password = canLogin ? body.password! : `${crypto.randomUUID()}${crypto.randomUUID()}`;

  const { data, error } = await adminClient.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    ...(canLogin ? {} : { ban_duration: "876000h" }),
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
      is_admin: canLogin ? (body.is_admin ?? false) : false,
      can_login: canLogin,
    })
    .eq("id", data.user.id)
    .select()
    .single();

  if (profileError) {
    throw createError({ statusCode: 500, statusMessage: profileError.message });
  }

  return profile;
});
