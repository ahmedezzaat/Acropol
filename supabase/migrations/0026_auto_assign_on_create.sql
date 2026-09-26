-- A user without the assign permission has no way to pick who a new
-- lead/deal/customer belongs to — previously that meant it was created
-- unassigned. Now it defaults to the creator themselves: if assigned_to is
-- left blank AND the caller lacks assign, it's auto-set to auth.uid()
-- instead. A user WITH assign can still deliberately leave it unassigned
-- (e.g. a manager building a pool to triage later) — this only changes the
-- behavior for the case that previously had no real choice in the matter.
create or replace function public.enforce_lead_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_setting('acropol.cascading_assignment', true) = 'true' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.assigned_to is null then
      if not public.has_permission('crm_leads', 'assign') then
        new.assigned_to := auth.uid();
      end if;
    elsif new.assigned_to is distinct from auth.uid()
       and not public.has_permission('crm_leads', 'assign') then
      raise exception 'insufficient permission to assign this lead';
    end if;
    return new;
  end if;

  if new.assigned_to is distinct from old.assigned_to
     and not public.has_permission('crm_leads', 'assign') then
    raise exception 'insufficient permission to reassign lead';
  end if;
  return new;
end;
$$;

create or replace function public.enforce_deal_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.assigned_to is null then
      if not public.has_permission('crm_deals', 'assign') then
        new.assigned_to := auth.uid();
      end if;
    elsif new.assigned_to is distinct from auth.uid()
       and not public.has_permission('crm_deals', 'assign') then
      raise exception 'insufficient permission to assign this deal';
    end if;
    return new;
  end if;

  if new.assigned_to is distinct from old.assigned_to
     and not public.has_permission('crm_deals', 'assign') then
    raise exception 'insufficient permission to reassign deal';
  end if;
  return new;
end;
$$;

create or replace function public.enforce_customer_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_setting('acropol.cascading_assignment', true) = 'true' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.assigned_to is null then
      if not public.has_permission('crm_customers', 'assign') then
        new.assigned_to := auth.uid();
      end if;
    elsif new.assigned_to is distinct from auth.uid()
       and not public.has_permission('crm_customers', 'assign') then
      raise exception 'insufficient permission to assign this customer';
    end if;
    return new;
  end if;

  if new.assigned_to is distinct from old.assigned_to
     and not public.has_permission('crm_customers', 'assign') then
    raise exception 'insufficient permission to reassign customer';
  end if;
  return new;
end;
$$;
