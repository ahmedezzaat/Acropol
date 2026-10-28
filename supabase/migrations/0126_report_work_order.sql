-- The printable work order (أمر الشغل) of one maintenance visit, from the Done
-- maintenance report: the customer's contact details, what was done on each product
-- with its parts and cost, the notes, the next maintenance and the customer's signature.
-- Only this visit's own data (not the customer's past maintenance).
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
revoke all on function public.report_work_order(uuid) from public, anon;
grant execute on function public.report_work_order(uuid) to authenticated;

-- People who can open the report can open the signature image printed on the order.
create policy visit_signatures_select_report on storage.objects
  for select
  using (bucket_id = 'visit-signatures' and public.has_permission('reports', 'maintenance_done'));
