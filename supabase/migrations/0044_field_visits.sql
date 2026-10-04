-- Field trips (مأمورية) and inspections (معاينة): outdoor work on a deal that
-- must be approved before it happens.
--
-- Approval is two steps:
--   1. the requester's team leader (skipped when the requester has no team
--      leader, or is the team leader),
--   2. a final approver: anyone with crm_visits "approve" or "view all"
--      (admins always).
-- Nobody approves their own request. After approval a visit ends as done or
-- cancelled, each with a mandatory note; rejection needs a note too.
--
--   pending_leader -> pending_final -> approved -> done | cancelled
--        |                |               |
--        +-> rejected <---+               +-> cancelled
create table public.field_visits (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('field_trip', 'inspection')),
  deal_id uuid not null references public.deals (id) on delete cascade,
  requested_by uuid not null references public.profiles (id),
  visit_date date not null,
  time_from time not null,
  time_to time not null,
  address text not null,
  notes text,
  status text not null default 'pending_leader'
    check (status in ('pending_leader', 'pending_final', 'approved', 'rejected', 'done', 'cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint field_visits_time_order check (time_to > time_from)
);

create index field_visits_deal on public.field_visits (deal_id);
create index field_visits_requester on public.field_visits (requested_by);
create index field_visits_status on public.field_visits (status);

-- Audit trail: every submission, approval, rejection and closing, with its note.
create table public.field_visit_events (
  id uuid primary key default gen_random_uuid(),
  visit_id uuid not null references public.field_visits (id) on delete cascade,
  action text not null check (action in ('submitted', 'leader_approved', 'approved', 'rejected', 'done', 'cancelled')),
  actor_id uuid references public.profiles (id),
  note text,
  created_at timestamptz not null default now()
);
create index field_visit_events_visit on public.field_visit_events (visit_id, created_at);

alter table public.field_visits enable row level security;
alter table public.field_visit_events enable row level security;

-- The requester's team leader (null when there is none).
create or replace function public.visit_leader_of(p_requester uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select t.leader_id from public.profiles p join public.teams t on t.id = p.team_id where p.id = p_requester
$$;
revoke all on function public.visit_leader_of(uuid) from public, anon, authenticated;

-- Final approvers: admins and anyone whose role grants crm_visits approve / view_all.
create or replace function public.visit_final_approvers()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select p.id from public.profiles p
  where p.is_active
    and (
      p.is_admin
      or exists (
        select 1 from public.role_permissions rp
        where rp.role_id = p.role_id and rp.module = 'crm_visits' and rp.action in ('approve', 'view_all')
      )
    )
$$;
revoke all on function public.visit_final_approvers() from public, anon, authenticated;

-- Visibility: your own requests; your team members' requests when you lead the
-- team; everything for approvers / view-all (they need to see what to approve).
create policy field_visits_select on public.field_visits
  for select
  using (
    public.has_any_module_permission('crm_visits')
    and (
      requested_by = auth.uid()
      or public.leads_my_team(requested_by)
      or public.has_permission('crm_visits', 'view_all')
      or public.has_permission('crm_visits', 'approve')
    )
  );

-- Requesting needs the create permission and a deal you can already see.
create policy field_visits_insert on public.field_visits
  for insert
  with check (
    requested_by = auth.uid()
    and public.has_permission('crm_visits', 'create')
    and exists (select 1 from public.deals d where d.id = deal_id)
  );

-- Editing: the requester only, with the edit permission (the guard trigger
-- below further limits it to requests no one has approved yet).
create policy field_visits_update on public.field_visits
  for update
  using (requested_by = auth.uid() and public.has_permission('crm_visits', 'edit'))
  with check (requested_by = auth.uid());

create policy field_visit_events_select on public.field_visit_events
  for select
  using (exists (select 1 from public.field_visits v where v.id = visit_id));

-- Insert: choose the first approval step, and keep clients from forging a status.
create or replace function public.field_visit_init()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_leader uuid := public.visit_leader_of(new.requested_by);
begin
  new.status := case when v_leader is null or v_leader = new.requested_by then 'pending_final' else 'pending_leader' end;
  return new;
end;
$$;

create trigger field_visits_init
  before insert on public.field_visits
  for each row execute function public.field_visit_init();

-- After insert: record the submission and tell whoever must approve first.
create or replace function public.field_visit_after_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_leader uuid := public.visit_leader_of(new.requested_by);
  v_user uuid;
  v_params jsonb := jsonb_build_object(
    'visit_id', new.id,
    'kind', new.kind,
    'name', public.deal_display_name(new.deal_id),
    'visit_date', new.visit_date,
    'requested_by', new.requested_by
  );
begin
  insert into public.field_visit_events (visit_id, action, actor_id) values (new.id, 'submitted', new.requested_by);

  if new.status = 'pending_leader' then
    perform public.notify_user(v_leader, 'visit_pending', v_params || '{"step":"leader"}'::jsonb);
  else
    for v_user in select * from public.visit_final_approvers() loop
      if v_user <> new.requested_by then
        perform public.notify_user(v_user, 'visit_pending', v_params || '{"step":"final"}'::jsonb);
      end if;
    end loop;
  end if;
  return new;
end;
$$;

create trigger field_visits_after_insert
  after insert on public.field_visits
  for each row execute function public.field_visit_after_insert();

-- Update guard: outside field_visit_action() only the request details can
-- change, and only while nobody has approved it yet.
create or replace function public.field_visit_guard()
returns trigger
language plpgsql
as $$
begin
  if current_setting('acropol.visit_action', true) = 'true' then
    new.updated_at := now();
    return new;
  end if;

  if new.status is distinct from old.status
     or new.requested_by is distinct from old.requested_by
     or new.deal_id is distinct from old.deal_id then
    raise exception 'status, requester and deal cannot be changed directly';
  end if;

  if old.status not in ('pending_leader', 'pending_final')
     or exists (select 1 from public.field_visit_events e where e.visit_id = old.id and e.action = 'leader_approved') then
    raise exception 'this request can no longer be edited';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create trigger field_visits_guard
  before update on public.field_visits
  for each row execute function public.field_visit_guard();

-- Every status change goes through here: approve / reject / done / cancel.
create or replace function public.field_visit_action(p_visit uuid, p_action text, p_note text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.field_visits%rowtype;
  me uuid := auth.uid();
  v_leader uuid;
  v_is_requester boolean;
  v_is_leader boolean;
  v_is_final boolean;
  v_is_admin boolean;
  v_new text;
  v_event text;
  v_user uuid;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_params jsonb;
begin
  if me is null then
    raise exception 'not authenticated';
  end if;

  select * into v from public.field_visits where id = p_visit for update;
  if not found then
    raise exception 'request not found';
  end if;

  v_leader := public.visit_leader_of(v.requested_by);
  v_is_requester := v.requested_by = me;
  v_is_leader := v_leader is not null and v_leader = me;
  v_is_final := public.has_permission('crm_visits', 'approve') or public.has_permission('crm_visits', 'view_all');
  v_is_admin := exists (select 1 from public.profiles p where p.id = me and p.is_admin);

  -- This function bypasses RLS, so enforce who may touch the request here:
  -- someone with access to the module who is the requester, their team
  -- leader, or a final approver.
  if not public.has_any_module_permission('crm_visits')
     or not (v_is_requester or v_is_leader or v_is_final or v_is_admin) then
    raise exception 'request not found';
  end if;

  if p_action in ('reject', 'done', 'cancel') and v_note is null then
    raise exception 'a note is required';
  end if;

  if p_action = 'approve' then
    if v_is_requester then raise exception 'you cannot approve your own request'; end if;
    if v.status = 'pending_leader' and (v_is_leader or v_is_admin) then
      v_new := 'pending_final'; v_event := 'leader_approved';
    elsif v.status = 'pending_final' and v_is_final then
      v_new := 'approved'; v_event := 'approved';
    else
      raise exception 'you cannot approve this request at its current step';
    end if;
  elsif p_action = 'reject' then
    if v_is_requester then raise exception 'you cannot reject your own request'; end if;
    if (v.status = 'pending_leader' and (v_is_leader or v_is_admin)) or (v.status = 'pending_final' and v_is_final) then
      v_new := 'rejected'; v_event := 'rejected';
    else
      raise exception 'you cannot reject this request at its current step';
    end if;
  elsif p_action = 'done' then
    if v.status = 'approved' and (v_is_requester or v_is_leader or v_is_final) then
      v_new := 'done'; v_event := 'done';
    else
      raise exception 'only an approved request can be marked done';
    end if;
  elsif p_action = 'cancel' then
    if v.status in ('pending_leader', 'pending_final', 'approved') and (v_is_requester or v_is_leader or v_is_final) then
      v_new := 'cancelled'; v_event := 'cancelled';
    else
      raise exception 'this request cannot be cancelled';
    end if;
  else
    raise exception 'unknown action';
  end if;

  perform set_config('acropol.visit_action', 'true', true);
  update public.field_visits set status = v_new where id = v.id;
  perform set_config('acropol.visit_action', 'false', true);

  insert into public.field_visit_events (visit_id, action, actor_id, note) values (v.id, v_event, me, v_note);

  v_params := jsonb_build_object(
    'visit_id', v.id,
    'kind', v.kind,
    'name', public.deal_display_name(v.deal_id),
    'visit_date', v.visit_date
  );

  -- Requester hears about every outcome decided by someone else.
  if not v_is_requester then
    perform public.notify_user(v.requested_by, 'visit_update',
      v_params || jsonb_build_object('status', v_new, 'by', me));
  end if;

  -- The team leader's approval hands the request to the final approvers.
  if v_new = 'pending_final' then
    for v_user in select * from public.visit_final_approvers() loop
      if v_user <> v.requested_by and v_user <> me then
        perform public.notify_user(v_user, 'visit_pending',
          v_params || jsonb_build_object('step', 'final', 'requested_by', v.requested_by));
      end if;
    end loop;
  end if;

  return v_new;
end;
$$;

revoke all on function public.field_visit_action(uuid, text, text) from public, anon;
grant execute on function public.field_visit_action(uuid, text, text) to authenticated;

-- Notification types for the new flow.
alter table public.notifications drop constraint notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in (
    'deal_assigned', 'lead_assigned', 'activity_scheduled', 'activity_reminder',
    'deal_unassigned', 'deals_unassigned', 'visit_pending', 'visit_update'
  ));
