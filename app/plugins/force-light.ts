// Night mode is disabled (see colorMode in nuxt.config.ts). This pins the
// preference to light, so even a stray "dark" left in localStorage can't
// turn it on. It is applied again once the app has mounted because the
// color-mode module restores the stored value during its own startup, which
// can run after this plugin.
export default defineNuxtPlugin((nuxtApp) => {
  const colorMode = useColorMode();
  const force = () => {
    colorMode.preference = "light";
  };
  force();
  nuxtApp.hook("app:mounted", force);
});
