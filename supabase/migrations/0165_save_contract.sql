-- One contract form for both places a contract is made: winning a deal (the Won window on the deal) and
-- "إنشاء عقد" on the contracts page. Both now ask for the same things and save through crm_save_contract:
--   the contract: code, date, value (required), sales person, notes, file (optional)
--   the products bought (at least one), whose code and date are the contract's
-- The file always goes on the contract (contract-files); the deal's Files tab shows it.

-- p_deal_id: the deal being won (its contract is created, or completed if one exists already), or null
-- p_customer_id: the customer (required without a deal; with a deal, used when the deal has none yet)
-- p_contract: { id?, code, signed_on, value, notes?, sales_person_id?, deal_id? (link, without p_deal_id), file_name?, file_path? }
-- p_products: [{ name, category_id, quantity, sales_person_id?, warranty_status?, warranty_details?, payment_status?, notes? }]
create or replace function public.crm_save_contract(p_deal_id uuid, p_customer_id uuid, p_contract jsonb, p_products jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deal public.deals;
  v_customer uuid := p_customer_id;
  v_link uuid := nullif(p_contract ->> 'deal_id', '')::uuid;
  v_id uuid := coalesce(nullif(p_contract ->> 'id', '')::uuid, gen_random_uuid());
  v_code text := nullif(btrim(coalesce(p_contract ->> 'code', '')), '');
  v_date date := nullif(p_contract ->> 'signed_on', '')::date;
  v_value numeric := nullif(p_contract ->> 'value', '')::numeric;
  v_seller uuid := nullif(p_contract ->> 'sales_person_id', '')::uuid;
  v_existing uuid;
  v_first uuid;
  v_item jsonb;
begin
  if p_deal_id is not null then
    select * into v_deal from public.deals where id = p_deal_id;
    if not found then raise exception 'deal not found'; end if;
    -- the same visibility and permission as changing the deal itself
    if not (
      (public.has_permission('crm_deals', 'edit') or public.has_permission('crm_deals', 'create'))
      and (
        public.has_permission('crm_deals', 'view_all')
        or v_deal.assigned_to = auth.uid()
        or v_deal.created_by = auth.uid()
        or public.leads_my_team(v_deal.assigned_to)
        or public.leads_my_team(v_deal.created_by)
      )
    ) then
      raise exception 'insufficient permission to record the contract of this deal';
    end if;
    if v_deal.customer_id is null then
      if v_customer is null or not exists (select 1 from public.customers where id = v_customer) then
        raise exception 'the deal has no customer yet';
      end if;
      update public.deals set customer_id = v_customer where id = p_deal_id;
    else
      v_customer := v_deal.customer_id;
    end if;
    v_link := p_deal_id;
  else
    if not public.has_permission('crm_customers', 'create') then
      raise exception 'insufficient permission to create contracts';
    end if;
    if not exists (
      select 1 from public.customers c
      where c.id = v_customer
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
    if v_link is not null and not exists (select 1 from public.deals d where d.id = v_link and d.customer_id = v_customer) then
      raise exception 'deal does not belong to this customer';
    end if;
  end if;

  if v_code is null then raise exception 'contract_code_required'; end if;
  if v_date is null then raise exception 'contract_date_required'; end if;
  if v_value is null or v_value < 0 then raise exception 'contract_value_required'; end if;
  if p_products is null or jsonb_typeof(p_products) <> 'array' or jsonb_array_length(p_products) = 0 then
    raise exception 'at least one product is required';
  end if;
  if v_seller is not null and not exists (select 1 from public.profiles where id = v_seller and is_active) then
    raise exception 'sales person not found';
  end if;

  -- a deal has one contract: complete the one that exists (made by hand earlier, or by a first try)
  if v_link is not null then
    select id into v_existing from public.contracts where deal_id = v_link;
  end if;
  if v_existing is not null then
    v_id := v_existing;
    update public.contracts set
      code = v_code, signed_on = v_date, value = v_value,
      notes = coalesce(nullif(btrim(coalesce(p_contract ->> 'notes', '')), ''), notes),
      sales_person_id = coalesce(v_seller, sales_person_id),
      file_name = coalesce(nullif(p_contract ->> 'file_name', ''), file_name),
      file_path = coalesce(nullif(p_contract ->> 'file_path', ''), file_path)
    where id = v_id;
    -- products this person added in a failed attempt a moment ago are replaced, not doubled
    select s.id into v_first from public.cs_pipeline_stages s join public.cs_pipelines p on p.id = s.pipeline_id
    order by p.sort_order, s.sort_order limit 1;
    delete from public.customer_products cp
    where cp.contract_id = v_id and cp.created_by = auth.uid() and cp.created_at > now() - interval '2 hours' and cp.stage_id = v_first;
  else
    insert into public.contracts (id, customer_id, deal_id, code, signed_on, value, notes, sales_person_id, file_name, file_path, created_by)
    values (
      v_id, v_customer, v_link, v_code, v_date, v_value,
      nullif(btrim(coalesce(p_contract ->> 'notes', '')), ''), v_seller,
      nullif(p_contract ->> 'file_name', ''), nullif(p_contract ->> 'file_path', ''),
      auth.uid()
    );
  end if;

  for v_item in select * from jsonb_array_elements(p_products) loop
    if coalesce(btrim(v_item ->> 'name'), '') = '' then
      raise exception 'every product needs a name';
    end if;
    insert into public.customer_products (
      customer_id, deal_id, name, category_id, contract_code, contract_date,
      sales_person_id, warranty_status, warranty_details, payment_status, notes, quantity, contract_id, created_by
    ) values (
      v_customer, v_link, btrim(v_item ->> 'name'), nullif(v_item ->> 'category_id', '')::uuid,
      v_code, v_date,
      coalesce(nullif(v_item ->> 'sales_person_id', '')::uuid, v_seller),
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
revoke all on function public.crm_save_contract(uuid, uuid, jsonb, jsonb) from public, anon;
grant execute on function public.crm_save_contract(uuid, uuid, jsonb, jsonb) to authenticated;

-- A deal can be Won once it has its contract: a contract record (the new way) or, as before, a contract file on the deal.
create or replace function public.deal_require_won_contract()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return new;
  end if;
  if new.stage_id is distinct from old.stage_id
     and exists (select 1 from public.pipeline_stages s where s.id = new.stage_id and s.system_key = 'won')
     and not exists (select 1 from public.contracts c where c.deal_id = new.id)
     and not exists (select 1 from public.deal_attachments a where a.deal_id = new.id and a.kind = 'contract') then
    raise exception 'won_requires_contract';
  end if;
  return new;
end;
$$;

-- People who work deals see the contract of a deal they can see (its Files tab shows the contract file),
-- and may attach the file when they win the deal.
create policy contracts_select_deals on public.contracts
  for select using (
    (select public.has_any_module_permission('crm_deals'))
    and deal_id is not null
    and exists (select 1 from public.deals d where d.id = contracts.deal_id)
  );
create policy contract_files_insert_deals on storage.objects for insert
  with check (bucket_id = 'contract-files' and (public.has_permission('crm_deals', 'edit') or public.has_permission('crm_deals', 'create')));
create policy contract_files_select_deals on storage.objects for select
  using (bucket_id = 'contract-files' and public.has_any_module_permission('crm_deals'));
