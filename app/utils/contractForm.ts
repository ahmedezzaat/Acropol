import type { SupabaseClient } from "@supabase/supabase-js";

// One contract form for both places a contract is made: winning a deal and "إنشاء عقد" on the contracts page.
export interface ContractDraft {
  code: string;
  signedOn: string;
  value: number | null;
  salesPersonId: string | null;
  notes: string;
  // any number of files (any language in the names)
  files: File[];
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
    files: [],
    products: d.products ?? [newWonProduct({ name: d.productName ?? "", contract_date: signedOn, sales_person_id: salesPersonId })],
  };
}

// required: the code, the date, the value and at least one complete product (the files are optional)
export function contractDraftValid(d: ContractDraft) {
  return !!d.code.trim() && !!d.signedOn && d.value !== null && d.value >= 0 && wonProductsValid(d.products);
}

// Saves the file (on the contract) and then the contract with its products. With a deal, its contract is created or
// completed; without one, a customer is needed (and a deal can be linked). Returns the contract's id or an error.
export async function saveContractDraft(
  supabase: SupabaseClient,
  opts: { dealId?: string | null; customerId?: string | null; linkDealId?: string | null; draft: ContractDraft },
): Promise<{ id: string | null; error: string | null; warning?: string }> {
  const d = opts.draft;
  const id = crypto.randomUUID();
  // every file is stored first (under the contract's future id); a failure leaves nothing behind
  const stored: { name: string; path: string }[] = [];
  const base = Date.now();
  for (const [i, file] of d.files.entries()) {
    const path = `${id}/${base + i}-${storageSafeName(file.name)}`;
    const { error } = await supabase.storage.from("contract-files").upload(path, file);
    if (error) {
      if (stored.length) await supabase.storage.from("contract-files").remove(stored.map((s) => s.path));
      return { id: null, error: `${file.name}: ${error.message}` };
    }
    stored.push({ name: file.name, path });
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
    // do not leave the uploaded files behind
    if (stored.length) await supabase.storage.from("contract-files").remove(stored.map((s) => s.path));
    return { id: null, error: error.message };
  }
  // the files belong to the contract now (in the order they were chosen)
  if (stored.length) {
    const { error: filesError } = await supabase
      .from("contract_files")
      .insert(stored.map((s, i) => ({ contract_id: id, file_name: s.name, storage_path: s.path, created_at: new Date(base + i).toISOString() })));
    if (filesError) {
      await supabase.storage.from("contract-files").remove(stored.map((s) => s.path));
      return { id: data as string, error: null, warning: filesError.message };
    }
  }
  return { id: data as string, error: null };
}
