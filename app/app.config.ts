export default defineAppConfig({
  ui: {
    colors: {
      primary: "kords-primary",
      secondary: "kords-secondary",
      accent: "kords-accent",
      success: "kords-success",
      warning: "kords-warning",
      error: "kords-error",
      info: "kords-info",
      neutral: "kords-neutral",
    },
    // Every page banner is a solid Deep Navy, regardless of light/dark mode, fixed to a 700px band.
    pageHero: {
      slots: {
        root: "bg-[var(--kords-navy-900)] min-h-[700px] flex flex-col justify-center",
        headline: "text-white/70",
        title: "text-white text-3xl sm:text-5xl",
        description: "text-white/80 text-base sm:text-lg",
      },
    },
  },
});
