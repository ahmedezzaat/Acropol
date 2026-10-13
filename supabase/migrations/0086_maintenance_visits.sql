-- A maintenance visit: the team goes to a customer once and services several of
-- the customer's products in that visit. The per-product records stay in
-- product_maintenance_log (each product keeps its own history, note, cost and
-- next due date); a visit groups the ones done together and keeps the note of
-- the visit as a whole.
create table public.maintenance_visits (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  visit_at timestamptz,
  note text,
  created_by uuid references public.profiles (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);
create index maintenance_visits_customer on public.maintenance_visits (customer_id);

alter table public.product_maintenance_log
  add column visit_id uuid references public.maintenance_visits (id) on delete set null;
create index product_maintenance_log_visit on public.product_maintenance_log (visit_id);

alter table public.maintenance_visits enable row level security;

-- Visible with the customer, to anyone who can see maintenance.
create policy maintenance_visits_select on public.maintenance_visits
  for select using (
    public.has_any_module_permission('cs_maintenance')
    and exists (select 1 from public.customers c where c.id = maintenance_visits.customer_id)
  );

-- A visit is created together with entries of a kind the user is allowed to
-- record (each entry is checked again by the log's own policy).
create policy maintenance_visits_insert on public.maintenance_visits
  for insert with check (
    (public.has_permission('cs_maintenance', 'schedule')
      or public.has_permission('cs_maintenance', 'complete')
      or public.has_permission('cs_maintenance', 'cancel'))
    and exists (select 1 from public.customers c where c.id = maintenance_visits.customer_id)
  );
