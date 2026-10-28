-- Pushing a customer from the CRM to Customer Service: someone with the
-- "push_to_cs" permission on crm_customers fills what is missing (area, address),
-- hands the customer to a Customer Service agent and can record the products the
-- customer bought. These people may not be allowed to edit Customer Service data
-- directly, so it all goes through one function that checks that permission.

-- The agent guard lets this function through (and only it) by a flag it sets for
-- the duration of its own transaction.
create or replace function public.customers_cs_agent_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or current_setting('app.pushing_to_cs', true) = 'on' then
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

-- The Customer Service agents someone pushing a customer can choose from.
create or replace function public.crm_cs_agents()
returns table (id uuid, full_name text, email text)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.has_permission('crm_customers', 'push_to_cs') then
    raise exception 'insufficient permission to push customers to Customer Service';
  end if;
  return query
  select p.id, p.full_name, p.email
  from public.profiles p
  where p.is_active
    and (
      p.is_admin
      or exists (
        select 1 from public.role_permissions rp
        where rp.role_id = p.role_id and rp.module in ('cs_customers', 'cs_maintenance')
      )
    )
  order by coalesce(nullif(p.full_name, ''), p.email);
end;
$$;
grant execute on function public.crm_cs_agents() to authenticated;

-- Fills the customer's gaps (only what is given; nothing is cleared), assigns the
-- agent and adds the products. Returns how many products were added.
create or replace function public.crm_push_customer_to_cs(
  p_customer_id uuid,
  p_area_id uuid,
  p_address text,
  p_cs_agent_id uuid,
  p_products jsonb default '[]'::jsonb
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item jsonb;
  v_count integer := 0;
begin
  if not public.has_permission('crm_customers', 'push_to_cs') then
    raise exception 'insufficient permission to push customers to Customer Service';
  end if;
  if not exists (select 1 from public.customers where id = p_customer_id) then
    raise exception 'customer not found';
  end if;
  if p_cs_agent_id is not null and not exists (
    select 1 from public.profiles p
    where p.id = p_cs_agent_id and p.is_active
      and (p.is_admin or exists (
        select 1 from public.role_permissions rp
        where rp.role_id = p.role_id and rp.module in ('cs_customers', 'cs_maintenance')))
  ) then
    raise exception 'that user does not work in Customer Service';
  end if;

  perform set_config('app.pushing_to_cs', 'on', true);
  update public.customers
  set area_id = coalesce(p_area_id, area_id),
      address = coalesce(nullif(btrim(coalesce(p_address, '')), ''), address),
      cs_agent_id = coalesce(p_cs_agent_id, cs_agent_id)
  where id = p_customer_id;
  perform set_config('app.pushing_to_cs', 'off', true);

  for v_item in select * from jsonb_array_elements(coalesce(p_products, '[]'::jsonb)) loop
    if coalesce(btrim(v_item ->> 'name'), '') = '' then
      raise exception 'every product needs a name';
    end if;
    insert into public.customer_products (
      customer_id, name, category_id, contract_code, contract_date,
      sales_person_id, warranty_status, warranty_details, payment_status, notes, created_by
    ) values (
      p_customer_id,
      btrim(v_item ->> 'name'),
      nullif(v_item ->> 'category_id', '')::uuid,
      nullif(btrim(coalesce(v_item ->> 'contract_code', '')), ''),
      nullif(v_item ->> 'contract_date', '')::date,
      nullif(v_item ->> 'sales_person_id', '')::uuid,
      nullif(v_item ->> 'warranty_status', ''),
      nullif(btrim(coalesce(v_item ->> 'warranty_details', '')), ''),
      nullif(v_item ->> 'payment_status', ''),
      nullif(btrim(coalesce(v_item ->> 'notes', '')), ''),
      auth.uid()
    );
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;
grant execute on function public.crm_push_customer_to_cs(uuid, uuid, text, uuid, jsonb) to authenticated;
