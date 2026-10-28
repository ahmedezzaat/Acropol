-- What a card on a technical office board shows about its deal: the agent the deal is
-- assigned to, and the lead's (or, once won, the customer's) name and phone. The people
-- who work a board may not be allowed to open deals, leads or customers themselves, so
-- this hands out only those few fields, for items on boards the caller can see.
create or replace function public.work_item_contacts(p_pipeline_id uuid)
returns table (work_item_id uuid, deal_agent_id uuid, contact_name text, contact_phone text)
language sql
stable
security definer
set search_path = public
as $$
  select w.id, d.assigned_to,
         coalesce(l.name, c.name),
         coalesce(l.phone, c.phone)
  from public.work_items w
  join public.deals d on d.id = w.deal_id
  left join public.leads l on l.id = d.lead_id
  left join public.customers c on c.id = d.customer_id
  where w.work_pipeline_id = p_pipeline_id
    and public.can_see_work_item(w.id);
$$;
grant execute on function public.work_item_contacts(uuid) to authenticated;
