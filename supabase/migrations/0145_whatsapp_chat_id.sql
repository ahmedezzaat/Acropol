-- A WAHA chat can be a person whose WhatsApp number is hidden behind a privacy id (a "LID"). Such a chat is
-- kept too, under that id; "chat_id" holds the full WAHA chat id used to answer it (a number's chat id is
-- "<digits>@c.us", a hidden one "<id>@lid"). Empty means "<wa_id>@c.us".
alter table public.whatsapp_conversations add column chat_id text;
