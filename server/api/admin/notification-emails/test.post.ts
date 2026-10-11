// "Send test email": emails every active address in the list so the setup
// (Resend key, sender address, recipients) can be checked from Settings.
export default defineEventHandler(async (event) => {
  const { adminClient } = await requireSetting(event, "notification_emails");

  const { data: recipients } = await adminClient.from("notification_emails").select("email").eq("is_active", true);
  if (!recipients?.length) return { sent: 0, reason: "no_recipients" };

  const { subject, html } = newDealEmail({
    title: "رسالة تجريبية",
    link: `${getRequestURL(event).origin}/crm/deals`,
    contactName: "عميل تجريبي",
    company: null,
    phone: null,
    source: null,
    pipeline: null,
    stage: null,
    assignee: null,
    createdBy: null,
    value: null,
    createdAt: new Date().toISOString(),
  });

  const results = await Promise.all(recipients.map((r) => sendEmail(event, { to: r.email, subject: `[تجربة] ${subject}`, html })));
  const sent = results.filter((r) => r.ok).length;
  const failure = results.find((r) => !r.ok);
  return { sent, reason: sent ? null : (failure?.reason ?? "failed"), detail: failure?.detail ?? null };
});
