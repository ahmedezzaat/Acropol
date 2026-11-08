-- Creating a contract from the CRM's "العقود" page. Until now only Customer Service roles could add a contract.
-- People with the CRM customers "create" permission can now add a contract for a customer they can see
-- (the customers' own rules decide which), and may tie it to one of that customer's deals they can see.
create policy contracts_insert_crm on public.contracts
  for insert with check (
    (select public.has_permission('crm_customers', 'create'))
    and exists (select 1 from public.customers c where c.id = contracts.customer_id)
    and (
      contracts.deal_id is null
      or exists (select 1 from public.deals d where d.id = contracts.deal_id and d.customer_id = contracts.customer_id)
    )
  );
