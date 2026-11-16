// Work orders (أوامر الشغل) made from the confirmed visits page.
export const WORK_ORDER_KINDS = ["maintenance", "installation", "operation", "inspection"] as const;
export type WorkOrderKind = (typeof WORK_ORDER_KINDS)[number];
// the kinds kept in cs_work_orders (maintenance is a done visit of the maintenance tables)
export type SimpleWorkOrderKind = Exclude<WorkOrderKind, "maintenance">;

export const WORK_ORDER_ICONS: Record<WorkOrderKind, string> = {
  maintenance: "i-lucide-wrench",
  installation: "i-lucide-hammer",
  operation: "i-lucide-power",
  inspection: "i-lucide-clipboard-check",
};
export const WORK_ORDER_TONES: Record<SimpleWorkOrderKind, "primary" | "success" | "info"> = {
  installation: "primary",
  operation: "success",
  inspection: "info",
};
