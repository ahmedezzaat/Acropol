export type VisitStatus = "pending_leader" | "pending_final" | "approved" | "rejected" | "done" | "cancelled";
// A visit type key (see visit_types). Admin-managed, so any string.
export type VisitKind = string;

export interface VisitType {
  id: string;
  key: string;
  name: string;
  requires_deal: boolean;
  icon: string;
  sort_order: number;
}
export type VisitAction = "approve" | "reject" | "done" | "cancel";

export interface Visit {
  id: string;
  kind: VisitKind;
  deal_id: string | null;
  requested_by: string;
  visit_date: string;
  time_from: string;
  time_to: string;
  address: string;
  notes: string | null;
  status: VisitStatus;
  created_at: string;
  updated_at: string;
}

export interface VisitEvent {
  id: string;
  visit_id: string;
  action: "submitted" | "leader_approved" | "approved" | "rejected" | "done" | "cancelled";
  actor_id: string | null;
  note: string | null;
  created_at: string;
}

export interface DealLabel {
  id: string;
  contact: string;
  title: string;
}

// Shared helpers for field trips (مأمورية) and inspections (معاينة): labels,
// colours, formatting, and the list of deals a request can be attached to.
export function useVisits() {
  const supabase = useSupabaseClient();
  const { t, locale } = useI18n();

  const dealLabels = useState<DealLabel[]>("visit-deal-labels", () => []);
  const visitTypes = useState<VisitType[]>("visit-types", () => []);

  const statusColors: Record<VisitStatus, "warning" | "info" | "success" | "error" | "neutral"> = {
    pending_leader: "warning",
    pending_final: "warning",
    approved: "info",
    rejected: "error",
    done: "success",
    cancelled: "neutral",
  };

  function statusLabel(status: VisitStatus) {
    return t(`crm.visits.status.${status}`);
  }
  function kindLabel(kind: VisitKind) {
    return visitTypes.value.find((x) => x.key === kind)?.name ?? kind;
  }
  function kindIcon(kind: VisitKind) {
    return visitTypes.value.find((x) => x.key === kind)?.icon ?? "i-lucide-map-pin";
  }
  function kindRequiresDeal(kind: VisitKind) {
    return visitTypes.value.find((x) => x.key === kind)?.requires_deal ?? true;
  }

  // The admin-managed list of types (مأمورية, معاينة, جولة خارجية, ...).
  async function loadTypes(force = false) {
    if (visitTypes.value.length && !force) return;
    const { data } = await supabase.from("visit_types").select("*").order("sort_order");
    visitTypes.value = (data ?? []) as VisitType[];
  }
  function formatDate(value: string) {
    // visit_date is a plain date: pin it to local noon so no timezone shifts it.
    return new Date(`${value}T12:00:00`).toLocaleDateString(locale.value === "ar" ? "ar" : "en", {
      weekday: "short",
      day: "numeric",
      month: "short",
      year: "numeric",
    });
  }
  function timeRange(v: Pick<Visit, "time_from" | "time_to">) {
    return `${v.time_from.slice(0, 5)} – ${v.time_to.slice(0, 5)}`;
  }

  function dealLabel(id: string | null) {
    if (!id) return "";
    const d = dealLabels.value.find((x) => x.id === id);
    return d ? d.contact : t("crm.visits.unknownDeal");
  }

  // What a request is "about": its deal's contact, or — for a type that isn't
  // tied to a deal (جولة خارجية) — the address / area.
  function visitSubject(v: Pick<Visit, "deal_id" | "address">) {
    return v.deal_id ? dealLabel(v.deal_id) : v.address;
  }

  // Every deal this user can see (RLS), with its contact's name — used for the
  // deal picker and to label visits.
  async function loadDeals(force = false) {
    if (dealLabels.value.length && !force) return;
    const [{ data: deals }, { data: leads }, { data: customers }] = await Promise.all([
      supabase.from("deals").select("id, title, lead_id, customer_id").order("created_at", { ascending: false }),
      supabase.from("leads").select("id, name"),
      supabase.from("customers").select("id, name"),
    ]);
    const leadName = new Map((leads ?? []).map((l) => [l.id, l.name]));
    const customerName = new Map((customers ?? []).map((c) => [c.id, c.name]));
    dealLabels.value = (deals ?? []).map((d) => ({
      id: d.id,
      title: d.title,
      contact: (d.lead_id && leadName.get(d.lead_id)) || (d.customer_id && customerName.get(d.customer_id)) || d.title,
    }));
  }

  return { dealLabels, visitTypes, loadTypes, kindRequiresDeal, visitSubject, statusColors, statusLabel, kindLabel, kindIcon, formatDate, timeRange, dealLabel, loadDeals };
}
