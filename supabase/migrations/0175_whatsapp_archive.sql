-- Archive for WhatsApp chats: a chat that is dealt with is archived and leaves the list, so the list only holds what
-- still needs following up. It comes back by itself when the person writes again (the app clears archived_at on an
-- incoming message). Its status (qualifying, known...) is not touched.
alter table public.whatsapp_conversations add column archived_at timestamptz;
