export interface CsArea {
  id: string;
  name: string;
}

export interface CsPipeline {
  id: string;
  name: string;
  sort_order: number;
}

export interface CsStage {
  id: string;
  pipeline_id: string;
  name: string;
  sort_order: number;
  is_final: boolean;
  require_date: boolean;
  max_stay_days: number | null;
  max_stay_hours: number | null;
}

// A company customer is shown by its company name, with the contact person
// under it; an individual by their own name. (Same convention as leads.)
export function isCompanyCustomer(c: Pick<CsCustomer, "company" | "customer_type">) {
  return c.customer_type ? c.customer_type === "company" : !!c.company?.trim();
}
export function customerTitle(c: Pick<CsCustomer, "name" | "company" | "customer_type">) {
  return isCompanyCustomer(c) && c.company?.trim() ? c.company.trim() : c.name;
}
export function customerSubtitle(c: Pick<CsCustomer, "name" | "company" | "customer_type">) {
  return isCompanyCustomer(c) && c.company?.trim() ? c.name : null;
}

export interface CsProductItem {
  id: string;
  product_id: string;
  name: string;
  quantity: number;
  unit: string | null;
  sort_order: number;
}

export interface CsProduct {
  id: string;
  customer_id: string;
  name: string;
  category_id: string | null;
  contract_date: string | null;
  contract_code: string | null;
  next_maintenance_at: string | null;
  next_maintenance_note: string | null;
  last_maintenance_on: string | null;
  sales_person_id: string | null;
  maintenance_declined_at: string | null;
  operation_date: string | null;
  warranty_status: string | null;
  warranty_details: string | null;
  payment_status: string | null;
  notes: string | null;
  pipeline_id: string;
  stage_id: string;
  created_at: string;
}

export interface CsStageDate {
  product_id: string;
  stage_id: string;
  reached_on: string;
}

export interface CsCustomer {
  id: string;
  name: string;
  company: string | null;
  phone: string | null;
  email: string | null;
  address: string | null;
  area_id: string | null;
  customer_type?: "individual" | "company";
  converted_from_lead_id?: string | null;
  created_at?: string;
}

