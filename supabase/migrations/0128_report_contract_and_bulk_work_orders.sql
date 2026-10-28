-- Contract number (رقم العقد) on the Done maintenance report and on the printed work order,
-- and a bulk version of the work order so many can be printed (or saved as PDF) at once.

-- The report lists each visit's contract number(s).
drop function public.report_maintenance_done(date, date, uuid, uuid);
create function public.report_maintenance_done(
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
  products int,
  contract_codes text
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
    count(*)::int as products,
    string_agg(distinct nullif(trim(p.contract_code), ''), ', ') as contract_codes
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
revoke all on function public.report_maintenance_done(date, date, uuid, uuid) from public, anon;
grant execute on function public.report_maintenance_done(date, date, uuid, uuid) to authenticated;

-- The work order now carries each product's contract number.
create or replace function public.report_work_order(p_visit_key uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_customer_id uuid;
  v_result jsonb;
begin
  if not public.has_permission('reports', 'maintenance_done') then
    raise exception 'insufficient permission to view this report';
  end if;

  select p.customer_id into v_customer_id
  from public.product_maintenance_log l
  join public.customer_products p on p.id = l.product_id
  where coalesce(l.visit_id, l.id) = p_visit_key and l.kind = 'done' and l.marked_done
  limit 1;
  if v_customer_id is null then
    raise exception 'work order not found';
  end if;

  select jsonb_build_object(
    'customer', (
      select jsonb_build_object(
        'name', c.name,
        'company', c.company,
        'phone', c.phone,
        'extra_phones', c.extra_phones,
        'extra_phone_names', c.extra_phone_names,
        'email', c.email,
        'address', c.address,
        'area', a.name
      )
      from public.customers c left join public.service_areas a on a.id = c.area_id
      where c.id = v_customer_id
    ),
    'visit', (
      select jsonb_build_object('done_on', max(l.done_on), 'note', (select v.note from public.maintenance_visits v where v.id = p_visit_key))
      from public.product_maintenance_log l
      where coalesce(l.visit_id, l.id) = p_visit_key and l.kind = 'done' and l.marked_done
    ),
    'technician', (
      select coalesce(nullif(tp.full_name, ''), tp.email)
      from public.product_maintenance_log l join public.profiles tp on tp.id = l.technician_id
      where coalesce(l.visit_id, l.id) = p_visit_key and l.kind = 'done' and l.marked_done
      limit 1
    ),
    'signature_path', (
      select l.signature_path from public.product_maintenance_log l
      where coalesce(l.visit_id, l.id) = p_visit_key and l.kind = 'done' and l.marked_done and l.signature_path is not null
      limit 1
    ),
    'entries', coalesce((
      select jsonb_agg(e order by e.product_name)
      from (
        select
          p.name as product_name,
          p.contract_code,
          cat.name as category_name,
          l.cost,
          l.visit_cost,
          l.note,
          (select jsonb_agg(jsonb_build_object('name', u.name, 'quantity', u.quantity, 'unit_price', u.unit_price) order by u.name)
             from public.maintenance_used_parts u where u.log_id = l.id) as parts,
          (select s.scheduled_for from public.product_maintenance_log s
             where s.product_id = l.product_id and s.kind = 'scheduled' and s.happened_at >= l.happened_at
             order by s.happened_at limit 1) as next_at,
          (select s.note from public.product_maintenance_log s
             where s.product_id = l.product_id and s.kind = 'scheduled' and s.happened_at >= l.happened_at
             order by s.happened_at limit 1) as next_note
        from public.product_maintenance_log l
        join public.customer_products p on p.id = l.product_id
        left join public.product_categories cat on cat.id = p.category_id
        where coalesce(l.visit_id, l.id) = p_visit_key and l.kind = 'done' and l.marked_done
      ) e
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

-- Many work orders at once, in the order asked for (the permission is checked by each).
create or replace function public.report_work_orders(p_visit_keys uuid[])
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(public.report_work_order(k.key) order by k.ord), '[]'::jsonb)
  from unnest(p_visit_keys) with ordinality as k(key, ord);
$$;
revoke all on function public.report_work_orders(uuid[]) from public, anon;
grant execute on function public.report_work_orders(uuid[]) to authenticated;
