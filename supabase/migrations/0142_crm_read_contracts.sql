-- The CRM's "العقود" (contracts) page lists the contracts generated when deals are won. Until now only
-- Customer Service roles could read the contracts table. People with the CRM customers permission
-- can now read the contracts of the customers they can see (the customers' own rules decide which).
create policy contracts_select_crm on public.contracts
  for select using (
    (select public.has_any_module_permission('crm_customers'))
    and exists (select 1 from public.customers c where c.id = contracts.customer_id)
  );
