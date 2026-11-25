import type { SupabaseClient } from "@supabase/supabase-js";

// Stores a customer's tax card files (private customer-files bucket + one customer_files row each); a failure leaves
// nothing behind. Returns an error message or null.
export async function uploadTaxCardFiles(supabase: SupabaseClient, customerId: string, files: File[]): Promise<string | null> {
  if (!files.length) return null;
  const base = Date.now();
  const stored: { name: string; path: string }[] = [];
  for (const [i, f] of files.entries()) {
    const path = `${customerId}/${base + i}-${storageSafeName(f.name)}`;
    const { error } = await supabase.storage.from("customer-files").upload(path, f);
    if (error) {
      if (stored.length) await supabase.storage.from("customer-files").remove(stored.map((s) => s.path));
      return `${f.name}: ${error.message}`;
    }
    stored.push({ name: f.name, path });
  }
  const { error } = await supabase
    .from("customer_files")
    .insert(stored.map((s, i) => ({ customer_id: customerId, kind: "tax_card", file_name: s.name, storage_path: s.path, created_at: new Date(base + i).toISOString() })));
  if (error) {
    await supabase.storage.from("customer-files").remove(stored.map((s) => s.path));
    return error.message;
  }
  return null;
}

// The customer category (الفئة) of a deal's contact: the customer's, or the lead's while it is not a customer yet.
export async function contactCategoryId(supabase: SupabaseClient, ids: { customerId?: string | null; leadId?: string | null }): Promise<string | null> {
  if (ids.customerId) {
    const { data } = await supabase.from("customers").select("category_id").eq("id", ids.customerId).maybeSingle();
    return (data as { category_id?: string | null } | null)?.category_id ?? null;
  }
  if (ids.leadId) {
    const { data } = await supabase.from("leads").select("category_id").eq("id", ids.leadId).maybeSingle();
    return (data as { category_id?: string | null } | null)?.category_id ?? null;
  }
  return null;
}
