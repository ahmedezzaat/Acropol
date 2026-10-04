-- In-app notifications.
--   * a deal or lead is assigned to someone -> they are notified
--   * an activity is scheduled on a deal assigned to someone else -> the
--     assignee is notified
--   * an open scheduled activity that is past due -> the assignee is reminded
--     every 30 minutes, 4 times in total, then never again
--
-- Rows hold a machine-readable type + params (not text), so the app renders
-- them in the viewer's language. Nobody inserts from the browser: rows are
-- written only by the security-definer functions below.
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  type text not null check (type in ('deal_assigned', 'lead_assigned', 'activity_scheduled', 'activity_reminder')),
  params jsonb not null default '{}'::jsonb,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index notifications_user_recent on public.notifications (user_id, created_at desc);
create index notifications_user_unread on public.notifications (user_id) where not is_read;

alter table public.notifications enable row level security;

create policy notifications_select_own on public.notifications
  for select using (user_id = auth.uid());
create policy notifications_update_own on public.notifications
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy notifications_delete_own on public.notifications
  for delete using (user_id = auth.uid());

-- Live delivery: the app subscribes to INSERTs for the signed-in user
-- (Realtime applies the select policy above, so users only receive their own).
alter publication supabase_realtime add table public.notifications;

create or replace function public.notify_user(p_user uuid, p_type text, p_params jsonb)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.notifications (user_id, type, params)
  select p_user, p_type, p_params
  where p_user is not null;
$$;
revoke all on function public.notify_user(uuid, text, jsonb) from public, anon, authenticated;

-- Deal assigned ------------------------------------------------------------
create or replace function public.notify_deal_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.assigned_to is null
     or new.assigned_to is not distinct from auth.uid()
     or (tg_op = 'UPDATE' and new.assigned_to is not distinct from old.assigned_to) then
    return new;
  end if;

  perform public.notify_user(new.assigned_to, 'deal_assigned', jsonb_build_object(
    'deal_id', new.id,
    'name', coalesce(
      (select l.name from public.leads l where l.id = new.lead_id),
      (select c.name from public.customers c where c.id = new.customer_id),
      new.title
    ),
    'assigned_by', auth.uid()
  ));
  return new;
end;
$$;

create trigger deals_notify_assignment
  after insert or update of assigned_to on public.deals
  for each row execute function public.notify_deal_assignment();

-- Lead assigned ------------------------------------------------------------
-- A deal's assignment cascades onto its lead; that would notify the same
-- person twice for one action, so the cascade raises a suppress flag.
create or replace function public.notify_lead_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.assigned_to is null
     or new.assigned_to is not distinct from auth.uid()
     or (tg_op = 'UPDATE' and new.assigned_to is not distinct from old.assigned_to)
     or current_setting('acropol.suppress_lead_notify', true) = 'true' then
    return new;
  end if;

  perform public.notify_user(new.assigned_to, 'lead_assigned', jsonb_build_object(
    'lead_id', new.id,
    'name', new.name,
    'assigned_by', auth.uid()
  ));
  return new;
end;
$$;

create trigger leads_notify_assignment
  after insert or update of assigned_to on public.leads
  for each row execute function public.notify_lead_assignment();

create or replace function public.cascade_deal_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and new.assigned_to is not distinct from old.assigned_to then
    return new;
  end if;

  perform set_config('acropol.cascading_assignment', 'true', true);
  perform set_config('acropol.suppress_lead_notify', 'true', true);

  if new.lead_id is not null then
    update public.leads set assigned_to = new.assigned_to where id = new.lead_id;
  end if;

  if new.customer_id is not null then
    update public.customers set assigned_to = new.assigned_to where id = new.customer_id;
  end if;

  perform set_config('acropol.cascading_assignment', 'false', true);
  perform set_config('acropol.suppress_lead_notify', 'false', true);
  return new;
end;
$$;

