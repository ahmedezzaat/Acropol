-- Contact statuses: "new" and "unqualified" are chosen by a person; "has an open deal" and "has a contract" are
-- worked out by the system (lead_state), so they are always true.
--  * the old statuses are folded in: contacted / qualified -> new, lost -> unqualified (converted stays: it
--    means a customer was made from the contact, shown as "has a contract")
update public.leads set status = 'new' where status in ('contacted', 'qualified');
update public.leads set status = 'unqualified' where status = 'lost';

-- deleting a customer sends its converted contact back to "new"
create or replace function public.customer_detach_before_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.leads
  set customer_id = null,
      status = case when status = 'converted' then 'new' else status end
  where customer_id = old.id;

  update public.deals set customer_id = null where customer_id = old.id;
  update public.quotes set customer_id = null where customer_id = old.id;

  return old;
end;
$$;

-- 'contract' when the contact has a contract (or was converted to a customer), else 'open_deal' when it has a deal
-- that is not closed yet, else null. Security definer so it is true for everyone who can see the contact.
create or replace function public.lead_state(p_lead uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when l.status = 'converted'
      or exists (
        select 1 from public.contracts c
        where (l.customer_id is not null and c.customer_id = l.customer_id)
           or c.deal_id in (select d.id from public.deals d where d.lead_id = l.id)
      ) then 'contract'
    when exists (
      select 1 from public.deals d
      join public.pipeline_stages s on s.id = d.stage_id
      where d.lead_id = l.id and not s.is_closed
    ) then 'open_deal'
  end
  from public.leads l where l.id = p_lead;
$$;
revoke all on function public.lead_state(uuid) from public, anon;
grant execute on function public.lead_state(uuid) to authenticated;

-- the state of every contact the caller can see (the leads policy decides which)
create or replace function public.lead_states()
returns table (lead_id uuid, state text)
language sql
stable
security invoker
set search_path = public
as $$
  select l.id, public.lead_state(l.id) from public.leads l;
$$;
grant execute on function public.lead_states() to authenticated;
