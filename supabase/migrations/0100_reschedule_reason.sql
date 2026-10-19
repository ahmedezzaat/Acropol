-- Rescheduling an appointment now records why: the person doing it writes the
-- reason, and the Rescheduled maintenance report shows it (instead of the
-- appointment's own note).
alter table public.product_maintenance_log
  add column reschedule_reason text;

drop function if exists public.report_maintenance_rescheduled(date, date, uuid);
create function public.report_maintenance_rescheduled(
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
    string_agg(distinct nullif(trim(l.reschedule_reason), ''), ' / ') as reason,
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
