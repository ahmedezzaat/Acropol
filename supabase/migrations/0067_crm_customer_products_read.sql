-- The CRM customer profile shows the products a customer bought (Customer
-- Service products). Anyone who can open CRM customers may read the products of
-- the customers they can see, and the funnel stage names those products carry.
create policy customer_products_select_crm on public.customer_products
  for select using (
    public.has_any_module_permission('crm_customers')
    and exists (select 1 from public.customers c where c.id = customer_products.customer_id)
  );

create policy cs_pipelines_select_crm on public.cs_pipelines
  for select using (public.has_any_module_permission('crm_customers'));

create policy cs_pipeline_stages_select_crm on public.cs_pipeline_stages
  for select using (public.has_any_module_permission('crm_customers'));
