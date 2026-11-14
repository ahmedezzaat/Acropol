-- المسؤول عن العقد and البائع are one person: changing the contract's sales person changes its products' seller too.
create or replace function public.customer_product_guard_maintenance()
returns trigger
language plpgsql
as $$
declare
  v_skip text[] := array[
    'updated_at', 'next_maintenance_at', 'next_maintenance_note',
    'last_maintenance_on', 'maintenance_declined_at',
    'maintenance_confirmed_at', 'maintenance_confirmed_by', 'maintenance_confirm_note',
    'maintenance_technician_id', 'maintenance_assigned_at',
    'maintenance_confirm_parts', 'maintenance_confirm_fee', 'maintenance_confirm_price_list_id',
    'maintenance_confirm_discount', 'maintenance_confirm_tax_invoice',
    -- the seller follows the contract's sales person (crm_update_contract), which has its own permission check
    'sales_person_id'
  ];
begin
  -- Server-side jobs and scripts (no signed-in user) are not limited.
  if auth.uid() is null then
    return new;
  end if;

  -- Anything other than the maintenance columns is a normal product edit.
  if (to_jsonb(new) - v_skip) is distinct from (to_jsonb(old) - v_skip)
     and not public.has_permission('cs_customers', 'edit') then
    raise exception 'insufficient permission to edit this product';
  end if;

  -- Each maintenance change needs its own action.
  if new.maintenance_declined_at is distinct from old.maintenance_declined_at then
    if not public.has_permission('cs_maintenance', 'cancel') then
      raise exception 'insufficient permission to cancel or resume maintenance';
    end if;
  elsif new.last_maintenance_on is distinct from old.last_maintenance_on then
    if not public.has_permission('cs_maintenance', 'complete') then
      raise exception 'insufficient permission to complete maintenance';
    end if;
  elsif new.next_maintenance_at is distinct from old.next_maintenance_at
     or new.next_maintenance_note is distinct from old.next_maintenance_note
     or new.maintenance_confirmed_at is distinct from old.maintenance_confirmed_at
     or new.maintenance_technician_id is distinct from old.maintenance_technician_id
     or new.maintenance_confirm_parts is distinct from old.maintenance_confirm_parts
     or new.maintenance_confirm_fee is distinct from old.maintenance_confirm_fee
     or new.maintenance_confirm_discount is distinct from old.maintenance_confirm_discount
     or new.maintenance_confirm_tax_invoice is distinct from old.maintenance_confirm_tax_invoice
     or new.maintenance_confirm_price_list_id is distinct from old.maintenance_confirm_price_list_id then
    if not public.has_permission('cs_maintenance', 'schedule') then
      raise exception 'insufficient permission to schedule maintenance';
    end if;
  end if;

  return new;
end;
$$;


create or replace function public.crm_update_contract(p_contract_id uuid, p_patch jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_contract public.contracts%rowtype;
begin
  if not public.has_permission('crm_customers', 'edit') then
    raise exception 'insufficient permission to edit contracts';
  end if;
  select * into v_contract from public.contracts where id = p_contract_id;
  if not found then raise exception 'contract not found'; end if;
  -- the same customers the CRM lets this person see
  if not exists (
    select 1 from public.customers c
    where c.id = v_contract.customer_id
      and (
        public.has_permission('crm_customers', 'view_all')
        or c.assigned_to = auth.uid()
        or c.created_by = auth.uid()
        or public.leads_my_team(c.assigned_to)
        or public.leads_my_team(c.created_by)
      )
  ) then
    raise exception 'contract not found';
  end if;
  if p_patch ? 'code' and nullif(btrim(coalesce(p_patch ->> 'code', '')), '') is null then
    raise exception 'contract_code_required';
  end if;
  if p_patch ? 'deal_id' and nullif(p_patch ->> 'deal_id', '') is not null
     and not exists (select 1 from public.deals d where d.id = (p_patch ->> 'deal_id')::uuid and d.customer_id = v_contract.customer_id) then
    raise exception 'deal does not belong to this customer';
  end if;
  if p_patch ? 'sales_person_id' and nullif(p_patch ->> 'sales_person_id', '') is not null
     and not exists (select 1 from public.profiles p where p.id = (p_patch ->> 'sales_person_id')::uuid and p.is_active) then
    raise exception 'sales person not found';
  end if;

  update public.contracts set
    code      = case when p_patch ? 'code' then btrim(p_patch ->> 'code') else code end,
    signed_on = case when p_patch ? 'signed_on' then nullif(p_patch ->> 'signed_on', '')::date else signed_on end,
    value     = case when p_patch ? 'value' then nullif(p_patch ->> 'value', '')::numeric else value end,
    notes     = case when p_patch ? 'notes' then nullif(btrim(coalesce(p_patch ->> 'notes', '')), '') else notes end,
    deal_id   = case when p_patch ? 'deal_id' then nullif(p_patch ->> 'deal_id', '')::uuid else deal_id end,
    file_name = case when p_patch ? 'file_name' then nullif(p_patch ->> 'file_name', '') else file_name end,
    file_path = case when p_patch ? 'file_path' then nullif(p_patch ->> 'file_path', '') else file_path end,
    sales_person_id = case when p_patch ? 'sales_person_id' then nullif(p_patch ->> 'sales_person_id', '')::uuid else sales_person_id end
  where id = p_contract_id;
  -- the contract's sales person is the seller of its products (one person, not two)
  if p_patch ? 'sales_person_id' then
    update public.customer_products set sales_person_id = nullif(p_patch ->> 'sales_person_id', '')::uuid where contract_id = p_contract_id;
  end if;
end;
$$;
revoke all on function public.crm_update_contract(uuid, jsonb) from public, anon;
grant execute on function public.crm_update_contract(uuid, jsonb) to authenticated;
