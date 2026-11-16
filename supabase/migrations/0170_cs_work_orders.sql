-- Work orders (أوامر الشغل) made straight from the confirmed visits page.
--   * maintenance  : a done maintenance visit of a customer's products (the existing visit / log tables; no change here)
--   * installation : a customer, the customer's signature and notes
--   * operation    : the same
--   * inspection   : the same, for a customer OR a lead
-- Installation, operation and inspection have no next visit and no spare parts, so they live in one small table.
-- An order is either recorded as done straight away, or created pending (with a date and instructions), given to a
-- technician now or later: the technician then marks it done with his notes and the customer's signature.
-- The name / phone / address are copied onto the order, so a lead's details can be shown and printed by people
-- who cannot open the CRM, and so the order stays readable if the customer is merged or removed.
create sequence public.cs_work_order_no_seq start 1;

create table public.cs_work_orders (
  id uuid primary key default gen_random_uuid(),
  number text not null unique default ('WO-' || lpad(nextval('public.cs_work_order_no_seq')::text, 5, '0')),
  kind text not null check (kind in ('installation', 'operation', 'inspection')),
  customer_id uuid references public.customers (id) on delete set null,
  lead_id uuid references public.leads (id) on delete set null,
  subject_name text not null,
  subject_phone text,
  subject_address text,
  -- the planned date while pending, the date it was done once done
  work_date date not null default current_date,
  technician_id uuid references public.profiles (id) on delete set null,
  status text not null default 'done' check (status in ('pending', 'done')),
  -- the office's instructions / the order's notes
  note text,
  -- what the technician wrote when it was done
  done_note text,
  done_on date,
  done_by uuid references public.profiles (id) on delete set null,
  signature_path text,
  created_by uuid references public.profiles (id) default auth.uid(),
  created_at timestamptz not null default now(),
  -- a customer or a lead, never both; only an inspection can be for a lead
  constraint cs_work_orders_one_subject check (customer_id is null or lead_id is null),
  constraint cs_work_orders_lead_inspection check (lead_id is null or kind = 'inspection')
);
create index cs_work_orders_pending on public.cs_work_orders (technician_id) where status = 'pending';

-- Recorded as done: the date it was done is its date
create or replace function public.cs_work_order_before_insert()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'done' then
    new.done_on := coalesce(new.done_on, new.work_date);
    new.done_by := coalesce(new.done_by, auth.uid());
  end if;
  return new;
end;
$$;
create trigger cs_work_order_before_insert
  before insert on public.cs_work_orders
  for each row execute function public.cs_work_order_before_insert();

-- A pending order tells its technician (the bell) when it is made for them or later given to them, unless they did it themselves
create or replace function public.cs_work_order_notify()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'pending' and new.technician_id is not null and new.technician_id is distinct from auth.uid()
     and (tg_op = 'INSERT' or new.technician_id is distinct from old.technician_id) then
    perform public.notify_user(new.technician_id, 'work_order_assigned', jsonb_build_object(
      'work_order_id', new.id, 'kind', new.kind, 'subject_name', new.subject_name, 'work_date', new.work_date));
  end if;
  return null;
end;
$$;
create trigger cs_work_order_notify
  after insert or update of technician_id on public.cs_work_orders
  for each row execute function public.cs_work_order_notify();

alter table public.notifications drop constraint notifications_type_check;
alter table public.notifications add constraint notifications_type_check check (type = any (array[
  'deal_assigned', 'lead_assigned', 'activity_scheduled', 'activity_reminder', 'deal_unassigned', 'deals_unassigned',
  'visit_pending', 'visit_update', 'work_stage_changed', 'work_request_created', 'work_assigned', 'work_request_withdrawn',
  'work_request_done', 'task_assigned', 'task_done', 'leave_request', 'leave_decided', 'chat_handover', 'work_order_assigned'
]));
create index cs_work_orders_customer on public.cs_work_orders (customer_id);
create index cs_work_orders_lead on public.cs_work_orders (lead_id);
create index cs_work_orders_date on public.cs_work_orders (work_date desc);

