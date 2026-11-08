-- Leave (الإجازات): vacation requests and delay permissions.
--  * A person asks for a vacation from one day to another and picks who approves it.
--  * Vacation types (اعتيادية, مرضية, ...) each have a yearly credit; an approved vacation uses it.
--    A type can require a file (the sick leave does).
--  * Each person has a delay permission: a number of hours, a number of times a month.
--  * Each person has their own attendance and exit times.
-- Everything is a setting (Settings -> Leave): the types and their credits, the delay rule, the
-- weekend, when the year starts, the default hours, and each person's hours and credits.

-- ---- Settings
create table public.leave_types (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  yearly_credit numeric not null default 0 check (yearly_credit >= 0),
  requires_attachment boolean not null default false,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);
-- a first set of credits to adjust in Settings
insert into public.leave_types (name, yearly_credit, requires_attachment, sort_order) values
  ('اعتيادية', 21, false, 0),
  ('مرضية', 15, true, 1);

create table public.leave_policy (
  id integer primary key default 1 check (id = 1),
  delay_max_hours numeric not null default 2 check (delay_max_hours > 0),
  delay_per_month integer not null default 3 check (delay_per_month >= 0),
  -- days that do not count in a vacation (0 = Sunday ... 6 = Saturday): Friday and Saturday
  weekend_days integer[] not null default '{5,6}',
  -- the month the credit year starts in (1 = January)
  year_start_month integer not null default 1 check (year_start_month between 1 and 12),
  default_start time not null default '09:00',
  default_end time not null default '17:00'
);
insert into public.leave_policy (id) values (1);

-- A person's own attendance and exit times (none: the defaults above).
create table public.user_work_schedules (
  profile_id uuid primary key references public.profiles (id) on delete cascade,
  start_time time not null,
  end_time time not null
);

-- A person's own credit for a type (none: the type's yearly credit).
create table public.leave_user_credits (
  profile_id uuid not null references public.profiles (id) on delete cascade,
  leave_type_id uuid not null references public.leave_types (id) on delete cascade,
  credit numeric not null check (credit >= 0),
  primary key (profile_id, leave_type_id)
);

-- ---- Requests
create table public.leave_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  leave_type_id uuid not null references public.leave_types (id),
  start_date date not null,
  end_date date not null check (end_date >= start_date),
  days numeric not null default 0 check (days >= 0),
  note text,
  approver_id uuid not null references public.profiles (id),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  attachments jsonb not null default '[]'::jsonb,
  decided_by uuid references public.profiles (id) on delete set null,
  decided_at timestamptz,
  decision_note text,
  created_at timestamptz not null default now()
);
create index leave_requests_user on public.leave_requests (user_id, start_date);
create index leave_requests_approver on public.leave_requests (approver_id, status);

create table public.leave_delay_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  delay_date date not null,
  hours numeric not null check (hours > 0),
  reason text,
  approver_id uuid not null references public.profiles (id),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  decided_by uuid references public.profiles (id) on delete set null,
  decided_at timestamptz,
  decision_note text,
  created_at timestamptz not null default now()
);
create index leave_delay_user on public.leave_delay_requests (user_id, delay_date);
create index leave_delay_approver on public.leave_delay_requests (approver_id, status);

-- ---- Helpers
-- Can this person decide leave requests? An active administrator, or a role with "approve".
create or replace function public.leave_is_approver(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = p_user and p.is_active
      and (
        p.is_admin
        or exists (select 1 from public.role_permissions rp where rp.role_id = p.role_id and rp.module = 'leave' and rp.action = 'approve')
      )
  );
$$;

-- The days of a vacation that count (the weekend is left out).
create or replace function public.leave_working_days(p_start date, p_end date)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int
  from generate_series(p_start::timestamp, p_end::timestamp, interval '1 day') d,
       (select weekend_days as w from public.leave_policy where id = 1) pol
  where not (extract(dow from d)::int = any (pol.w));
$$;

-- The first day of the credit year a date falls in.
create or replace function public.leave_period_start(p_date date)
returns date
language sql
stable
security definer
set search_path = public
as $$
  select make_date(
    extract(year from p_date)::int - case when extract(month from p_date) < y.m then 1 else 0 end,
    y.m,
    1
  )
  from (select year_start_month as m from public.leave_policy where id = 1) y;
$$;

