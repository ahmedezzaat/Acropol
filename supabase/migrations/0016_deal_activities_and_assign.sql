-- Deal assignment, mirroring leads: deals already had assigned_to but it
-- was never surfaced or enforced. Add the 'assign' permission action
-- (role_permissions.action is free text, no schema change needed there)
-- and enforce it the same way leads does — a trigger, not just UI, and
-- covering INSERT too (you may assign a new deal to yourself without the
-- permission, but not to someone else).
create or replace function public.enforce_deal_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.assigned_to is not null
       and new.assigned_to is distinct from auth.uid()
       and not public.has_permission('crm_deals', 'assign') then
      raise exception 'insufficient permission to assign this deal';
    end if;
    return new;
  end if;

  if new.assigned_to is distinct from old.assigned_to
     and not public.has_permission('crm_deals', 'assign') then
    raise exception 'insufficient permission to reassign deal';
  end if;
  return new;
end;
$$;

create trigger deals_enforce_assignment
  before insert or update on public.deals
  for each row execute function public.enforce_deal_assignment();

-- The deal timeline: manually logged notes/calls/meetings/site-visits
-- (optionally scheduled with a due time and later marked complete) plus
-- system-logged events (created, stage changed, reassigned) — one table so
-- the timeline is a single chronological query, not a union of several.
create table public.deal_activities (
  id uuid primary key default gen_random_uuid(),
  deal_id uuid not null references public.deals (id) on delete cascade,
  type text not null check (type in ('note', 'call', 'meeting', 'site_visit', 'stage_changed', 'assigned', 'created')),
  content text,
  scheduled_at timestamptz,
  completed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now()
);

alter table public.deal_activities enable row level security;

create policy deal_activities_select on public.deal_activities
  for select
  using (public.has_any_module_permission('crm_deals'));

create policy deal_activities_insert on public.deal_activities
  for insert
  with check (public.has_permission('crm_deals', 'edit'));

create policy deal_activities_update on public.deal_activities
  for update
  using (public.has_permission('crm_deals', 'edit'));

create policy deal_activities_delete on public.deal_activities
  for delete
  using (public.has_permission('crm_deals', 'edit'));

-- System events are logged server-side unconditionally (security definer
-- bypasses the insert policy above, same reasoning as elsewhere: the real
-- gate is that you already needed 'edit' permission to update the deals
-- row that triggers this in the first place).
create or replace function public.log_deal_activity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.deal_activities (deal_id, type, created_by)
    values (new.id, 'created', auth.uid());
    return new;
  end if;

  if new.stage_id is distinct from old.stage_id then
    insert into public.deal_activities (deal_id, type, metadata, created_by)
    values (
      new.id, 'stage_changed',
      jsonb_build_object('from_stage_id', old.stage_id, 'to_stage_id', new.stage_id),
      auth.uid()
    );
  end if;

  if new.assigned_to is distinct from old.assigned_to then
    insert into public.deal_activities (deal_id, type, metadata, created_by)
    values (
      new.id, 'assigned',
      jsonb_build_object('from', old.assigned_to, 'to', new.assigned_to),
      auth.uid()
    );
  end if;

  return new;
end;
$$;

create trigger deals_log_activity
  after insert or update on public.deals
  for each row execute function public.log_deal_activity();
