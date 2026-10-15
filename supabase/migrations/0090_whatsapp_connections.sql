-- WhatsApp numbers connected to Acropol through Meta's Embedded Signup (in
-- Coexistence mode the same number keeps working in the WhatsApp Business app).
-- The business access token is a secret: row level security is on and there
-- are no policies, so only the server (service role) reads or writes this
-- table, through routes that check the Settings permission.
create table public.whatsapp_connections (
  id uuid primary key default gen_random_uuid(),
  waba_id text not null,
  phone_number_id text not null unique,
  display_phone_number text,
  verified_name text,
  coexistence boolean not null default true,
  access_token text not null,
  subscribed boolean not null default false,
  connected_by uuid references public.profiles (id) on delete set null,
  connected_at timestamptz not null default now()
);
create index whatsapp_connections_waba on public.whatsapp_connections (waba_id);
alter table public.whatsapp_connections enable row level security;
