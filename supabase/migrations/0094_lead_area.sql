-- The area (المنطقة) of a lead, chosen from the same list as customers' areas
-- (Settings -> Areas). It is copied to the customer when the lead becomes one,
-- and shown on the lead, its deals and the customer.
alter table public.leads
  add column area_id uuid references public.service_areas (id) on delete set null;

-- Sales (CRM) users pick the area too, so they can read the list of areas.
drop policy service_areas_select on public.service_areas;
create policy service_areas_select on public.service_areas
  for select using (
    public.has_any_module_permission('cs_customers')
    or public.has_any_module_permission('cs_maintenance')
    or public.has_any_module_permission('crm_leads')
    or public.has_any_module_permission('crm_deals')
    or public.has_any_module_permission('crm_customers')
  );

create or replace function public.crm_convert_lead(p_lead_id uuid)
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

  insert into public.customers (name, company, phone, extra_phones, email, area_id, converted_from_lead_id, created_by)
  values (
    v_lead.name,
    case when v_lead.lead_type = 'company' then v_lead.company_name else null end,
    v_lead.phone,
    case when nullif(btrim(coalesce(v_lead.phone2, '')), '') is not null then array[v_lead.phone2] else '{}'::text[] end,
    v_lead.email,
    v_lead.area_id,
    p_lead_id,
    auth.uid()
  )
  returning id into v_customer_id;

  update public.leads
  set status = 'converted', customer_id = v_customer_id
  where id = p_lead_id;

  return v_customer_id;
end;
$$;
