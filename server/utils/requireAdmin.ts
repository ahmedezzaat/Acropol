import type { H3Event } from "h3";
import { serverSupabaseServiceRole, serverSupabaseUser } from "#supabase/server";

// Every admin route re-checks this itself rather than relying on RLS: the
// service-role client (used for auth.admin.* calls) bypasses RLS entirely
// by design, so RLS policies can't be the enforcement point here.
export async function requireAdmin(event: H3Event) {
  const authUser = await serverSupabaseUser(event);
  if (!authUser?.sub) {
    throw createError({ statusCode: 401, statusMessage: "Not authenticated" });
  }

  const adminClient = serverSupabaseServiceRole(event);
  const { data: profile } = await adminClient
    .from("profiles")
    .select("is_admin")
    .eq("id", authUser.sub)
    .single();

  if (!profile?.is_admin) {
    throw createError({ statusCode: 403, statusMessage: "Admin access required" });
  }

  return { userId: authUser.sub as string, adminClient };
}
