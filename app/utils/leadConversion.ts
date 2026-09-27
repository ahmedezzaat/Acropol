import type { SupabaseClient } from "@supabase/supabase-js";

// A lead only becomes a real customer once a deal actually wins — not at
// deal-creation time — since quotes and the rest of the pipeline run fine
// against a lead alone. Called wherever a deal's stage is about to become
// the pipeline's fixed "Won" stage. Reuses the lead's customer if it was
// already converted independently (e.g. the manual "Convert to customer"
// button on the lead page), otherwise converts it now via crm_convert_lead.
export async function resolveWonCustomerId(
  supabase: SupabaseClient,
  leadId: string | null,
): Promise<{ customerId: string | null; error: string | null }> {
  if (!leadId) {
    return { customerId: null, error: "no_lead" };
  }

  const { data: lead, error: leadError } = await supabase
    .from("leads")
    .select("customer_id")
    .eq("id", leadId)
    .single();
  if (leadError) return { customerId: null, error: leadError.message };
  if (lead.customer_id) return { customerId: lead.customer_id as string, error: null };

  const { data, error } = await supabase.rpc("crm_convert_lead", { p_lead_id: leadId });
  if (error || !data) return { customerId: null, error: error?.message ?? "conversion failed" };
  return { customerId: data as string, error: null };
}
