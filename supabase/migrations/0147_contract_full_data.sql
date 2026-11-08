-- A contract made by hand on the CRM's "العقود" page holds everything a won deal records: the code and
-- date, the contract's value, the contract file, and the products bought (with their warranty, payment,
-- salesperson and notes). The value and the file live on the contract itself; the file in a private bucket.

alter table public.contracts
  add column value numeric check (value is null or value >= 0),
  add column file_name text,
  add column file_path text;

insert into storage.buckets (id, name, public) values ('contract-files', 'contract-files', false) on conflict (id) do nothing;
-- who may add, read and remove a contract's file: the roles that work with contracts
create policy contract_files_insert on storage.objects for insert
  with check (bucket_id = 'contract-files' and (public.has_permission('crm_customers', 'create') or public.has_permission('cs_customers', 'edit')));
create policy contract_files_select on storage.objects for select
  using (bucket_id = 'contract-files' and (
    public.has_any_module_permission('crm_customers') or public.has_any_module_permission('cs_customers') or public.has_any_module_permission('cs_maintenance')));
create policy contract_files_delete on storage.objects for delete
  using (bucket_id = 'contract-files' and (public.has_permission('crm_customers', 'create') or public.has_permission('cs_customers', 'edit')));

-- Creates the contract and its products in one step, for a customer the caller can see.
-- p_contract: { id?, code, signed_on, value, notes, deal_id?, file_name?, file_path? }
-- p_products: the same list a won deal records. Returns the contract's id.
create or replace function public.crm_create_contract(p_customer_id uuid, p_contract jsonb, p_products jsonb default '[]'::jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid := coalesce(nullif(p_contract ->> 'id', '')::uuid, gen_random_uuid());
  v_code text := nullif(btrim(coalesce(p_contract ->> 'code', '')), '');
  v_date date := nullif(p_contract ->> 'signed_on', '')::date;
  v_deal uuid := nullif(p_contract ->> 'deal_id', '')::uuid;
  v_item jsonb;
begin
  if not public.has_permission('crm_customers', 'create') then
    raise exception 'insufficient permission to create contracts';
  end if;
  -- the same customers the CRM lets this person see
  if not exists (
    select 1 from public.customers c
    where c.id = p_customer_id
      and (
        public.has_permission('crm_customers', 'view_all')
        or c.assigned_to = auth.uid()
        or c.created_by = auth.uid()
        or public.leads_my_team(c.assigned_to)
        or public.leads_my_team(c.created_by)
      )
  ) then
    raise exception 'customer not found';
  end if;
  if v_code is null then raise exception 'contract_code_required'; end if;
  if v_deal is not null and not exists (select 1 from public.deals d where d.id = v_deal and d.customer_id = p_customer_id) then
    raise exception 'deal does not belong to this customer';
  end if;

  insert into public.contracts (id, customer_id, deal_id, code, signed_on, value, notes, file_name, file_path, created_by)
  values (
    v_id, p_customer_id, v_deal, v_code, v_date,
    nullif(p_contract ->> 'value', '')::numeric,
    nullif(btrim(coalesce(p_contract ->> 'notes', '')), ''),
    nullif(p_contract ->> 'file_name', ''), nullif(p_contract ->> 'file_path', ''),
    auth.uid()
  );

  for v_item in select * from jsonb_array_elements(coalesce(p_products, '[]'::jsonb)) loop
    if coalesce(btrim(v_item ->> 'name'), '') = '' then
      raise exception 'every product needs a name';
    end if;
    insert into public.customer_products (
      customer_id, deal_id, name, category_id, contract_code, contract_date,
      sales_person_id, warranty_status, warranty_details, payment_status, notes, quantity, contract_id, created_by
    ) values (
      p_customer_id, v_deal, btrim(v_item ->> 'name'), nullif(v_item ->> 'category_id', '')::uuid,
      v_code, v_date,
      nullif(v_item ->> 'sales_person_id', '')::uuid,
      nullif(v_item ->> 'warranty_status', ''),
      nullif(btrim(coalesce(v_item ->> 'warranty_details', '')), ''),
      nullif(v_item ->> 'payment_status', ''),
      nullif(btrim(coalesce(v_item ->> 'notes', '')), ''),
      greatest(coalesce(nullif(v_item ->> 'quantity', '')::int, 1), 1),
      v_id, auth.uid()
    );
  end loop;
  return v_id;
end;
$$;
revoke all on function public.crm_create_contract(uuid, jsonb, jsonb) from public, anon;
grant execute on function public.crm_create_contract(uuid, jsonb, jsonb) to authenticated;
