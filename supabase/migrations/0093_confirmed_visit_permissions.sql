-- Two new Maintenance permissions for the Confirmed visits page:
--   view_confirmed_own  see the confirmed visits assigned to me
--   view_confirmed_all  see every confirmed visit
-- A role that holds only one of these (a technician) sees only that: the
-- maintenance appointments the customer confirmed (all of them, or the ones
-- assigned to the user) and the customers, products and history those involve.
-- It does not open the Maintenance list, the customers list or anything else.
-- The other Maintenance permissions (view, schedule, complete, cancel, note)
-- keep working exactly as before.

-- Roles that already work on maintenance keep seeing every confirmed visit.
insert into public.role_permissions (role_id, module, action)
select distinct rp.role_id, 'cs_maintenance', 'view_confirmed_all'
from public.role_permissions rp
where rp.module = 'cs_maintenance'
on conflict do nothing;

-- "Full" maintenance access: any permission other than the two above (or admin).
create or replace function public.cs_maintenance_full()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles pr
    join public.role_permissions rp on rp.role_id = pr.role_id
    where pr.id = auth.uid() and pr.is_active
      and rp.module = 'cs_maintenance'
      and rp.action in ('view', 'schedule', 'complete', 'cancel', 'note')
  ) or exists (select 1 from public.profiles pr where pr.id = auth.uid() and pr.is_admin and pr.is_active);
$$;

-- May the caller see this product as a confirmed visit?
create or replace function public.cs_confirmed_visit_access(p_technician uuid, p_confirmed_at timestamptz, p_next timestamptz)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select p_confirmed_at is not null and p_next is not null and (
    public.has_permission('cs_maintenance', 'view_confirmed_all')
    or (public.has_permission('cs_maintenance', 'view_confirmed_own') and p_technician = auth.uid())
  );
$$;

-- ...and this customer, because one of its confirmed visits is visible?
create or replace function public.cs_customer_has_visible_visit(p_customer uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.customer_products p
    where p.customer_id = p_customer
      and public.cs_confirmed_visit_access(p.maintenance_technician_id, p.maintenance_confirmed_at, p.next_maintenance_at)
  );
$$;

drop policy customer_products_select on public.customer_products;
create policy customer_products_select on public.customer_products
  for select using (
    (
      (public.has_any_module_permission('cs_customers') or public.cs_maintenance_full())
      and exists (select 1 from public.customers c where c.id = customer_products.customer_id)
    )
    or public.cs_confirmed_visit_access(maintenance_technician_id, maintenance_confirmed_at, next_maintenance_at)
  );

drop policy customers_cs_select on public.customers;
create policy customers_cs_select on public.customers
  for select using (
    (
      public.has_any_module_permission('cs_customers')
      and (
        public.has_permission('cs_customers', 'view_all')
        or cs_agent_id = auth.uid()
        or created_by = auth.uid()
      )
    )
    -- a maintenance-only role (no Customer Service customer access at all) sees
    -- the customers its maintenance work involves
    or (public.cs_maintenance_full() and not public.has_any_module_permission('cs_customers'))
    -- a confirmed-visits-only role sees the customers of the visits it may see
    or public.cs_customer_has_visible_visit(customers.id)
  );
