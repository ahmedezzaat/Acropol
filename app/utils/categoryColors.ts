// One colour per product category, the same everywhere it is shown (chat list labels...). The colour comes from the
// category's place in the list, so each of the (up to ten) categories has its own and it never changes with the data.
// The whole class names are written out so Tailwind finds them.
const CHIPS = [
  "bg-blue-500/15 text-blue-700 dark:text-blue-300",
  "bg-emerald-500/15 text-emerald-700 dark:text-emerald-300",
  "bg-amber-500/20 text-amber-800 dark:text-amber-300",
  "bg-rose-500/15 text-rose-700 dark:text-rose-300",
  "bg-violet-500/15 text-violet-700 dark:text-violet-300",
  "bg-cyan-500/15 text-cyan-700 dark:text-cyan-300",
  "bg-orange-500/15 text-orange-700 dark:text-orange-300",
  "bg-lime-500/20 text-lime-800 dark:text-lime-300",
  "bg-fuchsia-500/15 text-fuchsia-700 dark:text-fuchsia-300",
  "bg-teal-500/15 text-teal-700 dark:text-teal-300",
] as const;
export const NEUTRAL_CHIP = "bg-muted text-muted";
export const categoryChipClass = (index: number) => CHIPS[((index % CHIPS.length) + CHIPS.length) % CHIPS.length]!;