-- Activity scheduled -------------------------------------------------------
-- An activity belongs to its deal's assignee. Scheduling one on someone
-- else's deal tells that person; scheduling on your own deal doesn't.
alter table public.deal_activities
  add column reminder_count int not null default 0,
  add column last_reminded_at timestamptz;

create or replace function public.notify_activity_scheduled()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deal record;
begin
  if new.scheduled_at is null then
    return new;
  end if;

  select d.id, d.assigned_to, d.title, d.lead_id, d.customer_id into v_deal
  from public.deals d where d.id = new.deal_id;

  if v_deal.assigned_to is null or v_deal.assigned_to is not distinct from new.created_by then
    return new;
  end if;

  perform public.notify_user(v_deal.assigned_to, 'activity_scheduled', jsonb_build_object(
    'deal_id', v_deal.id,
    'activity_id', new.id,
    'name', coalesce(
      (select l.name from public.leads l where l.id = v_deal.lead_id),
      (select c.name from public.customers c where c.id = v_deal.customer_id),
      v_deal.title
    ),
    'activity_type', coalesce((select t.name from public.activity_types t where t.key = new.type), new.type),
    'scheduled_at', new.scheduled_at,
    'assigned_by', new.created_by
  ));
  return new;
end;
$$;

create trigger deal_activities_notify_scheduled
  after insert on public.deal_activities
  for each row execute function public.notify_activity_scheduled();

-- Rescheduling an activity starts its reminders over.
create or replace function public.reset_activity_reminders()
returns trigger
language plpgsql
as $$
begin
  if new.scheduled_at is distinct from old.scheduled_at then
    new.reminder_count := 0;
    new.last_reminded_at := null;
  end if;
  return new;
end;
$$;

create trigger deal_activities_reset_reminders
  before update of scheduled_at on public.deal_activities
  for each row execute function public.reset_activity_reminders();

-- Reminders ----------------------------------------------------------------
-- An activity that is due (scheduled_at passed) and still open (not
-- completed) reminds its deal's assignee right away, then every 30 minutes,
-- 4 reminders in total. Completing the activity stops them.
create or replace function public.send_activity_reminders()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_sent int := 0;
begin
  for r in
    select a.id, a.type, a.scheduled_at, a.reminder_count,
           d.id as deal_id, d.assigned_to, d.title, d.lead_id, d.customer_id
    from public.deal_activities a
    join public.deals d on d.id = a.deal_id
    where a.scheduled_at is not null
      and a.completed_at is null
      and a.scheduled_at <= now()
      and a.reminder_count < 4
      and d.assigned_to is not null
      and (a.last_reminded_at is null or a.last_reminded_at <= now() - interval '30 minutes')
    for update of a skip locked
  loop
    perform public.notify_user(r.assigned_to, 'activity_reminder', jsonb_build_object(
      'deal_id', r.deal_id,
      'activity_id', r.id,
      'name', coalesce(
        (select l.name from public.leads l where l.id = r.lead_id),
        (select c.name from public.customers c where c.id = r.customer_id),
        r.title
      ),
      'activity_type', coalesce((select t.name from public.activity_types t where t.key = r.type), r.type),
      'scheduled_at', r.scheduled_at,
      'attempt', r.reminder_count + 1,
      'max', 4
    ));

    update public.deal_activities
    set reminder_count = reminder_count + 1, last_reminded_at = now()
    where id = r.id;

    v_sent := v_sent + 1;
  end loop;

  return v_sent;
end;
$$;
revoke all on function public.send_activity_reminders() from public, anon, authenticated;

-- Activities that were already overdue when this shipped would otherwise all
-- fire 4 reminders at once; treat them as already reminded.
update public.deal_activities
set reminder_count = 4, last_reminded_at = now()
where scheduled_at is not null and completed_at is null and scheduled_at <= now();

select cron.unschedule(jobid) from cron.job where jobname = 'acropol-activity-reminders';
select cron.schedule('acropol-activity-reminders', '* * * * *', $$select public.send_activity_reminders()$$);
