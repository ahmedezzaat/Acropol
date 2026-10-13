import type { SupabaseClient } from "@supabase/supabase-js";

// What was bought when a deal is won. These become Customer Service products
// (the same ones customer service tracks through installation), linked to the
// deal. A deal cannot reach Won without at least one.
export interface WonProductDraft {
  name: string;
  category_id: string | null;
  quantity: number;
  contract_code: string;
  contract_date: string;
  sales_person_id: string | null;
  warranty_status: string | null;
  warranty_details: string;
  payment_status: string | null;
  notes: string;
}

export function newWonProduct(defaults: Partial<WonProductDraft> = {}): WonProductDraft {
  return {
    name: "",
    category_id: null,
    quantity: 1,
    contract_code: "",
    contract_date: "",
    sales_person_id: null,
    warranty_status: null,
    warranty_details: "",
    payment_status: null,
    notes: "",
    ...defaults,
  };
}

// A product is complete once it has a name, a category and a contract date.
export function wonProductValid(p: WonProductDraft) {
  return p.name.trim().length > 0 && !!p.category_id && !!p.contract_date && Number.isInteger(p.quantity) && p.quantity >= 1;
}
export function wonProductsValid(list: WonProductDraft[]) {
  return list.length > 0 && list.every(wonProductValid);
}

// Whether the deal already has its products recorded (a salesperson cannot read
// Customer Service products directly, so this asks the database).
export async function dealHasProducts(supabase: SupabaseClient, dealId: string) {
  const { data } = await supabase.rpc("crm_deal_has_products", { p_deal_id: dealId });
  return data === true;
}

// Saves the products against the deal's customer. The deal must already have
// that customer, so it is set first when the win is what created the customer.
export async function recordDealProducts(
  supabase: SupabaseClient,
  dealId: string,
  customerId: string,
  list: WonProductDraft[],
): Promise<string | null> {
  const { error: linkError } = await supabase.from("deals").update({ customer_id: customerId }).eq("id", dealId).is("customer_id", null);
  if (linkError) return linkError.message;

  const { error } = await supabase.rpc("crm_record_deal_products", {
    p_deal_id: dealId,
    // The contract (one per deal): its code and date come from the products' shared fields.
    p_contract: { contract_code: list[0]?.contract_code.trim() ?? "", contract_date: list[0]?.contract_date ?? "" },
    p_products: list.map((p) => ({
      name: p.name.trim(),
      category_id: p.category_id,
      quantity: p.quantity,
      contract_code: p.contract_code.trim(),
      contract_date: p.contract_date,
      sales_person_id: p.sales_person_id,
      warranty_status: p.warranty_status,
      warranty_details: p.warranty_details.trim(),
      payment_status: p.payment_status,
      notes: p.notes.trim(),
    })),
  });
  return error?.message ?? null;
}
