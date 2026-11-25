// The customer's tax card (البطاقة الضريبية): files in the private customer-files bucket, one customer_files row each.
export interface TaxCardFile {
  id: string;
  file_name: string;
  storage_path: string;
  created_at: string;
}

export function useTaxCard() {
  const supabase = useSupabaseClient();

  async function listTaxCards(customerId: string): Promise<TaxCardFile[]> {
    const { data } = await supabase.from("customer_files").select("id, file_name, storage_path, created_at").eq("customer_id", customerId).eq("kind", "tax_card").order("created_at").order("id");
    return (data ?? []) as TaxCardFile[];
  }

  // stores the files and their rows; a failure leaves nothing behind. Returns an error message or null.
  const uploadTaxCards = (customerId: string, files: File[]) => uploadTaxCardFiles(supabase, customerId, files);

  async function removeTaxCard(file: TaxCardFile): Promise<string | null> {
    const { error } = await supabase.from("customer_files").delete().eq("id", file.id);
    if (error) return error.message;
    await supabase.storage.from("customer-files").remove([file.storage_path]);
    return null;
  }

  async function downloadTaxCard(file: TaxCardFile): Promise<string | null> {
    const { data, error } = await supabase.storage.from("customer-files").createSignedUrl(file.storage_path, 60, { download: file.file_name });
    if (error || !data) return error?.message ?? "failed";
    const a = document.createElement("a");
    a.href = data.signedUrl;
    a.click();
    return null;
  }

  return { listTaxCards, uploadTaxCards, removeTaxCard, downloadTaxCard };
}
