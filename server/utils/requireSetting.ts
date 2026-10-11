import type { H3Event } from "h3";
import type { SupabaseClient } from "@supabase/supabase-js";
import { serverSupabaseServiceRole, serverSupabaseUser } from "#supabase/server";

// The Settings API routes use the service-role client (which bypasses RLS), so
// each one checks for itself that the caller may manage that Settings page: an
// active administrator, or a role granted `settings` → <key>. Returns whether
// the caller is an administrator too, since some actions stay admin-only.
export async function requireSetting(event: H3Event, key: string) {
  const authUser = await serverSupabaseUser(event);
  if (!authUser?.sub) {
    throw createError({ statusCode: 401, statusMessage: "Not authenticated" });
  }

  const adminClient = serverSupabaseServiceRole(event);
  const { data: profile } = await adminClient
    .from("profiles")
    .select("is_admin, is_active, role_id")
    .eq("id", authUser.sub)
    .single();

  if (!profile || !profile.is_active) {
    throw createError({ statusCode: 403, statusMessage: "Access denied" });
  }

  let allowed = !!profile.is_admin;
  if (!allowed && profile.role_id) {
    const { data } = await adminClient
      .from("role_permissions")
      .select("id")
      .eq("role_id", profile.role_id)
      .eq("module", "settings")
      .eq("action", key)
      .maybeSingle();
    allowed = !!data;
  }
  if (!allowed) {
    throw createError({ statusCode: 403, statusMessage: "Not allowed to manage this setting" });
  }

  return { userId: authUser.sub as string, isAdmin: !!profile.is_admin, adminClient };
}

// A user who manages users without being an administrator can't touch an
// administrator's account, nor their own (which could raise their own access).
export async function guardNonAdmin(
  adminClient: SupabaseClient<any, any, any>,
  isAdmin: boolean,
  callerId: string,
  targetId: string,
) {
  if (isAdmin) return;
  if (targetId === callerId) {
    throw createError({ statusCode: 403, statusMessage: "You can't change your own account here" });
  }
  const { data } = await adminClient.from("profiles").select("is_admin").eq("id", targetId).maybeSingle();
  if (data?.is_admin) {
    throw createError({ statusCode: 403, statusMessage: "Only an administrator can change an administrator" });
  }
}
