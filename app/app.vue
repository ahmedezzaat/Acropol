<script setup lang="ts">
import { ar, en } from "@nuxt/ui/locale";

const { locale, t, te } = useI18n();
const route = useRoute();

// Propagates dir/lang into Nuxt UI's own components (pagination, table,
// etc.) — without this, only routing/text is localized, not RTL layout for
// components that ship their own locale strings.
const uiLocale = computed(() => (locale.value === "ar" ? ar : en));

const head = useLocaleHead();
useHead({
  htmlAttrs: computed(() => head.value.htmlAttrs),
});

// nuxt-seo-utils ships an i18n-aware fallback <title> (pages.<route>.title)
// but it never picks up locale messages correctly in this app regardless of
// module registration order — set it directly instead of fighting that
// black box.
const pageTitleKey = computed(() => {
  const routeName = String(route.name ?? "").replace(/___\w+$/, "");
  return `pages.${routeName}.title`;
});
useHead({
  title: () => (te(pageTitleKey.value) ? t(pageTitleKey.value) : ""),
  titleTemplate: (title) => (title ? `${title} | ${t("nav.appName")}` : t("nav.appName")),
});
</script>

<template>
  <UApp :locale="uiLocale">
    <NuxtRouteAnnouncer />
    <NuxtLayout>
      <NuxtPage />
    </NuxtLayout>
  </UApp>
</template>
