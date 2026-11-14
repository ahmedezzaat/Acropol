-- The sales person (المسؤول عن العقد) of a contract can be set on the contract itself ("تعديل العقد"). When it is empty
-- the contract keeps showing what it showed before: the sales person recorded on its products, else its deal's agent.

alter table public.contracts add column sales_person_id uuid references public.profiles (id) on delete set null;

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
end;
$$;
revoke all on function public.crm_update_contract(uuid, jsonb) from public, anon;
grant execute on function public.crm_update_contract(uuid, jsonb) to authenticated;
