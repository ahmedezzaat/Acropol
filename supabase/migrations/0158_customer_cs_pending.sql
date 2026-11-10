-- A customer made from a contract or a won deal is "pending" until someone clicks "إنشاء عميل وإرسال إلى خدمة العملاء"
-- on the contract: until then Customer Service does not see them (nor their contracts and products, which follow the
-- customer's visibility); the CRM sees and works with them as before. Sending them to Customer Service (the existing
-- crm_push_customer_to_cs) makes them a real Customer Service customer.

alter table public.customers add column cs_pending boolean not null default false;
comment on column public.customers.cs_pending is 'Made from a contract or won deal and not yet sent to Customer Service: hidden from Customer Service until pushed';

drop policy customers_cs_select on public.customers;
create policy customers_cs_select on public.customers
  for select using (
    (
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
    )
    and not cs_pending
  );

-- Converting a lead: p_pending true makes the customer pending (used by contracts and won deals); the lead page's own
-- "convert to customer" button keeps making a normal customer.
drop function public.crm_convert_lead(uuid);
create or replace function public.crm_convert_lead(p_lead_id uuid, p_pending boolean default false)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer_id uuid;
  v_lead record;
begin
  if not public.has_permission('crm_customers', 'create') then
    raise exception 'insufficient permission to create customer';
  end if;

  select * into v_lead from public.leads where id = p_lead_id;
  if not found then
    raise exception 'lead % not found', p_lead_id;
  end if;

  -- security definer bypasses the leads RLS policy's row-scoping, so it's
  -- re-checked explicitly here — otherwise a user without view_all could
  -- convert a lead they have no visibility into.
  if not (
    public.has_permission('crm_leads', 'edit')
    and (
      public.has_permission('crm_leads', 'view_all')
      or v_lead.assigned_to = auth.uid()
      or v_lead.created_by = auth.uid()
    )
  ) then
    raise exception 'insufficient permission to convert this lead';
  end if;

  insert into public.customers (name, company, phone, extra_phones, email, area_id, converted_from_lead_id, created_by, cs_pending)
  values (
    v_lead.name,
    case when v_lead.lead_type = 'company' then v_lead.company_name else null end,
    v_lead.phone,
    case when nullif(btrim(coalesce(v_lead.phone2, '')), '') is not null then array[v_lead.phone2] else '{}'::text[] end,
    v_lead.email,
    v_lead.area_id,
    p_lead_id,
    auth.uid(),
    coalesce(p_pending, false)
  )
  returning id into v_customer_id;

  update public.leads
  set status = 'converted', customer_id = v_customer_id
  where id = p_lead_id;

  return v_customer_id;
end;
$$;
grant execute on function public.crm_convert_lead(uuid, boolean) to authenticated;

-- Sending to Customer Service also ends the "pending" state.
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
      cs_agent_id = coalesce(p_cs_agent_id, cs_agent_id),
      cs_pending = false
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
