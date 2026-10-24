import * as z from "zod";

const bodySchema = z.object({
  email: z.email().optional(),
  password: z.string().min(8).optional(),
  full_name: z.string().min(1),
  role_id: z.uuid().nullable().optional(),
  is_admin: z.boolean().optional(),
  // false: a record-only user (e.g. for migrated data) that can never sign in.
  can_login: z.boolean().optional(),
  // A technician carries out maintenance visits (can be assigned to them).
  is_technician: z.boolean().optional(),
  // Sign in with phone + password (a technician may have no email at all).
  phone: z.string().optional(),
});

export default defineEventHandler(async (event) => {
  const { adminClient, isAdmin } = await requireSetting(event, "users");
  const body = await readValidatedBody(event, bodySchema.parse);
  const canLogin = body.can_login ?? true;

  const phone = canonicalPhone(body.phone);
  if (canLogin && (!(body.email || phone) || !body.password)) {
    throw createError({ statusCode: 400, statusMessage: "an email or phone, and a password, are required" });
  }

  // A record-only user still needs an auth row (profiles.id references it):
  // a throwaway password nobody knows, a placeholder address if none was given,
  // and a ban so no session can ever be minted.
  const email = body.email ?? (phone && canLogin ? phoneEmail(phone) : `nologin-${crypto.randomUUID()}@no-login.acropol.invalid`);
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
      // Only an administrator can make another administrator.
      is_admin: canLogin && isAdmin ? (body.is_admin ?? false) : false,
      can_login: canLogin,
      is_technician: body.is_technician ?? false,
      phone,
    })
    .eq("id", data.user.id)
    .select()
    .single();

  if (profileError) {
    // the user was created above: do not leave an account without its profile data
    await adminClient.auth.admin.deleteUser(data.user.id);
    throw createError({
      statusCode: profileError.code === "23505" ? 409 : 500,
      statusMessage: profileError.code === "23505" ? "This phone number is already used by another user" : profileError.message,
    });
  }

  return profile;
});
