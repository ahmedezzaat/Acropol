// Runs after auth.global.ts (alphabetical file order for global middleware),
// so by the time this runs an unauthenticated user has already been
// redirected to /login. This is UI-layer gatekeeping only — the real
// enforcement is Postgres RLS; this just avoids rendering a page (or
// attempting a doomed query) the user has no permission for.
export default defineNuxtRouteMiddleware(async (to) => {
  const requiresAdmin = to.path.startsWith("/admin");
  const meta = to.meta.crmPermission as
    | { module: string; action?: string }
    | undefined;
  if (!requiresAdmin && !meta) return;

  const user = useSupabaseUser();
  if (!user.value) return;

  const { hasPermission, hasAnyModulePermission, isAdmin, loaded, load } =
    usePermissions();
  if (!loaded.value) await load();

  if (requiresAdmin && !isAdmin.value) return navigateTo("/403");
  if (!meta) return;

  const ok = meta.action
    ? hasPermission(meta.module, meta.action)
    : hasAnyModulePermission(meta.module);

  if (!ok) return navigateTo("/403");
});
