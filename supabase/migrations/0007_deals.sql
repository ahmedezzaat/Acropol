create type public.deal_stage as enum ('open', 'proposal', 'negotiation', 'won', 'lost');

create table public.deals (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id),
  lead_id uuid references public.leads (id),
  title text not null,
  stage public.deal_stage not null default 'open',
  value numeric(12, 2),
  expected_close_date date,
  assigned_to uuid references public.profiles (id),
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger deals_set_updated_at
  before update on public.deals
  for each row execute function public.set_updated_at();

alter table public.deals enable row level security;

create policy deals_select on public.deals
  for select
  using (public.has_any_module_permission('crm_deals'));

create policy deals_insert on public.deals
  for insert
  with check (public.has_permission('crm_deals', 'create'));

create policy deals_update on public.deals
  for update
  using (public.has_permission('crm_deals', 'edit'));

create policy deals_delete on public.deals
  for delete
  using (public.has_permission('crm_deals', 'delete'));
