-- Deleting a contract from the CRM "العقود" page: people with the CRM customers "delete" permission may delete the
-- contracts of customers they can see, and the contract's file. (The customer's products stay: their contract link
-- is simply cleared.)
create policy contracts_delete_crm on public.contracts
  for delete using (
    (select public.has_permission('crm_customers', 'delete'))
    and exists (select 1 from public.customers c where c.id = contracts.customer_id)
  );
create policy contract_files_delete_crm on storage.objects for delete
  using (bucket_id = 'contract-files' and public.has_permission('crm_customers', 'delete'));
