-- The Rescheduled maintenance report lists only appointments moved with the
-- "Reschedule" button (إعادة جدولة), not time changes made while confirming a visit
-- or entered as records. That button now flags its log entry.
alter table public.product_maintenance_log
  add column marked_rescheduled boolean not null default false;

-- The entries made with the button so far: reschedules that are not part of a
-- recorded visit and not made together with a confirmation.
update public.product_maintenance_log
set marked_rescheduled = true
where id::text like any (array['e906785d%', '0f210062%', '784dc8c4%', '46e7f57d%', '85a087e4%', '880d837a%'])
  and kind = 'rescheduled';

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
    string_agg(distinct nullif(trim(l.reschedule_reason), ''), ' / ') as reason,
    l.created_by as agent_id,
    coalesce(nullif(ap.full_name, ''), ap.email) as agent_name,
    count(*)::int as products
  from public.product_maintenance_log l
  join public.customer_products p on p.id = l.product_id
  join public.customers c on c.id = p.customer_id
  left join public.profiles ap on ap.id = l.created_by
  where l.kind = 'rescheduled'
    and l.marked_rescheduled
    and (l.happened_at at time zone 'Africa/Cairo')::date between p_from and p_to
    and (p_agent is null or l.created_by = p_agent)
  group by c.id, c.name, c.company, c.customer_type, l.created_by, ap.full_name, ap.email, date_trunc('minute', l.happened_at), l.scheduled_for
  order by min(l.happened_at) desc;
end;
$$;

grant execute on function public.report_maintenance_rescheduled(date, date, uuid) to authenticated;
