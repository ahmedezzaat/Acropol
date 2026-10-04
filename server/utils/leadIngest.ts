import type { SupabaseClient } from "@supabase/supabase-js";

export const LEAD_SOURCES = [
  "external_client",
  "facebook",
  "instagram",
  "meta",
  "google",
  "website",
  "event",
  "referral",
  "whatsapp",
  "api",
] as const;

export interface IncomingLead {
  name: string;
  phone?: string | null;
  phone2?: string | null;
  email?: string | null;
  source: (typeof LEAD_SOURCES)[number];
  notes?: string | null;
  lead_type?: "individual" | "company";
  company_name?: string | null;
}

export type IngestResult =
  | { status: "created"; id: string }
  | { status: "duplicate"; entity: "lead" | "customer"; id: string };

// One place that turns "something arrived from outside" into a lead, shared
// by the public REST endpoint and the WhatsApp webhook. All the rules —
// phone normalisation, duplicate detection, assignment — live in the
// api_create_lead() database function so they can't drift between callers.
export async function ingestLead(
  client: SupabaseClient,
  lead: IncomingLead,
  assignedTo: string | null,
): Promise<IngestResult> {
  const { data, error } = await client.rpc("api_create_lead", {
    p_name: lead.name,
    p_phone: lead.phone ?? null,
    p_phone2: lead.phone2 ?? null,
    p_email: lead.email ?? null,
    p_source: lead.source,
    p_notes: lead.notes ?? null,
    p_lead_type: lead.lead_type ?? "individual",
    p_company_name: lead.company_name ?? null,
    p_assigned_to: assignedTo,
  });

  if (error) {
    throw createError({ statusCode: 500, statusMessage: error.message });
  }
  return data as IngestResult;
}
