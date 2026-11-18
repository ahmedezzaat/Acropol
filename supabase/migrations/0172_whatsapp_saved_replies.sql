-- Saved replies (ردود جاهزة) for the WhatsApp inbox: a shared list of messages the team inserts into a chat in one
-- click, or by typing "/" and the shortcut. {name} (the contact) and {agent} (the person answering) are filled in
-- when a reply is inserted. Anyone who can open the inbox reads them; people with the "manage replies" action
-- (crm_chats) add, change and delete them.
create table public.whatsapp_saved_replies (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(btrim(title)) between 1 and 80),
  body text not null check (char_length(btrim(body)) between 1 and 4000),
  -- typed after "/" in the reply box, without the slash and without spaces
  shortcut text check (shortcut is null or shortcut ~ '^[^[:space:]/]{1,30}$'),
  -- how many times it was used: the most used come first
  use_count integer not null default 0,
  created_by uuid references public.profiles (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index whatsapp_saved_replies_shortcut on public.whatsapp_saved_replies (lower(shortcut)) where shortcut is not null;

alter table public.whatsapp_saved_replies enable row level security;
create policy whatsapp_saved_replies_select on public.whatsapp_saved_replies for select to authenticated
  using (public.has_any_module_permission('crm_chats'));
create policy whatsapp_saved_replies_insert on public.whatsapp_saved_replies for insert to authenticated
  with check (public.has_permission('crm_chats', 'manage_replies'));
create policy whatsapp_saved_replies_update on public.whatsapp_saved_replies for update to authenticated
  using (public.has_permission('crm_chats', 'manage_replies'))
  with check (public.has_permission('crm_chats', 'manage_replies'));
create policy whatsapp_saved_replies_delete on public.whatsapp_saved_replies for delete to authenticated
  using (public.has_permission('crm_chats', 'manage_replies'));

create or replace function public.whatsapp_saved_replies_touch()
returns trigger
language plpgsql
as $$
begin
  -- the counter changes through whatsapp_use_saved_reply: that is not an edit
  if new.title is distinct from old.title or new.body is distinct from old.body or new.shortcut is distinct from old.shortcut then
    new.updated_at := now();
  end if;
  return new;
end;
$$;
create trigger whatsapp_saved_replies_touch before update on public.whatsapp_saved_replies
  for each row execute function public.whatsapp_saved_replies_touch();

-- Counting a use: anyone who can answer chats, without being able to edit the replies
create or replace function public.whatsapp_use_saved_reply(p_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.whatsapp_saved_replies set use_count = use_count + 1
  where id = p_id and public.has_permission('crm_chats', 'reply');
$$;
revoke all on function public.whatsapp_use_saved_reply(uuid) from public, anon;
grant execute on function public.whatsapp_use_saved_reply(uuid) to authenticated;

-- A few to start with (change or delete them from the inbox)
insert into public.whatsapp_saved_replies (title, shortcut, body) values
  ('ترحيب', 'ترحيب', 'أهلًا {name}، معك {agent} من أكروبول. كيف أقدر أساعدك؟'),
  ('شكرًا', 'شكرا', 'شكرًا لتواصلك مع أكروبول يا {name}. يسعدنا خدمتك دائمًا.'),
  ('سنتواصل معك', 'تواصل', 'تمام يا {name}، هنراجع طلبك ونتواصل معاك في أقرب وقت.'),
  ('العنوان', 'عنوان', 'عنوان أكروبول: 20 ب عمارات العبور، صلاح سالم، القاهرة. موقعنا: https://acropol-eg.com');
