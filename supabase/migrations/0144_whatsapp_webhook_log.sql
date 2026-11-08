-- A short log of what WAHA sends to the app (the last few hundred calls): which event, from which chat, and
-- what the app did with it — so "nothing happens" can be traced. Only people who manage Integrations read it.
create table public.whatsapp_webhook_log (
  id bigint generated always as identity primary key,
  received_at timestamptz not null default now(),
  event text,
  chat text,
  from_me boolean,
  outcome text not null,
  detail text
);
create index whatsapp_webhook_log_recent on public.whatsapp_webhook_log (received_at desc);
alter table public.whatsapp_webhook_log enable row level security;
create policy whatsapp_webhook_log_select on public.whatsapp_webhook_log for select
  using (public.has_permission('settings', 'integrations'));
