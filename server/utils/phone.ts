// Canonical international digits of a phone number (no "+", "00" or spacing), the same
// rule as app/utils/phone.ts: a leading 0 is Egyptian local format and becomes 20.
export function canonicalPhone(phone: string | null | undefined): string | null {
  const digits = phone?.replace(/[^\d+]/g, "");
  if (!digits) return null;
  let international: string;
  if (digits.startsWith("+")) international = digits.slice(1);
  else if (digits.startsWith("00")) international = digits.slice(2);
  else if (digits.startsWith("0")) international = "20" + digits.slice(1);
  else international = digits;
  return international || null;
}

// A user who signs in with a phone number and has no email gets a placeholder address
// (Supabase Auth needs one); it is never shown or used to send mail.
export const PHONE_EMAIL_DOMAIN = "phone.acropol.invalid";
export const phoneEmail = (canonical: string) => `phone-${canonical}@${PHONE_EMAIL_DOMAIN}`;
