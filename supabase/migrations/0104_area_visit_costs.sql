-- The cost of a maintenance visit depends on the customer's area. Managed in
-- Customer Service by the people granted "cs_visit_costs" (view / edit); anyone who
-- works with maintenance can read it, so the cost can be offered when a visit is
-- recorded.
create table public.area_visit_costs (
  area_id uuid primary key references public.service_areas (id) on delete cascade,
  cost numeric not null check (cost >= 0),
  updated_by uuid references public.profiles (id) on delete set null default auth.uid(),
  updated_at timestamptz not null default now()
);

alter table public.area_visit_costs enable row level security;

create policy area_visit_costs_select on public.area_visit_costs
  for select using (
    public.has_any_module_permission('cs_visit_costs')
    or public.has_any_module_permission('cs_maintenance')
  );
create policy area_visit_costs_insert on public.area_visit_costs
  for insert with check (public.has_permission('cs_visit_costs', 'edit'));
create policy area_visit_costs_update on public.area_visit_costs
  for update using (public.has_permission('cs_visit_costs', 'edit'))
  with check (public.has_permission('cs_visit_costs', 'edit'));
create policy area_visit_costs_delete on public.area_visit_costs
  for delete using (public.has_permission('cs_visit_costs', 'edit'));

-- The area list is read by whoever manages the costs.
drop policy service_areas_select on public.service_areas;
create policy service_areas_select on public.service_areas
  for select using (
    public.has_any_module_permission('cs_customers')
    or public.has_any_module_permission('cs_maintenance')
    or public.has_any_module_permission('crm_leads')
    or public.has_any_module_permission('crm_deals')
    or public.has_any_module_permission('crm_customers')
    or public.has_any_module_permission('reports')
    or public.has_any_module_permission('cs_visit_costs')
  );
