interface PermissionEntry {
  module: string;
  action: string;
}

// Loaded once per session into useState so every page/component shares the
// same permission set without re-fetching. This is UI-layer convenience
// only (hide buttons/nav the user can't use, redirect before a doomed
// query) — real enforcement is the RLS policies + triggers in
// supabase/migrations, never trust this alone.
export function usePermissions() {
  const permissions = useState<PermissionEntry[]>("permissions", () => []);
  const isAdmin = useState<boolean>("permissions-is-admin", () => false);
  const isActive = useState<boolean>("permissions-is-active", () => true);
  const loaded = useState<boolean>("permissions-loaded", () => false);
  // True when the lookup itself failed (an expired session returns nothing, for
  // example) — as opposed to succeeding and finding no permissions. The two
  // need different messages: "ask the admin for a role" vs "sign in again".
  const loadFailed = useState<boolean>("permissions-load-failed", () => false);

  async function load() {
    const user = useSupabaseUser();
    const supabase = useSupabaseClient();

    if (!user.value) {
      permissions.value = [];
      isAdmin.value = false;
      isActive.value = true;
      loaded.value = false;
      return;
    }

    // useSupabaseUser() holds JWT claims (getClaims()), not a User object —
    // the id is `sub`, not `id`.
    loadFailed.value = false;
    const { data: profile, error: profileError } = await supabase
      .from("profiles")
      .select("is_admin, is_active, role_id")
      .eq("id", user.value.sub)
      .single<{ is_admin: boolean; is_active: boolean; role_id: string | null }>();

    if (profileError || !profile) {
      console.error("Could not load the signed-in user's profile", profileError);
      loadFailed.value = true;
    }

    isAdmin.value = !!profile?.is_admin;
    isActive.value = profile?.is_active ?? true;

    if (profile?.role_id) {
      const { data, error } = await supabase
        .from("role_permissions")
        .select("module, action")
        .eq("role_id", profile.role_id)
        .returns<PermissionEntry[]>();
      if (error) {
        console.error("Could not load the user's permissions", error);
        loadFailed.value = true;
      }
      permissions.value = data ?? [];
    } else {
      permissions.value = [];
    }

    loaded.value = true;
  }

  function clear() {
    permissions.value = [];
    isAdmin.value = false;
    isActive.value = true;
    loaded.value = false;
    loadFailed.value = false;
  }

  function hasPermission(module: string, action: string) {
    return (
      isAdmin.value ||
      permissions.value.some((p) => p.module === module && p.action === action)
    );
  }

  function hasAnyModulePermission(module: string) {
    return isAdmin.value || permissions.value.some((p) => p.module === module);
  }

  return {
    permissions,
    isAdmin,
    isActive,
    loaded,
    loadFailed,
    load,
    clear,
    hasPermission,
    hasAnyModulePermission,
  };
}
