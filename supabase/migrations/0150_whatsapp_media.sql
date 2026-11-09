-- Photos and files in WhatsApp chats: customers' media is kept in a private bucket and shown in the inbox;
-- the team can send photos and files back. (Needs WAHA Plus: the Core edition cannot send or download media.)
alter table public.whatsapp_messages
  add column media_path text,
  add column media_type text,
  add column media_name text;

insert into storage.buckets (id, name, public) values ('wa-media', 'wa-media', false) on conflict (id) do nothing;
-- the inbox team uploads what they send (the server keeps what customers send, with its own key)
create policy wa_media_insert on storage.objects for insert
  with check (bucket_id = 'wa-media' and public.has_permission('crm_chats', 'reply'));
create policy wa_media_select on storage.objects for select
  using (bucket_id = 'wa-media' and public.has_any_module_permission('crm_chats'));
