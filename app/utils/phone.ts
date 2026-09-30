// Canonical international digits (no "+", "00", or spacing) for a phone
// number, used both for wa.me links and for matching the "same" number
// across differently-formatted entries (legacy local format, "+20...",
// "0020...", the new PhoneInput's "+20..."). Most numbers in this CRM are
// entered in Egyptian local format (a leading 0), so that leading 0 is
// swapped for the Egypt country code; numbers already entered with a "+" or
// "00" country code are left as-is.
export function phoneDigits(phone: string | null | undefined): string | null {
  const digits = phone?.replace(/[^\d+]/g, "");
  if (!digits) return null;
  let international: string;
  if (digits.startsWith("+")) {
    international = digits.slice(1);
  } else if (digits.startsWith("00")) {
    international = digits.slice(2);
  } else if (digits.startsWith("0")) {
    international = "20" + digits.slice(1);
  } else {
    international = digits;
  }
  return international || null;
}

export function toWhatsAppLink(phone: string | null | undefined): string | null {
  const digits = phoneDigits(phone);
  return digits ? `https://wa.me/${digits}` : null;
}

// Used by search boxes — a query matches a stored phone if either the raw
// digits (ignoring formatting) contain it, or the country-code-normalized
// forms do (so "01099307789" and "+201099307789" find each other, and a
// partial tail like "9307789" still matches via the raw-digit check).
export function phoneMatches(stored: string | null | undefined, query: string): boolean {
  const rawQuery = query.replace(/\D/g, "");
  if (!rawQuery) return false;
  const rawStored = stored?.replace(/\D/g, "") ?? "";
  if (rawStored.includes(rawQuery)) return true;
  const normQuery = phoneDigits(query);
  const normStored = phoneDigits(stored);
  return !!normQuery && !!normStored && normStored.includes(normQuery);
}
