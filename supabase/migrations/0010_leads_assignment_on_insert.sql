-- 0006 only enforced the 'assign' permission on UPDATE. A user without it
-- could still create a lead pre-assigned to someone else, since INSERT was
-- never checked. Extend the same function to also guard INSERT: you may
-- only assign a new lead to yourself (or leave it unassigned) unless you
-- hold 'assign'.
create or replace function public.enforce_lead_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.assigned_to is not null
       and new.assigned_to is distinct from auth.uid()
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

drop trigger if exists leads_enforce_assignment on public.leads;

create trigger leads_enforce_assignment
  before insert or update on public.leads
  for each row execute function public.enforce_lead_assignment();
