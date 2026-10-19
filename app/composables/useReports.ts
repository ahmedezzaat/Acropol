export interface MaintenanceDoneRow {
  visit_key: string;
  done_on: string;
  technician_id: string | null;
  technician_name: string | null;
  customer_id: string;
  customer_name: string;
  area_id: string | null;
  area_name: string | null;
  cost: number;
  products: number;
}

export interface MaintenanceRescheduledRow {
  done_at: string;
  old_at: string | null;
  new_at: string;
  customer_id: string;
  customer_name: string;
  reason: string | null;
  agent_id: string | null;
  agent_name: string | null;
  products: number;
}

export interface MaintenanceRescheduledFilters {
  from: string;
  to: string;
  agent: string | null;
}

export interface SparePartUsedRow {
  used_id: string;
  done_on: string;
  customer_id: string;
  customer_name: string;
  area_name: string | null;
  technician_name: string | null;
  product_name: string;
  part_name: string;
  quantity: number;
  unit_price: number;
  line_total: number;
}

export interface MaintenanceDoneFilters {
  from: string;
  to: string;
  technician: string | null;
  area: string | null;
}

export interface ReportOption {
  label: string;
  value: string;
}

// A local calendar date as YYYY-MM-DD (not UTC, so "today" is the user's today).
export function toISODate(d: Date) {
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

// The ready-made date ranges the report pages offer.
export function reportRange(kind: "thisWeek" | "thisMonth" | "lastMonth" | "last30" | "thisYear") {
  const now = new Date();
  // weeks run Saturday to Friday, like the visits calendar
  if (kind === "thisWeek") {
    const start = new Date(now.getFullYear(), now.getMonth(), now.getDate() - ((now.getDay() + 1) % 7));
    return { from: toISODate(start), to: toISODate(new Date(start.getFullYear(), start.getMonth(), start.getDate() + 6)) };
  }
  if (kind === "thisMonth") return { from: toISODate(new Date(now.getFullYear(), now.getMonth(), 1)), to: toISODate(new Date(now.getFullYear(), now.getMonth() + 1, 0)) };
  if (kind === "lastMonth") return { from: toISODate(new Date(now.getFullYear(), now.getMonth() - 1, 1)), to: toISODate(new Date(now.getFullYear(), now.getMonth(), 0)) };
  if (kind === "thisYear") return { from: toISODate(new Date(now.getFullYear(), 0, 1)), to: toISODate(new Date(now.getFullYear(), 11, 31)) };
  return { from: toISODate(new Date(now.getFullYear(), now.getMonth(), now.getDate() - 29)), to: toISODate(now) };
}

export function formatReportMoney(value: number, currency: string) {
  return `${Number(value).toLocaleString("en-US")} ${currency}`;
}

// Data for the reports: each report is a database function that checks the
// caller's permission for that report itself.
export function useReports() {
  const supabase = useSupabaseClient();

  async function loadMaintenanceDone(f: MaintenanceDoneFilters) {
    const { data, error } = await supabase.rpc("report_maintenance_done", {
      p_from: f.from,
      p_to: f.to,
      p_technician: f.technician ?? undefined,
      p_area: f.area ?? undefined,
    });
    if (error) throw error;
    return ((data ?? []) as MaintenanceDoneRow[]).map((r) => ({ ...r, cost: Number(r.cost) }));
  }

  async function loadSparePartsUsed(f: MaintenanceDoneFilters) {
    const { data, error } = await supabase.rpc("report_spare_parts_used", {
      p_from: f.from,
      p_to: f.to,
      p_technician: f.technician ?? undefined,
      p_area: f.area ?? undefined,
    });
    if (error) throw error;
    return ((data ?? []) as SparePartUsedRow[]).map((r) => ({ ...r, unit_price: Number(r.unit_price), line_total: Number(r.line_total) }));
  }

  // The same parts added up: how many of each were used, and what they come to.
  function summarizeParts(rows: SparePartUsedRow[]) {
    const byName = new Map<string, { name: string; quantity: number; total: number }>();
    for (const r of rows) {
      const cur = byName.get(r.part_name) ?? { name: r.part_name, quantity: 0, total: 0 };
      cur.quantity += r.quantity;
      cur.total += r.line_total;
      byName.set(r.part_name, cur);
    }
    return [...byName.values()].sort((a, b) => b.total - a.total);
  }

  async function loadMaintenanceRescheduled(f: MaintenanceRescheduledFilters) {
    const { data, error } = await supabase.rpc("report_maintenance_rescheduled", {
      p_from: f.from,
      p_to: f.to,
      p_agent: f.agent ?? undefined,
    });
    if (error) throw error;
    return (data ?? []) as MaintenanceRescheduledRow[];
  }

  // The people who can schedule maintenance (the agents who reschedule).
  async function loadAgents(): Promise<ReportOption[]> {
    const { data } = await supabase.from("profiles").select("id, full_name, email").eq("is_active", true).order("full_name");
    return (data ?? []).map((p) => ({ label: p.full_name || p.email, value: p.id }));
  }

  async function loadTechnicians(): Promise<ReportOption[]> {
    const { data } = await supabase.from("profiles").select("id, full_name, email").eq("is_technician", true).order("full_name");
    return (data ?? []).map((p) => ({ label: p.full_name || p.email, value: p.id }));
  }

  async function loadAreaOptions(): Promise<ReportOption[]> {
    const { data } = await supabase.from("service_areas").select("id, name").order("sort_order");
    return (data ?? []).map((a) => ({ label: a.name, value: a.id }));
  }

  return { loadSparePartsUsed, summarizeParts, loadMaintenanceDone, loadMaintenanceRescheduled, loadAgents, loadTechnicians, loadAreaOptions };
}
