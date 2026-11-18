-- Messages that come from a Click-to-WhatsApp ad (Facebook / Instagram): which ad. WhatsApp itself shows this on the
-- first message of the chat; WAHA hands it over inside the message (externalAdReply), so it is kept here.
--   ad_referral on a message  : the ad that message came from
--   ad_referral on a chat     : the latest ad the person came from (ad_referred_at: when)
-- {title, body, url, id, type, image, thumb, ctwa, source}: the ad's headline and text, its link and id, a picture
-- (a link, or a small embedded thumbnail because the link expires), Meta's click id and the entry point.
alter table public.whatsapp_messages add column ad_referral jsonb;
alter table public.whatsapp_conversations add column ad_referral jsonb;
alter table public.whatsapp_conversations add column ad_referred_at timestamptz;
