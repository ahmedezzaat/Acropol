import type { SupabaseClient } from "@supabase/supabase-js";

// One contract form for both places a contract is made: winning a deal and "إنشاء عقد" on the contracts page.
export interface ContractDraft {
  code: string;
  signedOn: string;
  value: number | null;
  salesPersonId: string | null;
  notes: string;
  file: File | null;
  products: WonProductDraft[];
}

export function newContractDraft(d: Partial<ContractDraft> & { productName?: string } = {}): ContractDraft {
  const signedOn = d.signedOn ?? "";
  const salesPersonId = d.salesPersonId ?? null;
  return {
    code: d.code ?? "",
    signedOn,
    value: d.value ?? null,
    salesPersonId,
    notes: d.notes ?? "",
    file: null,
    products: d.products ?? [newWonProduct({ name: d.productName ?? "", contract_date: signedOn, sales_person_id: salesPersonId })],
  };
}

// required: the code, the date, the value and at least one complete product (the file is optional)
export function contractDraftValid(d: ContractDraft) {
  return !!d.code.trim() && !!d.signedOn && d.value !== null && d.value >= 0 && wonProductsValid(d.products);
}

// Saves the file (on the contract) and then the contract with its products. With a deal, its contract is created or
// completed; without one, a customer is needed (and a deal can be linked). Returns the contract's id or an error.
export async function saveContractDraft(
  supabase: SupabaseClient,
  opts: { dealId?: string | null; customerId?: string | null; linkDealId?: string | null; draft: ContractDraft },
): Promise<{ id: string | null; error: string | null }> {
  const d = opts.draft;
  const id = crypto.randomUUID();
  let filePath: string | null = null;
  if (d.file) {
    filePath = `${id}/${Date.now()}-${d.file.name}`;
    const { error } = await supabase.storage.from("contract-files").upload(filePath, d.file);
    if (error) return { id: null, error: error.message };
  }
  const { data, error } = await supabase.rpc("crm_save_contract", {
    p_deal_id: opts.dealId ?? null,
    p_customer_id: opts.customerId ?? null,
    p_contract: {
      id,
      code: d.code.trim(),
      signed_on: d.signedOn,
      value: d.value,
      notes: d.notes.trim() || null,
      sales_person_id: d.salesPersonId,
      deal_id: opts.linkDealId ?? null,
      file_name: d.file?.name ?? null,
      file_path: filePath,
    },
    p_products: d.products.map((p) => ({
      name: p.name.trim(),
      category_id: p.category_id,
      quantity: p.quantity,
      sales_person_id: p.sales_person_id,
      warranty_status: p.warranty_status,
      warranty_details: p.warranty_details.trim(),
      payment_status: p.payment_status,
      notes: p.notes.trim(),
    })),
  });
  if (error) {
    // do not leave the uploaded file behind
    if (filePath) await supabase.storage.from("contract-files").remove([filePath]);
    return { id: null, error: error.message };
  }
  return { id: data as string, error: null };
}
