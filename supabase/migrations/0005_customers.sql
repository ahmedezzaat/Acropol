create table public.customers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  company text,
  phone text,
  email text,
  address text,
  -- FK to leads added in 0006, once the leads table exists.
  converted_from_lead_id uuid,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger customers_set_updated_at
  before update on public.customers
  for each row execute function public.set_updated_at();

alter table public.customers enable row level security;

create policy customers_select on public.customers
  for select
  using (public.has_any_module_permission('crm_customers'));

create policy customers_insert on public.customers
  for insert
  with check (public.has_permission('crm_customers', 'create'));

create policy customers_update on public.customers
  for update
  using (public.has_permission('crm_customers', 'edit'));

create policy customers_delete on public.customers
  for delete
  using (public.has_permission('crm_customers', 'delete'));
