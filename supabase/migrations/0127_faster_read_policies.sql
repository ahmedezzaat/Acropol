-- Speed: the read rules of the biggest tables called the permission functions once per
-- row (a list of 1,500 customers ran them 1,500 times, and every list that checks the
-- customer ran the customers rule again for each of its rows). Wrapping the checks that
-- do not depend on the row in (select ...) makes the database work them out once per
-- query. The functions are STABLE and the rules say exactly what they said before.

drop policy customers_cs_select on public.customers;
create policy customers_cs_select on public.customers
  for select using (
    (
      (select public.has_any_module_permission('cs_customers'))
      and (
        (select public.has_permission('cs_customers', 'view_all'))
        or cs_agent_id = (select auth.uid())
        or created_by = (select auth.uid())
      )
    )
    -- a maintenance-only role (no Customer Service customer access at all) sees
    -- the customers its maintenance work involves
    or ((select public.cs_maintenance_full()) and not (select public.has_any_module_permission('cs_customers')))
    -- a confirmed-visits-only role sees the customers of the visits it may see
    or public.cs_customer_has_visible_visit(id)
  );

drop policy customers_select on public.customers;
create policy customers_select on public.customers
  for select using (
    (select public.has_any_module_permission('crm_customers'))
    and (
      (select public.has_permission('crm_customers', 'view_all'))
      or assigned_to = (select auth.uid())
      or created_by = (select auth.uid())
      or public.leads_my_team(assigned_to)
      or public.leads_my_team(created_by)
    )
  );

drop policy contracts_select on public.contracts;
create policy contracts_select on public.contracts
  for select using (
    ((select public.has_any_module_permission('cs_customers')) or (select public.has_any_module_permission('cs_maintenance')))
    and exists (select 1 from public.customers c where c.id = contracts.customer_id)
  );

drop policy customer_products_select on public.customer_products;
create policy customer_products_select on public.customer_products
  for select using (
    (
      ((select public.has_any_module_permission('cs_customers')) or (select public.cs_maintenance_full()))
      and exists (select 1 from public.customers c where c.id = customer_products.customer_id)
    )
    or public.cs_confirmed_visit_access(maintenance_technician_id, maintenance_confirmed_at, next_maintenance_at)
  );

drop policy customer_products_select_crm on public.customer_products;
create policy customer_products_select_crm on public.customer_products
  for select using (
    (select public.has_any_module_permission('crm_customers'))
    and exists (select 1 from public.customers c where c.id = customer_products.customer_id)
  );

drop policy deals_select on public.deals;
create policy deals_select on public.deals
  for select using (
    (select public.has_any_module_permission('crm_deals'))
    and (
      (select public.has_permission('crm_deals', 'view_all'))
      or assigned_to = (select auth.uid())
      or created_by = (select auth.uid())
      or public.leads_my_team(assigned_to)
      or public.leads_my_team(created_by)
    )
  );

drop policy leads_select on public.leads;
create policy leads_select on public.leads
  for select using (
    (select public.has_any_module_permission('crm_leads'))
    and (
      (select public.has_permission('crm_leads', 'view_all'))
      or assigned_to = (select auth.uid())
      or created_by = (select auth.uid())
      or public.leads_my_team(assigned_to)
      or public.leads_my_team(created_by)
    )
  );
