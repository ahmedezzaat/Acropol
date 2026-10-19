-- Finishing a maintenance visit now records the spare parts used (with their
-- quantity and the price at the time) and the visit cost; the log entry's cost is
-- the final fees collected from the customer (visit cost + parts).
alter table public.product_maintenance_log
  add column visit_cost numeric check (visit_cost is null or visit_cost >= 0);

create table public.maintenance_used_parts (
  id uuid primary key default gen_random_uuid(),
  log_id uuid not null references public.product_maintenance_log (id) on delete cascade,
  spare_part_id uuid references public.spare_parts (id) on delete set null,
  name text not null,
  unit_price numeric not null check (unit_price >= 0),
  quantity int not null check (quantity > 0)
);
create index maintenance_used_parts_log on public.maintenance_used_parts (log_id);

alter table public.maintenance_used_parts enable row level security;

-- Visible with the log entry it belongs to.
create policy maintenance_used_parts_select on public.maintenance_used_parts
  for select using (exists (select 1 from public.product_maintenance_log l where l.id = maintenance_used_parts.log_id));
create policy maintenance_used_parts_insert on public.maintenance_used_parts
  for insert with check (
    public.has_permission('cs_maintenance', 'complete')
    and exists (select 1 from public.product_maintenance_log l where l.id = maintenance_used_parts.log_id)
  );
create policy maintenance_used_parts_update on public.maintenance_used_parts
  for update using (public.has_permission('cs_maintenance', 'complete'))
  with check (public.has_permission('cs_maintenance', 'complete'));
create policy maintenance_used_parts_delete on public.maintenance_used_parts
  for delete using (public.has_permission('cs_maintenance', 'complete'));

-- The spare parts list is read by the people who finish visits (to pick the parts used).
drop policy spare_parts_select on public.spare_parts;
create policy spare_parts_select on public.spare_parts
  for select using (
    public.has_any_module_permission('cs_spare_parts')
    or public.has_any_module_permission('cs_maintenance')
  );