// Shared helpers for the Customer Service module. Its funnels (pipelines and
// their stages) are managed in Settings, like the CRM's.
export function useCs() {
  const supabase = useSupabaseClient();
  const { locale } = useI18n();

  const areas = useState<CsArea[]>("cs-areas", () => []);
  const pipelines = useState<CsPipeline[]>("cs-pipelines", () => []);
  const stages = useState<CsStage[]>("cs-stages", () => []);

  async function loadAreas(force = false) {
    if (areas.value.length && !force) return;
    const { data } = await supabase.from("service_areas").select("id, name").order("sort_order");
    areas.value = data ?? [];
  }
  function areaName(id: string | null | undefined) {
    return id ? (areas.value.find((a) => a.id === id)?.name ?? "") : "";
  }

  async function loadPipelines(force = false) {
    if (pipelines.value.length && !force) return;
    const [{ data: pips }, { data: stg }] = await Promise.all([
      supabase.from("cs_pipelines").select("id, name, sort_order").order("sort_order"),
      supabase
        .from("cs_pipeline_stages")
        .select("id, pipeline_id, name, sort_order, is_final, require_date, max_stay_days, max_stay_hours")
        .order("sort_order"),
    ]);
    pipelines.value = pips ?? [];
    stages.value = stg ?? [];
  }

  function stagesOf(pipelineId: string | null | undefined) {
    return stages.value.filter((s) => s.pipeline_id === pipelineId).sort((a, b) => a.sort_order - b.sort_order);
  }
  function stageById(id: string | null | undefined) {
    return stages.value.find((s) => s.id === id);
  }
  function stageName(id: string | null | undefined) {
    return stageById(id)?.name ?? "—";
  }
  function pipelineName(id: string | null | undefined) {
    return pipelines.value.find((p) => p.id === id)?.name ?? "";
  }
  // Label for a stage: just its name, or "pipeline › stage" once there is more
  // than one pipeline to tell apart.
  function stageLabelFull(id: string | null | undefined) {
    const stage = stageById(id);
    if (!stage) return "—";
    return pipelines.value.length > 1 ? `${pipelineName(stage.pipeline_id)} › ${stage.name}` : stage.name;
  }

  // Colour by position in its own funnel: first is neutral, the final (completed)
  // stage is green, the stages in between step through blue / amber / brand.
  const MIDDLE = ["info", "warning", "primary"] as const;
  function stageColor(id: string | null | undefined): "neutral" | "info" | "warning" | "primary" | "success" {
    const stage = stageById(id);
    if (!stage) return "neutral";
    if (stage.is_final) return "success";
    const list = stagesOf(stage.pipeline_id);
    const index = list.findIndex((s) => s.id === stage.id);
    if (index <= 0) return "neutral";
    return MIDDLE[(index - 1) % MIDDLE.length]!;
  }

  // Maximum stay in a stage, in days (days + hours/24), or null when unset.
  function stageLimitDays(stage: CsStage | undefined) {
    if (!stage) return null;
    const total = (stage.max_stay_days ?? 0) + (stage.max_stay_hours ?? 0) / 24;
    return total > 0 ? total : null;
  }

  // Stage dates: build a lookup once per fetched list of rows.
  function dateIndex(rows: CsStageDate[]) {
    return new Map(rows.map((r) => [`${r.product_id}:${r.stage_id}`, r.reached_on]));
  }
  function dateOf(index: Map<string, string>, productId: string, stageId: string) {
    return index.get(`${productId}:${stageId}`) ?? null;
  }

  function daysSince(date: string | null | undefined) {
    return date ? Math.floor((Date.now() - new Date(`${date}T12:00:00`).getTime()) / 86_400_000) : null;
  }

  function formatDate(value: string | null | undefined) {
    if (!value) return "—";
    // Plain dates: pin to local noon so no timezone shifts the day.
    return new Date(`${value}T12:00:00`).toLocaleDateString(locale.value === "ar" ? "ar" : "en", {
      day: "numeric",
      month: "short",
      year: "numeric",
    });
  }

  // A timestamp as local date + time (e.g. a maintenance appointment).
  function formatDateTime(value: string | null | undefined) {
    if (!value) return "—";
    return new Date(value).toLocaleString(locale.value === "ar" ? "ar" : "en", { dateStyle: "medium", timeStyle: "short" });
  }

  // Periodic maintenance: due every `months` months counted from the operation
  // date. The due date is the first anniversary after the last visit (or after
  // the operation date if there was none), so a product that was never serviced
  // is due 12 months after it started, and is overdue from then on.
  function maintenanceDue(p: Pick<CsProduct, "operation_date" | "last_maintenance_on">, months: number | null | undefined) {
    if (!p.operation_date || !months) return null;
    const [y, m, d] = p.operation_date.split("-").map(Number) as [number, number, number];
    const iso = (dt: Date) =>
      `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, "0")}-${String(dt.getDate()).padStart(2, "0")}`;
    const after = p.last_maintenance_on ?? p.operation_date;
    for (let k = 1; k < 400; k++) {
      const occ = new Date(y, m - 1 + k * months, 1);
      occ.setDate(Math.min(d, new Date(occ.getFullYear(), occ.getMonth() + 1, 0).getDate()));
      if (iso(occ) > after) return iso(occ);
    }
    return null;
  }

  return {
    areas,
    pipelines,
    stages,
    loadAreas,
    areaName,
    loadPipelines,
    stagesOf,
    stageById,
    stageName,
    pipelineName,
    stageLabelFull,
    stageColor,
    stageLimitDays,
    dateIndex,
    dateOf,
    daysSince,
    formatDate,
    formatDateTime,
    maintenanceDue,
  };
}
