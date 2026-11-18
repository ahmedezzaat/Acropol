// The ad a WhatsApp message came from (Click-to-WhatsApp ads on Facebook / Instagram). WhatsApp shows it on the first
// message of the chat; WAHA (NOWEB) carries it in the message's contextInfo as externalAdReply, plus an
// entryPointConversionSource such as "ctwa_ad". Everything read from it is cleaned and cut to a sensible size.
export interface AdReferral {
  title: string | null;
  body: string | null;
  // the ad's link (facebook.com / instagram.com post or ad)
  url: string | null;
  id: string | null;
  // "ad" or "post"
  type: string | null;
  // the picture: a link (it expires) and, when there is one, a small embedded thumbnail
  image: string | null;
  thumb: string | null;
  // Meta's click id (ctwa_clid), for matching the click to the ad in Ads Manager
  ctwa: string | null;
  // where in the app the person entered ("ctwa_ad", "ctwa_post"...)
  source: string | null;
}

// eslint-disable-next-line no-control-regex
const text = (v: unknown, max: number) => (typeof v === "string" ? v.replace(/[\u0000-\u001F\u007F-\u009F]/g, " ").replace(/\s+/g, " ").trim().slice(0, max) || null : null);
const link = (v: unknown) => (typeof v === "string" && /^https?:\/\//i.test(v.trim()) ? v.trim().slice(0, 1000) : null);

// a thumbnail comes as base64 text or as bytes ({type:"Buffer", data:[...]}); only a small one is kept
function thumbnail(v: unknown): string | null {
  let b64: string | null = null;
  if (typeof v === "string") b64 = v.replace(/\s+/g, "");
  else if (v && typeof v === "object" && Array.isArray((v as { data?: unknown }).data) && (v as { data: unknown[] }).data.length < 30_000) b64 = Buffer.from((v as { data: number[] }).data).toString("base64");
  if (!b64 || b64.length > 40_000 || !/^[A-Za-z0-9+/=]+$/.test(b64)) return null;
  return `data:image/jpeg;base64,${b64}`;
}

// every contextInfo a message carries: one per kind of message ("extendedTextMessage", "imageMessage"...)
function contextInfos(payload: any): any[] {
  const list: any[] = [];
  const msg = payload?._data?.message;
  if (msg && typeof msg === "object") for (const v of Object.values(msg)) if (v && typeof v === "object") list.push((v as any).contextInfo);
  list.push(payload?._data?.contextInfo, payload?.contextInfo);
  return list.filter((c) => c && typeof c === "object");
}

export function extractAdReferral(payload: unknown): AdReferral | null {
  for (const ci of contextInfos(payload)) {
    const ad = ci.externalAdReply && typeof ci.externalAdReply === "object" ? ci.externalAdReply : null;
    const source = text(ci.entryPointConversionSource, 60);
    // an ad has its reply block; the entry point alone ("ctwa_ad") is enough to know the chat came from one
    if (!ad && !(source && /ctwa|ad/i.test(source))) continue;
    return {
      title: text(ad?.title, 200),
      body: text(ad?.body, 500),
      url: link(ad?.sourceUrl),
      id: text(ad?.sourceId, 80),
      type: text(ad?.sourceType, 30),
      image: link(ad?.thumbnailUrl) ?? link(ad?.originalImageUrl),
      thumb: thumbnail(ad?.thumbnail),
      ctwa: text(ad?.ctwaClid ?? ci.ctwaClid, 300),
      source,
    };
  }
  return null;
}

// What the message's contextInfo holds, as field names only (never content): a message that should have an ad but shows
// none can then be understood from the webhook log.
export function contextKeys(payload: unknown): string {
  const keys = new Set<string>();
  for (const ci of contextInfos(payload)) for (const k of Object.keys(ci)) keys.add(k);
  return [...keys].slice(0, 14).join(",");
}