alter table public.cs_work_orders enable row level security;

-- Seen by the people who work with visits: all of them, or only the ones made by / given to them
create policy cs_work_orders_select on public.cs_work_orders for select to authenticated
  using (
    public.has_permission('cs_maintenance', 'view_confirmed_all')
    or public.has_permission('cs_maintenance', 'complete')
    or technician_id = auth.uid()
    or created_by = auth.uid()
  );
create policy cs_work_orders_insert on public.cs_work_orders for insert to authenticated
  with check (public.has_permission('cs_maintenance', 'complete'));
create policy cs_work_orders_delete on public.cs_work_orders for delete to authenticated
  using (public.has_permission('cs_maintenance', 'cancel'));

-- The technician (or the office) marks a pending order done: his notes, the date and the customer's signature.
-- Done through a function so nothing else of the order can be changed from the technician's phone.
create or replace function public.cs_complete_work_order(p_id uuid, p_done_on date, p_note text, p_signature_path text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tech uuid;
  v_status text;
begin
  select technician_id, status into v_tech, v_status from public.cs_work_orders where id = p_id for update;
  if not found then
    raise exception 'work order not found';
  end if;
  if v_tech is distinct from auth.uid() and not public.has_permission('cs_maintenance', 'complete') then
    raise exception 'insufficient permission';
  end if;
  if v_status <> 'pending' then
    raise exception 'work order is already done';
  end if;
  update public.cs_work_orders
  set status = 'done', done_on = coalesce(p_done_on, current_date), done_note = nullif(btrim(p_note), ''),
      signature_path = p_signature_path, done_by = auth.uid()
  where id = p_id;
end;
$$;
revoke all on function public.cs_complete_work_order(uuid, date, text, text) from public, anon;
grant execute on function public.cs_complete_work_order(uuid, date, text, text) to authenticated;

-- The office gives a pending order to a technician (or changes the technician). Nothing else of the order changes.
create or replace function public.cs_assign_work_order(p_id uuid, p_technician uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.has_permission('cs_maintenance', 'schedule') or public.has_permission('cs_maintenance', 'complete')) then
    raise exception 'insufficient permission';
  end if;
  update public.cs_work_orders set technician_id = p_technician where id = p_id and status = 'pending';
  if not found then
    raise exception 'work order not found or already done';
  end if;
end;
$$;
revoke all on function public.cs_assign_work_order(uuid, uuid) from public, anon;
grant execute on function public.cs_assign_work_order(uuid, uuid) to authenticated;

-- Finding a lead for an inspection: people in customer service cannot read the CRM's leads directly
create or replace function public.cs_search_leads(p_q text default '')
returns table (id uuid, name text, phone text, company_name text)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.has_permission('cs_maintenance', 'complete') then
    raise exception 'insufficient permission';
  end if;
  return query
    select l.id, l.name, l.phone, l.company_name
    from public.leads l
    where l.customer_id is null
      and (coalesce(btrim(p_q), '') = ''
           or l.name ilike '%' || btrim(p_q) || '%'
           or l.phone ilike '%' || btrim(p_q) || '%'
           or l.company_name ilike '%' || btrim(p_q) || '%')
    order by l.created_at desc
    limit 20;
end;
$$;
revoke all on function public.cs_search_leads(text) from public, anon;
grant execute on function public.cs_search_leads(text) to authenticated;

-- Merging customers also moves their work orders
do $$
declare
  d text := pg_get_functiondef('public.cs_merge_customers(uuid, uuid[])'::regprocedure);
  marker constant text := '    update public.quotes set customer_id = p_keep where customer_id = v_id;';
begin
  if position(marker in d) = 0 then
    raise exception 'merge function changed: marker not found';
  end if;
  execute replace(d, marker, marker || E'\n    update public.cs_work_orders set customer_id = p_keep where customer_id = v_id;');
end $$;
