// The Click-to-WhatsApp ad a chat or a message came from (kept by the server in ad_referral).
export interface AdRef {
  title: string | null;
  body: string | null;
  url: string | null;
  id: string | null;
  type: string | null;
  image: string | null;
  thumb: string | null;
  ctwa: string | null;
  source: string | null;
}
