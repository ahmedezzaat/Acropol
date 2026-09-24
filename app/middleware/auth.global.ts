// Own redirect handling instead of @nuxtjs/supabase's built-in `redirect`
// option (disabled in nuxt.config.ts), since its path-based matching doesn't
// account for i18n's locale-prefixed routes (ar unprefixed, en at /en/...).
export default defineNuxtRouteMiddleware((to) => {
  const user = useSupabaseUser();
  const localePath = useLocalePath();

  const routeBaseName = to.name?.toString().replace(/___\w+$/, "") ?? "";
  const publicRoutes = ["login"];

  if (!user.value && !publicRoutes.includes(routeBaseName)) {
    return navigateTo(localePath("/login"));
  }

  if (user.value && routeBaseName === "login") {
    return navigateTo(localePath("/"));
  }
});
