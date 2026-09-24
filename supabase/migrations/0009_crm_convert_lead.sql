-- Atomically converts a lead into a customer and marks the lead as
-- converted. security definer so the customer insert + lead update happen
-- as one permission-checked unit rather than two separate client calls that
-- could race or partially fail.
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

  insert into public.customers (name, company, phone, email, converted_from_lead_id, created_by)
  values (v_lead.name, null, v_lead.phone, v_lead.email, p_lead_id, auth.uid())
  returning id into v_customer_id;

  update public.leads
  set status = 'converted', customer_id = v_customer_id
  where id = p_lead_id;

  return v_customer_id;
end;
$$;
