// Phone numbers get pasted from all kinds of sources (WhatsApp, contact
// cards, spreadsheets) that leave stray leading/trailing whitespace —
// trimmed automatically wherever a phone field is saved, everywhere else in
// the number (the internal formatting spaces) is left untouched.
export function trimOrNull(value: string | null | undefined): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}
