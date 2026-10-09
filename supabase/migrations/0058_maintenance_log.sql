-- A log of maintenance activity, so it can be tracked over time: an
-- appointment being booked ('scheduled', for the time it is booked for) and a
-- visit being performed ('done', on the date it happened). Append-only.
create table public.product_maintenance_log (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.customer_products (id) on delete cascade,
  kind text not null check (kind in ('scheduled', 'done')),
  happened_at timestamptz not null default now(),
  scheduled_for timestamptz,
  done_on date,
  note text,
  created_by uuid references public.profiles (id) on delete set null default auth.uid()
);
create index product_maintenance_log_product on public.product_maintenance_log (product_id);
create index product_maintenance_log_kind_time on public.product_maintenance_log (kind, happened_at);
create index product_maintenance_log_done_on on public.product_maintenance_log (done_on) where kind = 'done';

alter table public.product_maintenance_log enable row level security;

create policy product_maintenance_log_select on public.product_maintenance_log
  for select using (public.has_any_module_permission('cs_customers'));
create policy product_maintenance_log_insert on public.product_maintenance_log
  for insert with check (public.has_permission('cs_customers', 'edit'));
