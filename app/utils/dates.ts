// Dates are shown the same way everywhere in Acropol: DD/MM/YY (14/10/26), with
// the time after it when there is one. Latin digits in both languages.
const pad = (n: number) => String(n).padStart(2, "0");

function toDate(value: string | Date): Date | null {
  const d = value instanceof Date ? value : new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

// A date, or a plain "YYYY-MM-DD" (read as is, so no timezone can move the day).
export function formatDMY(value: string | Date | null | undefined): string {
  if (!value) return "";
  if (typeof value === "string") {
    const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value.trim());
    if (m) return `${m[3]}/${m[2]}/${m[1]!.slice(2)}`;
  }
  const d = toDate(value);
  return d ? `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${pad(d.getFullYear() % 100)}` : "";
}

// The time of day (12-hour, in the viewer's language for AM/PM).
export function formatClock(value: string | Date | null | undefined, locale = "en"): string {
  const d = value ? toDate(value) : null;
  return d ? d.toLocaleTimeString(locale === "ar" ? "ar-EG-u-nu-latn" : "en", { hour: "numeric", minute: "2-digit" }) : "";
}

// DD/MM/YY and the time: 14/10/26 1:00 PM.
export function formatDMYTime(value: string | Date | null | undefined, locale = "en"): string {
  const date = formatDMY(value);
  if (!date) return "";
  return `${date} ${formatClock(value, locale)}`;
}
