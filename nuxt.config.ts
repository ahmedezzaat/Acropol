// https://nuxt.com/docs/api/configuration/nuxt-config
export default defineNuxtConfig({
  compatibilityDate: "2025-07-15",
  devtools: { enabled: true },

  css: ["~/assets/css/main.css"],

  ui: {
    theme: {
      colors: [
        "primary",
        "secondary",
        "accent",
        "info",
        "success",
        "warning",
        "error",
      ],
    },
  },

  modules: [
    "@nuxt/image",
    "@nuxt/scripts",
    "@nuxt/ui",
    "@nuxtjs/seo",
    // "@nuxtjs/supabase",
    "@nuxtjs/i18n",
    // @nuxtjs/seo pulls in nuxt-og-image, which unconditionally registers
    // "playwright-core" as a Nitro virtual module that mocks every export
    // (so its own og-image renderer doesn't force playwright into every
    // deployment). That mock shadows real imports too, which breaks the
    // proposal PDF route's actual use of playwright-core. Registered last
    // so this hook runs after nuxt-og-image's and wins.
    (_options, nuxt) => {
      nuxt.hook("nitro:config", (nitroConfig) => {
        delete nitroConfig.virtual?.["playwright-core"];
      });
    },
  ],

  app: {
    head: {
      meta: [],
      link: [
        {
          rel: "preload",
          href: "/fonts/thmanyah-sans-400.woff2",
          as: "font",
          type: "font/woff2",
          crossorigin: "",
        },
      ],
    },
  },

  i18n: {
    // Required for the module's SEO integration to emit absolute
    // <link rel="alternate" hreflang> tags — without it, Arabic/English
    // page pairs (e.g. /pricing and /en/pricing) never get linked as
    // language variants and search engines treat them as unrelated pages.
    baseUrl: "https://kords.ai",
    locales: [
      // Plain "ar" (no region subtag), not "ar-EG": the site serves Saudi
      // Arabia and Egypt (and the hreflang tag built from this feeds
      // directly into how search engines infer country relevance), so
      // locking the language tag to one country actively worked against
      // being recognized as relevant to the other.
      { code: "ar", language: "ar", dir: "rtl", name: "العربية" },
      { code: "en", language: "en", dir: "ltr", name: "English" },
    ],
    defaultLocale: "ar",
    strategy: "prefix_except_default",
    detectBrowserLanguage: false,
    // The Kords Lab content platform + admin panel are Arabic-only and
    // stay at their existing paths regardless of site locale.
    pages: {},
  },

  supabase: {},

  site: {
    defaultLocale: "ar",
  },

  // Site-wide Organization identity, included in the schema.org graph on
  // every page (previously only a bare {name, logo} was set per-page on
  // /help/*). `telephone` and `sameAs` are the real, already-public numbers
  // and profiles from the site footer — `areaServed` is deliberately scoped
  // to Saudi Arabia and Egypt only (the two markets with real evidence: the
  // Saudi phone line and the Egypt office), not the full GCC, to avoid
  // claiming service coverage that isn't actually backed by anything.
  schemaOrg: {
    identity: {
      type: "Organization",
      logo: "/logo-color.svg",
      telephone: "+966596366376",
      areaServed: ["SA", "EG"],
      sameAs: [],
    },
  },

  sitemap: {
    // Splitting the Knowledge Base into its own /sitemap-help.xml chunk
    // (auto-referenced from the /sitemap_index.xml index) keeps it
    // independently fast to regenerate/crawl as the KB grows, separate from
    // the rest of the site's static + content-platform URLs. The module's
    // default sitemapsPathPrefix ("/__sitemap__/") would nest chunks under
    // that folder instead of the flat "/sitemap-{name}.xml" naming we want,
    // so it's cleared and the literal prefix is baked into each key instead.
    sitemapsPathPrefix: "",
    sitemaps: {},
    // /help/* URLs are canonicalized with a trailing slash (see
    // server/middleware/help-trailing-slash.ts) but the sitemap module
    // unconditionally strips trailing slashes from every `loc` it builds —
    // there's no per-chunk override, only the global (site-wide)
    // `site.trailingSlash`, which would incorrectly add one to every other
    // URL in sitemap-pages.xml too. So /sitemap-help.xml is hand-built
    // instead (server/routes/sitemap-help.xml.ts) and just appended to the
    // index here.
    appendSitemaps: [],
  },

  robots: {
    groups: [
      {
        // Explicitly welcome the AI crawlers/answer engines we want citing
        // Kords content, rather than leaving them to the default "*" rule.
        userAgent: [
          "GPTBot", // OpenAI / ChatGPT
          "OAI-SearchBot", // OpenAI search
          "ClaudeBot", // Anthropic
          "PerplexityBot", // Perplexity
          "Google-Extended", // Gemini / Google AI Overviews
        ],
        allow: ["/"],
      },
      {},
    ],
  },
});
