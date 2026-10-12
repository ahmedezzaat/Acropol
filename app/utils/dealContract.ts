import type { SupabaseClient } from "@supabase/supabase-js";

// Winning a deal needs its contract file. It is stored like any deal attachment
// (private storage + a deal_attachments row), marked as kind "contract".
export async function dealHasContract(supabase: SupabaseClient, dealId: string) {
  const { data } = await supabase.from("deal_attachments").select("id").eq("deal_id", dealId).eq("kind", "contract").limit(1);
  return !!data?.length;
}

// Returns an error message, or null when the file was stored.
export async function uploadDealContract(supabase: SupabaseClient, dealId: string, file: File): Promise<string | null> {
  const path = `${dealId}/${Date.now()}-${file.name}`;
  const { error: uploadError } = await supabase.storage.from("deal-attachments").upload(path, file);
  if (uploadError) return uploadError.message;
  const { error: insertError } = await supabase
    .from("deal_attachments")
    .insert({ deal_id: dealId, file_name: file.name, storage_path: path, kind: "contract" });
  return insertError?.message ?? null;
}
