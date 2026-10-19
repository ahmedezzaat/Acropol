-- The Done maintenance report lists only visits finished with the "Done" button
-- (تمت الصيانة), not the history that was imported or entered as records. That
-- button now flags its log entry.
alter table public.product_maintenance_log
  add column marked_done boolean not null default false;

-- The entries made with the button so far (the only done entries with a real
-- timestamp rather than an imported date).
update public.product_maintenance_log
set marked_done = true
where id in (
  'b90d0a49-cfb6-4ce2-bc38-de5a735dc2c3',
  '07d548dd-a3f9-4259-a74d-75762955cf55',
  'b8a20d1f-ce33-4622-b230-7c39090a5493'
);

create or replace function public.report_maintenance_done(
  p_from date,
  p_to date,
  p_technician uuid default null,
  p_area uuid default null
)
returns table (
  visit_key uuid,
  done_on date,
  technician_id uuid,
  technician_name text,
  customer_id uuid,
  customer_name text,
  area_id uuid,
  area_name text,
  cost numeric,
  products int
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.has_permission('reports', 'maintenance_done') then
    raise exception 'insufficient permission to view this report';
  end if;

  return query
  select
    coalesce(l.visit_id, l.id) as visit_key,
    l.done_on,
    (array_agg(l.technician_id) filter (where l.technician_id is not null))[1] as technician_id,
    (array_agg(coalesce(nullif(tp.full_name, ''), tp.email)) filter (where l.technician_id is not null))[1] as technician_name,
    c.id as customer_id,
    case
      when coalesce(c.customer_type, case when nullif(trim(c.company), '') is not null then 'company' else 'individual' end) = 'company'
           and nullif(trim(c.company), '') is not null then trim(c.company)
      else c.name
    end as customer_name,
    c.area_id,
    a.name as area_name,
    coalesce(sum(l.cost), 0) as cost,
    count(*)::int as products
  from public.product_maintenance_log l
  join public.customer_products p on p.id = l.product_id
  join public.customers c on c.id = p.customer_id
  left join public.service_areas a on a.id = c.area_id
  left join public.profiles tp on tp.id = l.technician_id
  where l.kind = 'done'
    and l.marked_done
    and l.done_on between p_from and p_to
    and (p_area is null or c.area_id = p_area)
  group by coalesce(l.visit_id, l.id), l.done_on, c.id, c.name, c.company, c.customer_type, c.area_id, a.name
  having p_technician is null or bool_or(l.technician_id = p_technician)
  order by l.done_on desc, customer_name;
end;
$$;

grant execute on function public.report_maintenance_done(date, date, uuid, uuid) to authenticated;
