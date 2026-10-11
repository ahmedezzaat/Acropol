-- Maintenance gets its own permission resource, `cs_maintenance`, with the
-- actions: view, schedule (schedule / reschedule), complete (mark done),
-- cancel (decline / resume) and note. Holding any of them opens the
-- Maintenance pages.
--
-- Everything here is enforced in the database: the log can only be written for
-- an action the user holds, and a product's maintenance columns can only be
-- changed with the matching action (other product columns still need
-- cs_customers "edit").

-- Roles that already work in Customer Service keep working: they get the new
-- permissions that match what they could do before.
insert into public.role_permissions (role_id, module, action)
select distinct rp.role_id, 'cs_maintenance', 'view'
from public.role_permissions rp
where rp.module = 'cs_customers'
on conflict do nothing;

insert into public.role_permissions (role_id, module, action)
select distinct rp.role_id, 'cs_maintenance', a.action
from public.role_permissions rp
cross join (values ('schedule'), ('complete'), ('cancel'), ('note')) as a(action)
where rp.module = 'cs_customers' and rp.action = 'edit'
on conflict do nothing;

-- Reading: people who work on maintenance need to see the products, customers
-- and funnels it is built on, even without any Customer Service customers access.
drop policy customers_cs_select on public.customers;
create policy customers_cs_select on public.customers
  for select using (
    public.has_any_module_permission('cs_customers') or public.has_any_module_permission('cs_maintenance')
  );

drop policy customer_products_select on public.customer_products;
create policy customer_products_select on public.customer_products
  for select using (
    public.has_any_module_permission('cs_customers') or public.has_any_module_permission('cs_maintenance')
  );

drop policy customer_product_items_select on public.customer_product_items;
create policy customer_product_items_select on public.customer_product_items
  for select using (
    public.has_any_module_permission('cs_customers') or public.has_any_module_permission('cs_maintenance')
  );

drop policy customer_product_stage_dates_select on public.customer_product_stage_dates;
create policy customer_product_stage_dates_select on public.customer_product_stage_dates
  for select using (
    public.has_any_module_permission('cs_customers') or public.has_any_module_permission('cs_maintenance')
  );

drop policy cs_pipelines_select on public.cs_pipelines;
create policy cs_pipelines_select on public.cs_pipelines
  for select using (
    public.has_any_module_permission('cs_customers') or public.has_any_module_permission('cs_maintenance')
  );

drop policy cs_pipeline_stages_select on public.cs_pipeline_stages;
create policy cs_pipeline_stages_select on public.cs_pipeline_stages
  for select using (
    public.has_any_module_permission('cs_customers') or public.has_any_module_permission('cs_maintenance')
  );

drop policy service_areas_select on public.service_areas;
create policy service_areas_select on public.service_areas
  for select using (
    public.has_any_module_permission('cs_customers') or public.has_any_module_permission('cs_maintenance')
  );

-- The maintenance log: readable with any maintenance permission; each kind of
-- entry needs its own action.
drop policy product_maintenance_log_select on public.product_maintenance_log;
create policy product_maintenance_log_select on public.product_maintenance_log
  for select using (public.has_any_module_permission('cs_maintenance'));

drop policy product_maintenance_log_insert on public.product_maintenance_log;
create policy product_maintenance_log_insert on public.product_maintenance_log
  for insert with check (
    case kind
      when 'scheduled' then public.has_permission('cs_maintenance', 'schedule')
      when 'rescheduled' then public.has_permission('cs_maintenance', 'schedule')
      when 'done' then public.has_permission('cs_maintenance', 'complete')
      when 'declined' then public.has_permission('cs_maintenance', 'cancel')
      when 'resumed' then public.has_permission('cs_maintenance', 'cancel')
      when 'cancelled' then public.has_permission('cs_maintenance', 'cancel')
      when 'note' then public.has_permission('cs_maintenance', 'note')
      else false
    end
  );

-- Products: a maintenance holder may update a product row, but the trigger
-- below limits what they can change.
create policy customer_products_update_maintenance on public.customer_products
  for update
  using (
    public.has_permission('cs_maintenance', 'schedule')
    or public.has_permission('cs_maintenance', 'complete')
    or public.has_permission('cs_maintenance', 'cancel')
  )
  with check (
    public.has_permission('cs_maintenance', 'schedule')
    or public.has_permission('cs_maintenance', 'complete')
    or public.has_permission('cs_maintenance', 'cancel')
  );

create or replace function public.customer_product_guard_maintenance()
returns trigger
language plpgsql
as $$
declare
  v_skip text[] := array[
    'updated_at', 'next_maintenance_at', 'next_maintenance_note',
    'last_maintenance_on', 'maintenance_declined_at'
  ];
begin
  -- Server-side jobs and scripts (no signed-in user) are not limited.
  if auth.uid() is null then
    return new;
  end if;

  -- Anything other than the maintenance columns is a normal product edit.
  if (to_jsonb(new) - v_skip) is distinct from (to_jsonb(old) - v_skip)
     and not public.has_permission('cs_customers', 'edit') then
    raise exception 'insufficient permission to edit this product';
  end if;

  -- Each maintenance change needs its own action.
  if new.maintenance_declined_at is distinct from old.maintenance_declined_at then
    if not public.has_permission('cs_maintenance', 'cancel') then
      raise exception 'insufficient permission to cancel or resume maintenance';
    end if;
  elsif new.last_maintenance_on is distinct from old.last_maintenance_on then
    if not public.has_permission('cs_maintenance', 'complete') then
      raise exception 'insufficient permission to complete maintenance';
    end if;
  elsif new.next_maintenance_at is distinct from old.next_maintenance_at
     or new.next_maintenance_note is distinct from old.next_maintenance_note then
    if not public.has_permission('cs_maintenance', 'schedule') then
      raise exception 'insufficient permission to schedule maintenance';
    end if;
  end if;

  return new;
end;
$$;

create trigger customer_products_guard_maintenance
  before update on public.customer_products
  for each row execute function public.customer_product_guard_maintenance();
