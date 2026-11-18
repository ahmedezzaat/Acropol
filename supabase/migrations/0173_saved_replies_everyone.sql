-- Saved replies: anyone who can open the WhatsApp inbox can add, change and delete them (there is no separate permission).
drop policy whatsapp_saved_replies_insert on public.whatsapp_saved_replies;
drop policy whatsapp_saved_replies_update on public.whatsapp_saved_replies;
drop policy whatsapp_saved_replies_delete on public.whatsapp_saved_replies;
create policy whatsapp_saved_replies_insert on public.whatsapp_saved_replies for insert to authenticated
  with check (public.has_any_module_permission('crm_chats'));
create policy whatsapp_saved_replies_update on public.whatsapp_saved_replies for update to authenticated
  using (public.has_any_module_permission('crm_chats'))
  with check (public.has_any_module_permission('crm_chats'));
create policy whatsapp_saved_replies_delete on public.whatsapp_saved_replies for delete to authenticated
  using (public.has_any_module_permission('crm_chats'));