create or replace function public.leave_credit(p_user uuid, p_type uuid)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select c.credit from public.leave_user_credits c where c.profile_id = p_user and c.leave_type_id = p_type),
    (select t.yearly_credit from public.leave_types t where t.id = p_type),
    0
  );
$$;
revoke all on function public.leave_is_approver(uuid), public.leave_working_days(date, date), public.leave_period_start(date), public.leave_credit(uuid, uuid) from public, anon;
grant execute on function public.leave_is_approver(uuid), public.leave_working_days(date, date), public.leave_period_start(date), public.leave_credit(uuid, uuid) to authenticated;

-- ---- Rules on a new request (the messages are codes the app turns into text)
create or replace function public.leave_requests_validate()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type public.leave_types;
  v_days integer;
  v_ps date;
  v_used numeric;
begin
  select * into v_type from public.leave_types where id = new.leave_type_id and is_active;
  if v_type.id is null then raise exception 'leave_type_unavailable'; end if;
  if new.approver_id = new.user_id then raise exception 'approver_is_self'; end if;
  if not public.leave_is_approver(new.approver_id) then raise exception 'approver_not_allowed'; end if;
  v_days := public.leave_working_days(new.start_date, new.end_date);
  if v_days <= 0 then raise exception 'no_working_days'; end if;
  new.days := v_days;
  if v_type.requires_attachment and jsonb_array_length(new.attachments) = 0 then raise exception 'attachment_required'; end if;
  if exists (
    select 1 from public.leave_requests r
    where r.user_id = new.user_id and r.status in ('pending', 'approved')
      and r.start_date <= new.end_date and r.end_date >= new.start_date
  ) then raise exception 'overlapping_request'; end if;
  v_ps := public.leave_period_start(new.start_date);
  select coalesce(sum(r.days), 0) into v_used
  from public.leave_requests r
  where r.user_id = new.user_id and r.leave_type_id = new.leave_type_id and r.status in ('pending', 'approved')
    and r.start_date >= v_ps and r.start_date < (v_ps + interval '1 year')::date;
  if v_used + new.days > public.leave_credit(new.user_id, new.leave_type_id) then raise exception 'insufficient_balance'; end if;
  return new;
end;
$$;
create trigger leave_requests_validate before insert on public.leave_requests
  for each row execute function public.leave_requests_validate();

create or replace function public.leave_delay_validate()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_policy public.leave_policy;
begin
  select * into v_policy from public.leave_policy where id = 1;
  if new.hours > v_policy.delay_max_hours then raise exception 'delay_too_long'; end if;
  if new.approver_id = new.user_id then raise exception 'approver_is_self'; end if;
  if not public.leave_is_approver(new.approver_id) then raise exception 'approver_not_allowed'; end if;
  if exists (
    select 1 from public.leave_delay_requests r
    where r.user_id = new.user_id and r.status in ('pending', 'approved') and r.delay_date = new.delay_date
  ) then raise exception 'delay_same_day'; end if;
  if (
    select count(*) from public.leave_delay_requests r
    where r.user_id = new.user_id and r.status in ('pending', 'approved')
      and date_trunc('month', r.delay_date) = date_trunc('month', new.delay_date)
  ) >= v_policy.delay_per_month then raise exception 'delay_quota_reached'; end if;
  return new;
end;
$$;
create trigger leave_delay_validate before insert on public.leave_delay_requests
  for each row execute function public.leave_delay_validate();

-- After a request is made, only its status can change (cancelled by its owner, or decided by
-- the approver through leave_decide).
create or replace function public.leave_requests_immutable()
returns trigger
language plpgsql
as $$
begin
  if (to_jsonb(new) - array['status', 'decided_by', 'decided_at', 'decision_note'])
     is distinct from (to_jsonb(old) - array['status', 'decided_by', 'decided_at', 'decision_note']) then
    raise exception 'request_is_fixed';
  end if;
  return new;
end;
$$;
create trigger leave_requests_immutable before update on public.leave_requests
  for each row execute function public.leave_requests_immutable();
create trigger leave_delay_immutable before update on public.leave_delay_requests
  for each row execute function public.leave_requests_immutable();

