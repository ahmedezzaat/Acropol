import { escapeHtml } from "./email";

export interface NewDealEmailData {
  title: string;
  link: string;
  contactName: string | null;
  company: string | null;
  phone: string | null;
  source: string | null;
  pipeline: string | null;
  stage: string | null;
  assignee: string | null;
  createdBy: string | null;
  value: number | null;
  createdAt: string;
}

const SOURCE_LABELS: Record<string, string> = {
  external_client: "عميل خارجي",
  facebook: "فيسبوك",
  instagram: "انستجرام",
  meta: "ميتا",
  google: "جوجل",
  website: "الموقع",
  event: "فعالية",
  referral: "ترشيح",
  whatsapp: "واتساب",
  api: "API",
};

// The "new deal" email: a short summary and a button that opens the deal.
export function newDealEmail(d: NewDealEmailData) {
  const rows: [string, string | null][] = [
    ["العميل", d.contactName],
    ["الشركة", d.company],
    ["الهاتف", d.phone],
    ["المصدر", d.source ? (SOURCE_LABELS[d.source] ?? d.source) : null],
    ["المسار", d.pipeline],
    ["المرحلة", d.stage],
    ["المسؤول", d.assignee],
    ["أضافها", d.createdBy],
    ["القيمة", d.value ? d.value.toLocaleString("en-US") : null],
    ["التاريخ", new Date(d.createdAt).toLocaleString("ar-EG", { timeZone: "Africa/Cairo", dateStyle: "medium", timeStyle: "short" })],
  ];
  const body = rows
    .filter(([, v]) => v)
    .map(
      ([k, v]) =>
        `<tr><td style="padding:6px 0;color:#6b7280;width:90px">${escapeHtml(k)}</td><td style="padding:6px 0;color:#111827;font-weight:600">${k === "الهاتف" ? `<span dir="ltr">${escapeHtml(v)}</span>` : escapeHtml(v)}</td></tr>`,
    )
    .join("");

  const html = `<!doctype html><html dir="rtl" lang="ar"><body style="margin:0;padding:24px;background:#f3f4f6;font-family:Tahoma,Arial,sans-serif">
  <div style="max-width:520px;margin:0 auto;background:#ffffff;border:1px solid #e5e7eb">
    <div style="padding:16px 20px;background:#1d4ed8;color:#ffffff;font-size:15px">صفقة جديدة في أكروبول</div>
    <div style="padding:20px">
      <div style="font-size:18px;font-weight:700;color:#111827;margin-bottom:12px">${escapeHtml(d.title || "صفقة جديدة")}</div>
      <table style="border-collapse:collapse;font-size:14px;width:100%">${body}</table>
      <div style="margin-top:20px"><a href="${escapeHtml(d.link)}" style="display:inline-block;background:#1d4ed8;color:#ffffff;text-decoration:none;padding:10px 18px;font-size:14px">فتح الصفقة</a></div>
    </div>
  </div></body></html>`;

  return { subject: `صفقة جديدة: ${d.title || ""}`.trim(), html };
}
