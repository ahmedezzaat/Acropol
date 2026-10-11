import * as z from "zod";
import { serverSupabaseServiceRole, serverSupabaseUser } from "#supabase/server";

const bodySchema = z.object({ deal_id: z.uuid() });

// Called by the app right after someone adds a deal. Emails the addresses
// managed in Settings -> Notification emails, once per deal.
export default defineEventHandler(async (event) => {
  const authUser = await serverSupabaseUser(event);
  if (!authUser?.sub) throw createError({ statusCode: 401, statusMessage: "Not authenticated" });
  const { deal_id } = await readValidatedBody(event, bodySchema.parse);

  const admin = serverSupabaseServiceRole(event);
  const { data: deal } = await admin
    .from("deals")
    .select(
      "id, title, value, created_at, created_by, assigned_to, new_deal_email_sent_at, lead:leads(name, phone, source, company_name), customer:customers(name, company, phone), stage:pipeline_stages(name), pipeline:pipelines(name)",
    )
    .eq("id", deal_id)
    .maybeSingle();
  if (!deal) throw createError({ statusCode: 404, statusMessage: "Deal not found" });

  // Only the person who just added the deal can ask for its email.
  const justCreated = Date.now() - new Date(deal.created_at).getTime() < 15 * 60_000;
  if (deal.created_by !== authUser.sub || !justCreated) {
    throw createError({ statusCode: 403, statusMessage: "Not allowed" });
  }

  // Claim the deal so a second call can't send it again.
  const { data: claimed } = await admin
    .from("deals")
    .update({ new_deal_email_sent_at: new Date().toISOString() })
    .eq("id", deal_id)
    .is("new_deal_email_sent_at", null)
    .select("id");
  if (!claimed?.length) return { sent: 0, reason: "already_sent" };

  const release = () => admin.from("deals").update({ new_deal_email_sent_at: null }).eq("id", deal_id);

  const { data: recipients } = await admin.from("notification_emails").select("email").eq("is_active", true);
  if (!recipients?.length) {
    await release();
    return { sent: 0, reason: "no_recipients" };
  }

  const { data: people } = await admin
    .from("profiles")
    .select("id, full_name, email")
    .in("id", [deal.created_by, deal.assigned_to].filter((x): x is string => !!x));
  const nameOf = (id: string | null) => {
    const p = people?.find((x) => x.id === id);
    return p ? p.full_name || p.email : null;
  };

  const lead = deal.lead as { name: string; phone: string | null; source: string | null; company_name: string | null } | null;
  const customer = deal.customer as { name: string; company: string | null; phone: string | null } | null;
  const { subject, html } = newDealEmail({
    title: deal.title,
    link: `${getRequestURL(event).origin}/crm/deals/${deal.id}`,
    contactName: customer?.name ?? lead?.name ?? null,
    company: customer?.company ?? lead?.company_name ?? null,
    phone: customer?.phone ?? lead?.phone ?? null,
    source: lead?.source ?? null,
    pipeline: (deal.pipeline as { name: string } | null)?.name ?? null,
    stage: (deal.stage as { name: string } | null)?.name ?? null,
    assignee: nameOf(deal.assigned_to),
    createdBy: nameOf(deal.created_by),
    value: deal.value,
    createdAt: deal.created_at,
  });

  const results = await Promise.all(recipients.map((r) => sendEmail(event, { to: r.email, subject, html })));
  const sent = results.filter((r) => r.ok).length;
  if (!sent) {
    await release();
    const failure = results.find((r) => !r.ok);
    return { sent: 0, reason: failure?.reason ?? "failed" };
  }
  return { sent, reason: null };
});
