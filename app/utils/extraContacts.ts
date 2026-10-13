// Extra phone numbers of a customer, each with the person to ask for. Stored as
// two arrays that line up by position (extra_phones + extra_phone_names); the
// forms edit them as one list of { phone, name }.
export interface ExtraContact {
  phone: string;
  name: string;
}

export function toExtraContacts(phones?: string[] | null, names?: string[] | null): ExtraContact[] {
  return (phones ?? []).map((phone, i) => ({ phone, name: names?.[i] ?? "" }));
}

// Blank numbers are dropped, and their names with them.
export function fromExtraContacts(list: ExtraContact[]) {
  const kept = list.map((c) => ({ phone: c.phone.trim(), name: c.name.trim() })).filter((c) => c.phone.length > 0);
  return { extra_phones: kept.map((c) => c.phone), extra_phone_names: kept.map((c) => c.name) };
}