-- ---- Deciding
create or replace function public.leave_decide(p_kind text, p_id uuid, p_approve boolean, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_approver uuid;
  v_status text;
  v_is_admin boolean;
  v_new text := case when p_approve then 'approved' else 'rejected' end;
begin
  if p_kind = 'vacation' then
    select approver_id, status into v_approver, v_status from public.leave_requests where id = p_id for update;
  elsif p_kind = 'delay' then
    select approver_id, status into v_approver, v_status from public.leave_delay_requests where id = p_id for update;
  else
    raise exception 'bad_kind';
  end if;
  if v_approver is null then raise exception 'not_found'; end if;
  if v_status <> 'pending' then raise exception 'already_decided'; end if;
  select coalesce(p.is_admin, false) into v_is_admin from public.profiles p where p.id = auth.uid();
  if auth.uid() <> v_approver and not coalesce(v_is_admin, false) then raise exception 'not_your_request'; end if;

  if p_kind = 'vacation' then
    update public.leave_requests
    set status = v_new, decided_by = auth.uid(), decided_at = now(), decision_note = nullif(btrim(coalesce(p_note, '')), '')
    where id = p_id;
  else
    update public.leave_delay_requests
    set status = v_new, decided_by = auth.uid(), decided_at = now(), decision_note = nullif(btrim(coalesce(p_note, '')), '')
    where id = p_id;
  end if;
end;
$$;
revoke all on function public.leave_decide(text, uuid, boolean, text) from public, anon;
grant execute on function public.leave_decide(text, uuid, boolean, text) to authenticated;

-- The people a request can be sent to.
create or replace function public.leave_approvers()
returns table (id uuid, full_name text, email text)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.full_name, p.email
  from public.profiles p
  where p.id <> auth.uid() and public.leave_is_approver(p.id)
  order by coalesce(nullif(p.full_name, ''), p.email);
$$;
revoke all on function public.leave_approvers() from public, anon;
grant execute on function public.leave_approvers() to authenticated;

-- Credit, used and waiting days of each active type: for yourself, or for everyone (view all).
create or replace function public.leave_balances(p_all boolean default false)
returns table (user_id uuid, leave_type_id uuid, credit numeric, used numeric, pending numeric)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ps date := public.leave_period_start(current_date);
  v_pe date := (public.leave_period_start(current_date) + interval '1 year')::date;
begin
  if p_all and not public.has_permission('leave', 'view_all') then
    raise exception 'insufficient_permission';
  end if;
  return query
  select p.id, t.id, public.leave_credit(p.id, t.id),
    coalesce((select sum(r.days) from public.leave_requests r
      where r.user_id = p.id and r.leave_type_id = t.id and r.status = 'approved' and r.start_date >= v_ps and r.start_date < v_pe), 0),
    coalesce((select sum(r.days) from public.leave_requests r
      where r.user_id = p.id and r.leave_type_id = t.id and r.status = 'pending' and r.start_date >= v_ps and r.start_date < v_pe), 0)
  from public.profiles p
  cross join public.leave_types t
  where t.is_active and p.is_active and p.can_login
    and (p_all or p.id = auth.uid())
  order by p.full_name, t.sort_order;
end;
$$;
revoke all on function public.leave_balances(boolean) from public, anon;
grant execute on function public.leave_balances(boolean) to authenticated;

-- ---- Notifications: the approver hears of a request, the requester of the decision
alter table public.notifications drop constraint notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in (
    'deal_assigned', 'lead_assigned', 'activity_scheduled', 'activity_reminder',
    'deal_unassigned', 'deals_unassigned', 'visit_pending', 'visit_update',
    'work_stage_changed', 'work_request_created', 'work_assigned', 'work_request_withdrawn',
    'work_request_done', 'task_assigned', 'task_done', 'leave_request', 'leave_decided'
  ));

create or replace function public.notify_leave_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_kind text := case when tg_table_name = 'leave_requests' then 'vacation' else 'delay' end;
  v_params jsonb;
begin
  -- one function serves both tables, so each table's own columns are read in its own branch
  if v_kind = 'vacation' then
    v_params := jsonb_build_object('kind', 'vacation', 'request_id', new.id, 'from', new.start_date, 'to', new.end_date, 'days', new.days,
      'type', (select name from public.leave_types where id = new.leave_type_id), 'who', new.user_id, 'by', auth.uid());
  else
    v_params := jsonb_build_object('kind', 'delay', 'request_id', new.id, 'date', new.delay_date, 'hours', new.hours, 'who', new.user_id, 'by', auth.uid());
  end if;
  if tg_op = 'INSERT' then
    perform public.notify_user(new.approver_id, 'leave_request', v_params);
  elsif new.status in ('approved', 'rejected') and old.status = 'pending' then
    perform public.notify_user(new.user_id, 'leave_decided', v_params || jsonb_build_object('approved', new.status = 'approved'));
  end if;
  return new;
