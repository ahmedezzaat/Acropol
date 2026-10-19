-- Rescheduled maintenance report. A reschedule is a 'rescheduled' log entry: when
-- it was done (happened_at), the new appointment time (scheduled_for), the reason
-- (note) and who did it (created_by). The old appointment time is now kept on the
-- entry too, so it can be reported.
alter table public.product_maintenance_log
  add column previous_scheduled_for timestamptz;

-- Earlier reschedules: the old time is the product's previous appointment entry.
update public.product_maintenance_log l
set previous_scheduled_for = s.prev
from (
  select id, lag(scheduled_for) over (partition by product_id order by happened_at, id) as prev
  from public.product_maintenance_log
  where kind in ('scheduled', 'rescheduled')
) s
where s.id = l.id and l.kind = 'rescheduled' and s.prev is not null;

-- One row per reschedule: products moved together (same customer, agent, minute and
-- new time) are one row.
create or replace function public.report_maintenance_rescheduled(
  p_from date,
  p_to date,
  p_agent uuid default null
)
returns table (
  done_at timestamptz,
  old_at timestamptz,
  new_at timestamptz,
  customer_id uuid,
  customer_name text,
  reason text,
  agent_id uuid,
  agent_name text,
  products int
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.has_permission('reports', 'maintenance_rescheduled') then
    raise exception 'insufficient permission to view this report';
  end if;

  return query
  select
    min(l.happened_at) as done_at,
    min(l.previous_scheduled_for) as old_at,
    l.scheduled_for as new_at,
    c.id as customer_id,
    case
      when coalesce(c.customer_type, case when nullif(trim(c.company), '') is not null then 'company' else 'individual' end) = 'company'
           and nullif(trim(c.company), '') is not null then trim(c.company)
      else c.name
    end as customer_name,
    string_agg(distinct nullif(trim(l.note), ''), ' / ') as reason,
    l.created_by as agent_id,
    coalesce(nullif(ap.full_name, ''), ap.email) as agent_name,
    count(*)::int as products
  from public.product_maintenance_log l
  join public.customer_products p on p.id = l.product_id
  join public.customers c on c.id = p.customer_id
  left join public.profiles ap on ap.id = l.created_by
  where l.kind = 'rescheduled'
    and (l.happened_at at time zone 'Africa/Cairo')::date between p_from and p_to
    and (p_agent is null or l.created_by = p_agent)
  group by c.id, c.name, c.company, c.customer_type, l.created_by, ap.full_name, ap.email, date_trunc('minute', l.happened_at), l.scheduled_for
  order by min(l.happened_at) desc;
end;
$$;

grant execute on function public.report_maintenance_rescheduled(date, date, uuid) to authenticated;
