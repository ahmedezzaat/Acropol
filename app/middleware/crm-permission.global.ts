// Runs after auth.global.ts (alphabetical file order for global middleware),
// so by the time this runs an unauthenticated user has already been
// redirected to /login. This is UI-layer gatekeeping only — the real
// enforcement is Postgres RLS; this just avoids rendering a page (or
// attempting a doomed query) the user has no permission for.
export default defineNuxtRouteMiddleware(async (to) => {
  const requiresAdmin = to.path.startsWith("/admin");
  const meta = to.meta.crmPermission as
    | { module: string; action?: string; anyAction?: string[] }
    | undefined;
  if (!requiresAdmin && !meta) return;

  const user = useSupabaseUser();
  if (!user.value) return;

  const { hasPermission, hasAnyModulePermission, isAdmin, loaded, load } =
    usePermissions();
  if (!loaded.value) await load();

  // Settings: an administrator, or a role granted that Settings page (any page
  // of it for the hub).
  if (requiresAdmin) {
    const key = settingsKeyForPath(to.path);
    const allowed = isAdmin.value || (key ? hasPermission("settings", key) : hasAnyModulePermission("settings"));
    if (!allowed) return navigateTo("/403");
  }
  if (!meta) return;

  const ok = meta.anyAction
    ? meta.anyAction.some((a) => hasPermission(meta.module, a))
    : meta.action
      ? hasPermission(meta.module, meta.action)
      : hasAnyModulePermission(meta.module);

  if (!ok) return navigateTo("/403");
});
