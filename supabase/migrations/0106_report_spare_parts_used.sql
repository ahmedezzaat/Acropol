-- Report: the spare parts used in maintenance visits finished with the "Done"
-- button — one row per part used, with the visit's date, customer, area and
-- technician.
create or replace function public.report_spare_parts_used(
  p_from date,
  p_to date,
  p_technician uuid default null,
  p_area uuid default null
)
returns table (
  used_id uuid,
  done_on date,
  customer_id uuid,
  customer_name text,
  area_name text,
  technician_name text,
  product_name text,
  part_name text,
  quantity int,
  unit_price numeric,
  line_total numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.has_permission('reports', 'spare_parts_used') then
    raise exception 'insufficient permission to view this report';
  end if;

  return query
  select
    u.id as used_id,
    l.done_on,
    c.id as customer_id,
    case
      when coalesce(c.customer_type, case when nullif(trim(c.company), '') is not null then 'company' else 'individual' end) = 'company'
           and nullif(trim(c.company), '') is not null then trim(c.company)
      else c.name
    end as customer_name,
    a.name as area_name,
    coalesce(nullif(tp.full_name, ''), tp.email) as technician_name,
    p.name as product_name,
    u.name as part_name,
    u.quantity,
    u.unit_price,
    u.unit_price * u.quantity as line_total
  from public.maintenance_used_parts u
  join public.product_maintenance_log l on l.id = u.log_id
  join public.customer_products p on p.id = l.product_id
  join public.customers c on c.id = p.customer_id
  left join public.service_areas a on a.id = c.area_id
  left join public.profiles tp on tp.id = l.technician_id
  where l.kind = 'done'
    and l.marked_done
    and l.done_on between p_from and p_to
    and (p_area is null or c.area_id = p_area)
    and (p_technician is null or l.technician_id = p_technician)
  order by l.done_on desc, customer_name, u.name;
end;
$$;

grant execute on function public.report_spare_parts_used(date, date, uuid, uuid) to authenticated;
