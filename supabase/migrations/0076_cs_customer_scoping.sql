-- Customer Service: managers and agents.
--  * Each customer can be assigned to a Customer Service agent (cs_agent_id,
--    separate from the CRM owner, so the two never fight over one column).
--  * Without "view all" on cs_customers an agent sees only the customers
--    assigned to them (or that they created), and everything that hangs off
--    those: products, installations, maintenance and its log.
--  * Assigning a customer to an agent needs the "assign" permission.
alter table public.customers
  add column cs_agent_id uuid references public.profiles (id) on delete set null;
create index customers_cs_agent on public.customers (cs_agent_id);

-- Nobody loses access: roles that already work in Customer Service keep seeing
-- every customer, until a manager takes "view all" away from the agent role.
insert into public.role_permissions (role_id, module, action)
select distinct rp.role_id, 'cs_customers', 'view_all'
from public.role_permissions rp
where rp.module = 'cs_customers'
on conflict do nothing;

create or replace function public.customers_cs_agent_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.cs_agent_id is not null
       and new.cs_agent_id is distinct from auth.uid()
       and not public.has_permission('cs_customers', 'assign') then
      raise exception 'insufficient permission to assign this customer';
    end if;
  elsif new.cs_agent_id is distinct from old.cs_agent_id
        and not public.has_permission('cs_customers', 'assign') then
    raise exception 'insufficient permission to reassign this customer';
  end if;
  return new;
end;
$$;

create trigger customers_cs_agent_guard
  before insert or update on public.customers
  for each row execute function public.customers_cs_agent_guard();

-- Customers
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
    or (public.has_any_module_permission('cs_maintenance') and not public.has_any_module_permission('cs_customers'))
  );

drop policy customers_cs_update on public.customers;
create policy customers_cs_update on public.customers
  for update
  using (
    public.has_permission('cs_customers', 'edit')
    and (public.has_permission('cs_customers', 'view_all') or cs_agent_id = auth.uid() or created_by = auth.uid())
  )
  with check (
    public.has_permission('cs_customers', 'edit')
    and (public.has_permission('cs_customers', 'view_all') or cs_agent_id = auth.uid() or created_by = auth.uid())
  );

drop policy customers_cs_delete on public.customers;
create policy customers_cs_delete on public.customers
  for delete using (
    public.has_permission('cs_customers', 'delete')
    and (public.has_permission('cs_customers', 'view_all') or cs_agent_id = auth.uid() or created_by = auth.uid())
  );

-- Products follow their customer: visible when the customer is (the customers
-- policies above apply inside these checks).
drop policy customer_products_select on public.customer_products;
create policy customer_products_select on public.customer_products
  for select using (
    (public.has_any_module_permission('cs_customers') or public.has_any_module_permission('cs_maintenance'))
    and exists (select 1 from public.customers c where c.id = customer_products.customer_id)
  );

drop policy customer_products_insert on public.customer_products;
create policy customer_products_insert on public.customer_products
  for insert with check (
    public.has_permission('cs_customers', 'edit')
    and exists (select 1 from public.customers c where c.id = customer_products.customer_id)
  );

drop policy customer_products_update on public.customer_products;
create policy customer_products_update on public.customer_products
  for update
  using (
    public.has_permission('cs_customers', 'edit')
    and exists (select 1 from public.customers c where c.id = customer_products.customer_id)
  )
  with check (
    public.has_permission('cs_customers', 'edit')
    and exists (select 1 from public.customers c where c.id = customer_products.customer_id)
  );

drop policy customer_products_delete on public.customer_products;
create policy customer_products_delete on public.customer_products
  for delete using (
    public.has_permission('cs_customers', 'edit')
    and exists (select 1 from public.customers c where c.id = customer_products.customer_id)
  );

drop policy customer_products_update_maintenance on public.customer_products;
create policy customer_products_update_maintenance on public.customer_products
  for update
  using (
    (
      public.has_permission('cs_maintenance', 'schedule')
      or public.has_permission('cs_maintenance', 'complete')
      or public.has_permission('cs_maintenance', 'cancel')
    )
    and exists (select 1 from public.customers c where c.id = customer_products.customer_id)
  )
  with check (
    (
      public.has_permission('cs_maintenance', 'schedule')
      or public.has_permission('cs_maintenance', 'complete')
      or public.has_permission('cs_maintenance', 'cancel')
    )
    and exists (select 1 from public.customers c where c.id = customer_products.customer_id)
  );

-- What hangs off a product follows the product.
drop policy customer_product_items_select on public.customer_product_items;
create policy customer_product_items_select on public.customer_product_items
  for select using (
    (public.has_any_module_permission('cs_customers') or public.has_any_module_permission('cs_maintenance'))
    and exists (select 1 from public.customer_products p where p.id = customer_product_items.product_id)
  );
drop policy customer_product_items_write on public.customer_product_items;
create policy customer_product_items_write on public.customer_product_items
  for all
  using (public.has_permission('cs_customers', 'edit') and exists (select 1 from public.customer_products p where p.id = customer_product_items.product_id))
  with check (public.has_permission('cs_customers', 'edit') and exists (select 1 from public.customer_products p where p.id = customer_product_items.product_id));

drop policy customer_product_stage_dates_select on public.customer_product_stage_dates;
create policy customer_product_stage_dates_select on public.customer_product_stage_dates
  for select using (
    (public.has_any_module_permission('cs_customers') or public.has_any_module_permission('cs_maintenance'))
    and exists (select 1 from public.customer_products p where p.id = customer_product_stage_dates.product_id)
  );
drop policy customer_product_stage_dates_write on public.customer_product_stage_dates;
create policy customer_product_stage_dates_write on public.customer_product_stage_dates
  for all
  using (public.has_permission('cs_customers', 'edit') and exists (select 1 from public.customer_products p where p.id = customer_product_stage_dates.product_id))
  with check (public.has_permission('cs_customers', 'edit') and exists (select 1 from public.customer_products p where p.id = customer_product_stage_dates.product_id));

drop policy product_maintenance_log_select on public.product_maintenance_log;
create policy product_maintenance_log_select on public.product_maintenance_log
  for select using (
    public.has_any_module_permission('cs_maintenance')
    and exists (select 1 from public.customer_products p where p.id = product_maintenance_log.product_id)
  );
