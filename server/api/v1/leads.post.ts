import * as z from "zod";

const bodySchema = z
  .object({
    name: z.string().trim().min(1).max(200),
    phone: z.string().trim().max(40).optional(),
    phone2: z.string().trim().max(40).optional(),
    email: z.email().optional(),
    source: z.enum(LEAD_SOURCES).default("api"),
    notes: z.string().trim().max(5000).optional(),
    lead_type: z.enum(["individual", "company"]).optional(),
    company_name: z.string().trim().max(200).optional(),
  })
  .refine((b) => b.phone || b.email, { message: "phone or email is required" });

// POST /api/v1/leads — creates a lead from an external system.
// Auth: "Authorization: Bearer <api key>" (keys are managed in Settings ->
// Integrations). Responds 201 with the new id, or 200 with status
// "duplicate" and the existing record when the phone number is already known.
export default defineEventHandler(async (event) => {
  const { apiKey, adminClient } = await requireApiKey(event);
  const body = await readValidatedBody(event, bodySchema.parse);

  const result = await ingestLead(adminClient, body, apiKey.default_assignee_id);
  setResponseStatus(event, result.status === "created" ? 201 : 200);
  return result;
});
