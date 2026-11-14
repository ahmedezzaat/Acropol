// Customer Service quotations (عروض الأسعار): their statuses and how they are totalled (the database works the
// totals out the same way; this is for showing them while typing).
export const QUOTATION_STATUSES = ["draft", "sent", "approved", "rejected"] as const;
export type QuotationStatus = (typeof QUOTATION_STATUSES)[number];
export const QUOTATION_TONES: Record<QuotationStatus, "neutral" | "info" | "success" | "error"> = {
  draft: "neutral",
  sent: "info",
  approved: "success",
  rejected: "error",
};

export interface QuotationLine {
  spare_part_id: string | null;
  description: string;
  qty: number | null;
  unit_price: number | null;
}

export function quotationTotals(lines: QuotationLine[], discount: number, taxInvoice: boolean) {
  const subtotal = lines.reduce((n, l) => n + (l.qty ?? 0) * (l.unit_price ?? 0), 0);
  const net = Math.max(0, subtotal - Math.min(discount, subtotal));
  const tax = taxInvoice ? Math.round(net * TAX_RATE * 100) / 100 : 0;
  return { subtotal, discount: Math.min(discount, subtotal), net, tax, total: net + tax };
}
