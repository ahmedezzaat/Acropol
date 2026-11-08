-- The WhatsApp inbox also holds conversations that come through WAHA (the self-hosted WhatsApp
-- HTTP API). A conversation now says which channel it belongs to; for WAHA the "phone_number_id"
-- column holds the WAHA session name.
alter table public.whatsapp_conversations
  add column provider text not null default 'cloud' check (provider in ('cloud', 'waha'));
create index whatsapp_conversations_unread on public.whatsapp_conversations (last_message_at desc) where unread;
