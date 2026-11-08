-- Who approves a person's requests: set once per person in Settings -> Leave. A request then goes to
-- that person automatically (whatever the form sent). People with no approver set still pick one.
-- Being set as someone's approver is enough to approve their requests.
create table public.leave_approval_routes (
  profile_id uuid primary key references public.profiles (id) on delete cascade,
  approver_id uuid not null references public.profiles (id) on delete cascade,
  check (profile_id <> approver_id)
);
alter table public.leave_approval_routes enable row level security;
create policy leave_routes_select on public.leave_approval_routes for select
  using (profile_id = auth.uid() or approver_id = auth.uid() or public.has_permission('leave', 'view_all') or public.has_permission('settings', 'leave'));
create policy leave_routes_write on public.leave_approval_routes for all
  using (public.has_permission('settings', 'leave')) with check (public.has_permission('settings', 'leave'));

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
        or exists (select 1 from public.leave_approval_routes r where r.approver_id = p.id)
      )
  );
$$;

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
  v_route uuid;
begin
  -- a person with a set approver always goes to that person
  select approver_id into v_route from public.leave_approval_routes where profile_id = new.user_id;
  if v_route is not null then new.approver_id := v_route; end if;
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

create or replace function public.leave_delay_validate()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_policy public.leave_policy;
  v_route uuid;
begin
  select approver_id into v_route from public.leave_approval_routes where profile_id = new.user_id;
  if v_route is not null then new.approver_id := v_route; end if;
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
