-- WhatsApp chat qualification: when a stranger messages the business number, Claude chats with
-- them and asks what is needed (what they need, where, when, budget) BEFORE any contact is
-- created. Only a qualified chat becomes a lead; the rest stay saved as conversations and an agent
-- can still turn one into a contact by hand. A person who is already a lead or customer is never
-- answered by the assistant.

-- ---- Settings (one row)
create table public.whatsapp_ai_settings (
  id integer primary key default 1 check (id = 1),
  enabled boolean not null default false,
  model text not null default 'claude-sonnet-5-5',
  -- what the business does, in the assistant's instructions
  business_description text not null default '',
  qualify_need boolean not null default true,
  qualify_area boolean not null default true,
  qualify_timing boolean not null default true,
  qualify_budget boolean not null default true,
  -- the assistant hands over to a person after this many replies in one chat
  max_ai_replies integer not null default 12 check (max_ai_replies > 0),
  -- sent when the chat is qualified and when it is handed over
  done_message text not null default 'شكرًا لك، تم تسجيل طلبك وسيتواصل معك أحد زملائنا قريبًا.',
  handover_message text not null default 'سأحوّل محادثتك إلى أحد زملائنا ليساعدك، وسيرد عليك قريبًا.'
);
insert into public.whatsapp_ai_settings (id) values (1);

-- ---- Conversations
create table public.whatsapp_conversations (
  id uuid primary key default gen_random_uuid(),
  phone_number_id text not null,
  wa_id text not null,
  display_name text,
  -- qualifying: the assistant is asking; qualified: a lead was created; handed_over: a person
  -- takes it; known: already a lead or customer; closed
  status text not null default 'qualifying' check (status in ('qualifying', 'qualified', 'handed_over', 'known', 'closed')),
  ai_paused boolean not null default false,
  collected jsonb not null default '{}'::jsonb,
  ai_replies integer not null default 0,
  lead_id uuid references public.leads (id) on delete set null,
  customer_id uuid references public.customers (id) on delete set null,
  last_inbound_at timestamptz,
  last_message_at timestamptz not null default now(),
  unread boolean not null default true,
  created_at timestamptz not null default now(),
  unique (phone_number_id, wa_id)
);
create index whatsapp_conversations_recent on public.whatsapp_conversations (last_message_at desc);

create table public.whatsapp_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.whatsapp_conversations (id) on delete cascade,
  direction text not null check (direction in ('in', 'out')),
  sender text not null check (sender in ('customer', 'ai', 'agent')),
  body text,
  wa_message_id text unique,
  created_at timestamptz not null default now()
);
create index whatsapp_messages_conversation on public.whatsapp_messages (conversation_id, created_at);

-- Is this number already a lead or a customer? (the same digits rule as creating a lead)
create or replace function public.whatsapp_known_contact(p_digits text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select jsonb_build_object('entity', 'lead', 'id', l.id) from public.leads l
       where public.phone_digits(l.phone) = p_digits or public.phone_digits(l.phone2) = p_digits limit 1),
    (select jsonb_build_object('entity', 'customer', 'id', c.id) from public.customers c
       where public.phone_digits(c.phone) = p_digits
          or exists (select 1 from unnest(c.extra_phones) e where public.phone_digits(e) = p_digits) limit 1),
    'null'::jsonb
  );
$$;
revoke all on function public.whatsapp_known_contact(text) from public, anon, authenticated;

-- ---- Access: people with a chats permission read them; settings by the Settings permission.
-- (The server writes conversations and messages with its own key.)
alter table public.whatsapp_ai_settings enable row level security;
alter table public.whatsapp_conversations enable row level security;
alter table public.whatsapp_messages enable row level security;
create policy whatsapp_ai_settings_select on public.whatsapp_ai_settings for select
  using (public.has_permission('settings', 'whatsapp_ai'));
create policy whatsapp_ai_settings_update on public.whatsapp_ai_settings for update
  using (public.has_permission('settings', 'whatsapp_ai')) with check (public.has_permission('settings', 'whatsapp_ai'));
create policy whatsapp_conversations_select on public.whatsapp_conversations for select
  using (public.has_any_module_permission('crm_chats'));
create policy whatsapp_conversations_update on public.whatsapp_conversations for update
  using (public.has_permission('crm_chats', 'reply')) with check (public.has_permission('crm_chats', 'reply'));
create policy whatsapp_messages_select on public.whatsapp_messages for select
  using (public.has_any_module_permission('crm_chats'));

-- ---- Notification: a chat needs a person
alter table public.notifications drop constraint notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in (
    'deal_assigned', 'lead_assigned', 'activity_scheduled', 'activity_reminder',
    'deal_unassigned', 'deals_unassigned', 'visit_pending', 'visit_update',
    'work_stage_changed', 'work_request_created', 'work_assigned', 'work_request_withdrawn',
    'work_request_done', 'task_assigned', 'task_done', 'leave_request', 'leave_decided',
    'chat_handover'
  ));
