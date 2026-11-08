// Shared pieces of the Leave module: the settings (types, policy), who can approve, the days a
// vacation counts, and the turning of a database refusal into a message.
export interface LeaveType {
  id: string;
  name: string;
  yearly_credit: number;
  requires_attachment: boolean;
  is_active: boolean;
  sort_order: number;
}
export interface LeavePolicy {
  delay_max_hours: number;
  delay_per_month: number;
  weekend_days: number[];
  year_start_month: number;
  default_start: string;
  default_end: string;
}
export interface Approver {
  id: string;
  full_name: string | null;
  email: string;
}

export function useLeave() {
  const supabase = useSupabaseClient();
  const { t } = useI18n();

  async function loadTypes(onlyActive = true): Promise<LeaveType[]> {
    let q = supabase.from("leave_types").select("id, name, yearly_credit, requires_attachment, is_active, sort_order").order("sort_order").order("created_at");
    if (onlyActive) q = q.eq("is_active", true);
    const { data } = await q;
    return ((data ?? []) as LeaveType[]).map((x) => ({ ...x, yearly_credit: Number(x.yearly_credit) }));
  }
  async function loadPolicy(): Promise<LeavePolicy> {
    const { data } = await supabase.from("leave_policy").select("delay_max_hours, delay_per_month, weekend_days, year_start_month, default_start, default_end").eq("id", 1).maybeSingle();
    const p = data as LeavePolicy | null;
    return {
      delay_max_hours: Number(p?.delay_max_hours ?? 2),
      delay_per_month: Number(p?.delay_per_month ?? 3),
      weekend_days: p?.weekend_days ?? [5, 6],
      year_start_month: p?.year_start_month ?? 1,
      default_start: (p?.default_start ?? "09:00").slice(0, 5),
      default_end: (p?.default_end ?? "17:00").slice(0, 5),
    };
  }
  async function loadApprovers(): Promise<Approver[]> {
    const { data } = await supabase.rpc("leave_approvers");
    return (data ?? []) as Approver[];
  }

  // The days of a vacation that count: every day but the weekend (the database does the same sum).
  function workingDays(start: string, end: string, weekend: number[]) {
    if (!start || !end || end < start) return 0;
    let n = 0;
    const d = new Date(`${start}T00:00:00`);
    const last = new Date(`${end}T00:00:00`);
    while (d <= last) {
      if (!weekend.includes(d.getDay())) n++;
      d.setDate(d.getDate() + 1);
    }
    return n;
  }

  // The database refuses with a short code; show it as text.
  function errorText(message: string | undefined) {
    const code = (message ?? "").trim();
    const key = `leave.errors.${code}`;
    const text = t(key);
    return text === key ? code : text;
  }

  return { loadTypes, loadPolicy, loadApprovers, workingDays, errorText };
}
