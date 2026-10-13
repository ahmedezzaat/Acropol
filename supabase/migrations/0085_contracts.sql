-- Contracts. A customer has one or more contracts; a contract holds one or more
-- products. A contract is the won deal (deal_id) when it came from the CRM, or a
-- contract recorded directly in Customer Service (imports, older customers).
--
-- The contract is the single place for the code and date: its products carry a
-- copy (contract_code / contract_date), kept in step by triggers, so every
-- screen that already reads those columns keeps working.
create table public.contracts (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  deal_id uuid unique references public.deals (id) on delete set null,
  code text,
  signed_on date,
  notes text,
  created_by uuid references public.profiles (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index contracts_customer on public.contracts (customer_id);

create trigger contracts_set_updated_at
  before update on public.contracts
  for each row execute function public.set_updated_at();

alter table public.customer_products
  add column contract_id uuid references public.contracts (id) on delete set null;
create index customer_products_contract on public.customer_products (contract_id);

-- Same visibility as the products: whoever can see the customer sees its contracts.
alter table public.contracts enable row level security;
create policy contracts_select on public.contracts
  for select using (
    (public.has_any_module_permission('cs_customers') or public.has_any_module_permission('cs_maintenance'))
    and exists (select 1 from public.customers c where c.id = contracts.customer_id)
  );
create policy contracts_insert on public.contracts
  for insert with check (
    public.has_permission('cs_customers', 'edit')
    and exists (select 1 from public.customers c where c.id = contracts.customer_id)
  );
create policy contracts_update on public.contracts
  for update
  using (
    public.has_permission('cs_customers', 'edit')
    and exists (select 1 from public.customers c where c.id = contracts.customer_id)
  )
  with check (
    public.has_permission('cs_customers', 'edit')
    and exists (select 1 from public.customers c where c.id = contracts.customer_id)
  );
create policy contracts_delete on public.contracts
  for delete using (
    public.has_permission('cs_customers', 'edit')
    and exists (select 1 from public.customers c where c.id = contracts.customer_id)
  );

-- ---- Backfill: group the existing products into contracts.
-- One contract per won deal that has products...
insert into public.contracts (customer_id, deal_id, code, signed_on, created_by, created_at)
select p.customer_id, p.deal_id,
       (array_agg(nullif(btrim(p.contract_code), '') order by p.created_at) filter (where nullif(btrim(p.contract_code), '') is not null))[1],
       min(p.contract_date),
       (array_agg(p.created_by order by p.created_at))[1],
       min(p.created_at)
from public.customer_products p
where p.deal_id is not null
group by p.customer_id, p.deal_id;

update public.customer_products p
set contract_id = c.id
from public.contracts c
where p.deal_id is not null and c.deal_id = p.deal_id;

-- ...and one per customer and contract code for the rest. Products without a
-- code stay without a contract (shown separately until one is assigned).
insert into public.contracts (customer_id, code, signed_on, created_by, created_at)
select p.customer_id, btrim(p.contract_code), min(p.contract_date),
       (array_agg(p.created_by order by p.created_at))[1], min(p.created_at)
from public.customer_products p
where p.deal_id is null and nullif(btrim(p.contract_code), '') is not null
group by p.customer_id, btrim(p.contract_code);

update public.customer_products p
set contract_id = c.id
from public.contracts c
where p.contract_id is null and p.deal_id is null
  and c.deal_id is null and c.customer_id = p.customer_id and c.code = btrim(p.contract_code);

-- ---- Keep the product copies in step with their contract (created after the
-- backfill so it does not rewrite products while they are being linked).
create or replace function public.customer_product_sync_contract()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_contract public.contracts;
begin
  if new.contract_id is null then
    return new;
  end if;
  select * into v_contract from public.contracts where id = new.contract_id;
  if not found or v_contract.customer_id <> new.customer_id then
    raise exception 'the contract belongs to another customer';
  end if;
  new.contract_code := v_contract.code;
  new.contract_date := v_contract.signed_on;
  return new;
end;
$$;

create trigger customer_products_01_sync_contract
  before insert or update of contract_id on public.customer_products
  for each row execute function public.customer_product_sync_contract();

create or replace function public.contract_sync_products()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.customer_products
  set contract_code = new.code, contract_date = new.signed_on
  where contract_id = new.id
    and (contract_code is distinct from new.code or contract_date is distinct from new.signed_on);
  return new;
end;
$$;

create trigger contracts_sync_products
  after update of code, signed_on on public.contracts
  for each row execute function public.contract_sync_products();

-- ---- Winning a deal records its contract (one per deal) with the products.
-- p_contract is optional so an older client that sends the code and date on
-- each product keeps working. Replaces the earlier two-argument version.
drop function if exists public.crm_record_deal_products(uuid, jsonb);
create or replace function public.crm_record_deal_products(p_deal_id uuid, p_products jsonb, p_contract jsonb default null)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deal public.deals;
  v_first uuid;
  v_item jsonb;
  v_count int := 0;
  v_contract uuid;
  v_code text;
  v_date date;
begin
  select * into v_deal from public.deals where id = p_deal_id;
  if not found then
    raise exception 'deal not found';
  end if;

  -- Same visibility and permission as changing the deal itself.
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
    raise exception 'insufficient permission to record products for this deal';
  end if;

  if v_deal.customer_id is null then
    raise exception 'the deal has no customer yet';
  end if;
  if p_products is null or jsonb_typeof(p_products) <> 'array' or jsonb_array_length(p_products) = 0 then
    raise exception 'at least one product is required';
  end if;

  select s.id into v_first
  from public.cs_pipeline_stages s
  join public.cs_pipelines p on p.id = s.pipeline_id
  order by p.sort_order, s.sort_order
  limit 1;

  delete from public.customer_products cp
  where cp.deal_id = p_deal_id
    and cp.created_by = auth.uid()
    and cp.created_at > now() - interval '2 hours'
    and cp.stage_id = v_first;

  -- The deal is the contract: one per deal, holding the code and date (taken
  -- from the first product when an older client sends them per product).
  v_code := nullif(btrim(coalesce(p_contract ->> 'contract_code', p_products -> 0 ->> 'contract_code', '')), '');
  v_date := coalesce(nullif(p_contract ->> 'contract_date', '')::date, nullif(p_products -> 0 ->> 'contract_date', '')::date);
  insert into public.contracts (customer_id, deal_id, code, signed_on, created_by)
  values (v_deal.customer_id, p_deal_id, v_code, v_date, auth.uid())
  on conflict (deal_id) do update
    set code = coalesce(excluded.code, public.contracts.code),
        signed_on = coalesce(excluded.signed_on, public.contracts.signed_on)
  returning id into v_contract;

  for v_item in select * from jsonb_array_elements(p_products) loop
    if coalesce(btrim(v_item ->> 'name'), '') = '' then
      raise exception 'every product needs a name';
    end if;
    insert into public.customer_products (
      customer_id, deal_id, name, category_id, contract_code, contract_date,
      sales_person_id, warranty_status, warranty_details, payment_status, notes, quantity, contract_id, created_by
    ) values (
      v_deal.customer_id,
      p_deal_id,
      btrim(v_item ->> 'name'),
      nullif(v_item ->> 'category_id', '')::uuid,
      nullif(btrim(coalesce(v_item ->> 'contract_code', '')), ''),
      nullif(v_item ->> 'contract_date', '')::date,
      nullif(v_item ->> 'sales_person_id', '')::uuid,
      nullif(v_item ->> 'warranty_status', ''),
      nullif(btrim(coalesce(v_item ->> 'warranty_details', '')), ''),
      nullif(v_item ->> 'payment_status', ''),
      nullif(btrim(coalesce(v_item ->> 'notes', '')), ''),
      greatest(coalesce(nullif(v_item ->> 'quantity', '')::int, 1), 1),
      v_contract,
      auth.uid()
    );
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;
