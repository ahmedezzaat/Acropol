-- Who gets an email when a new deal is added (managed in Settings), and a mark on
-- each deal so its email is sent only once.
create table public.notification_emails (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  label text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create unique index notification_emails_email on public.notification_emails (lower(email));

alter table public.notification_emails enable row level security;
create policy notification_emails_manage on public.notification_emails
  for all
  using (public.has_permission('settings', 'notification_emails'))
  with check (public.has_permission('settings', 'notification_emails'));

alter table public.deals add column new_deal_email_sent_at timestamptz;
