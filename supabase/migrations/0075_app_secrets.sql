-- Server-side secrets entered in Settings (e.g. the email service key). Nobody
-- can read or write this table from the browser: row level security is on and
-- there are no policies, so only the server (service role) touches it, through
-- routes that check the Settings permission.
create table public.app_secrets (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles (id) on delete set null
);
alter table public.app_secrets enable row level security;