end;
$$;
create trigger leave_requests_notify after insert or update of status on public.leave_requests
  for each row execute function public.notify_leave_changes();
create trigger leave_delay_notify after insert or update of status on public.leave_delay_requests
  for each row execute function public.notify_leave_changes();

-- ---- Access rules
alter table public.leave_types enable row level security;
alter table public.leave_policy enable row level security;
alter table public.user_work_schedules enable row level security;
alter table public.leave_user_credits enable row level security;
alter table public.leave_requests enable row level security;
alter table public.leave_delay_requests enable row level security;

-- settings: everyone reads the types and the policy; the Leave setting changes them
create policy leave_types_select on public.leave_types for select using (auth.uid() is not null);
create policy leave_types_write on public.leave_types for all
  using (public.has_permission('settings', 'leave')) with check (public.has_permission('settings', 'leave'));
create policy leave_policy_select on public.leave_policy for select using (auth.uid() is not null);
create policy leave_policy_update on public.leave_policy for update
  using (public.has_permission('settings', 'leave')) with check (public.has_permission('settings', 'leave'));
create policy user_work_schedules_select on public.user_work_schedules for select
  using (profile_id = auth.uid() or public.has_permission('leave', 'view_all') or public.has_permission('settings', 'leave'));
create policy user_work_schedules_write on public.user_work_schedules for all
  using (public.has_permission('settings', 'leave')) with check (public.has_permission('settings', 'leave'));
create policy leave_user_credits_select on public.leave_user_credits for select
  using (profile_id = auth.uid() or public.has_permission('leave', 'view_all') or public.has_permission('settings', 'leave'));
create policy leave_user_credits_write on public.leave_user_credits for all
  using (public.has_permission('settings', 'leave')) with check (public.has_permission('settings', 'leave'));

-- requests: yours, the ones sent to you, and (view all) everyone's
create policy leave_requests_select on public.leave_requests for select
  using (user_id = auth.uid() or approver_id = auth.uid() or public.has_permission('leave', 'view_all'));
create policy leave_requests_insert on public.leave_requests for insert
  with check (user_id = auth.uid() and status = 'pending');
create policy leave_requests_cancel on public.leave_requests for update
  using (user_id = auth.uid() and status = 'pending') with check (user_id = auth.uid() and status = 'cancelled');
create policy leave_delay_select on public.leave_delay_requests for select
  using (user_id = auth.uid() or approver_id = auth.uid() or public.has_permission('leave', 'view_all'));
create policy leave_delay_insert on public.leave_delay_requests for insert
  with check (user_id = auth.uid() and status = 'pending');
create policy leave_delay_cancel on public.leave_delay_requests for update
  using (user_id = auth.uid() and status = 'pending') with check (user_id = auth.uid() and status = 'cancelled');

-- ---- Files of a request (the sick leave certificate), in a private bucket: <user id>/<file>
insert into storage.buckets (id, name, public) values ('leave-files', 'leave-files', false) on conflict (id) do nothing;

create or replace function public.leave_file_can_view(p_path text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select split_part(p_path, '/', 1) = auth.uid()::text
    or public.has_permission('leave', 'view_all')
    or exists (
      select 1 from public.leave_requests r
      where r.approver_id = auth.uid() and r.attachments @> jsonb_build_array(jsonb_build_object('path', p_path))
    );
$$;
revoke all on function public.leave_file_can_view(text) from public, anon;
grant execute on function public.leave_file_can_view(text) to authenticated;

create policy leave_files_insert on storage.objects for insert
  with check (bucket_id = 'leave-files' and split_part(name, '/', 1) = auth.uid()::text);
create policy leave_files_select on storage.objects for select
  using (bucket_id = 'leave-files' and public.leave_file_can_view(name));
create policy leave_files_delete on storage.objects for delete
  using (bucket_id = 'leave-files' and split_part(name, '/', 1) = auth.uid()::text);
