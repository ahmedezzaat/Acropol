-- Admin-managed automation rules. First (and so far only) action: "unassign"
-- a deal once it has sat in a stage for N hours. Rules are data, so admins
-- can add as many as they like from Settings without a migration.
--
-- A rule is bound to a stage (which already belongs to exactly one
-- pipeline), so "pipeline Y" is derived rather than stored twice and can
-- never disagree with the stage.
create table public.automation_rules (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  stage_id uuid not null references public.pipeline_stages (id) on delete cascade,
  after_hours int not null check (after_hours > 0),
  action text not null default 'unassign' check (action in ('unassign')),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- Conflict guard #1 (hard): two active rules with the same action on the same
-- stage. Whichever has the lower threshold always fires first, so the other
-- could never act — it is redundant at best, contradictory at worst.
create unique index automation_rules_one_active_action_per_stage
  on public.automation_rules (stage_id, action)
  where is_active;

-- Conflict guard #2 (hard): a closed stage (won / competitor / archive) has
-- no one working it, so an "unassign" rule there is meaningless.
create or replace function public.validate_automation_rule()
returns trigger
language plpgsql
as $$
begin
  if exists (select 1 from public.pipeline_stages s where s.id = new.stage_id and s.is_closed) then
    raise exception 'automation rules cannot target a closed stage';
  end if;
  return new;
end;
$$;

create trigger automation_rules_validate
  before insert or update on public.automation_rules
  for each row execute function public.validate_automation_rule();

alter table public.automation_rules enable row level security;

create policy automation_rules_admin_all on public.automation_rules
  for all
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

-- The engine unassigns on behalf of nobody (no auth.uid()), so the reassign
-- permission check needs a narrow, transaction-local escape hatch — the same
-- pattern as acropol.cascading_assignment. Only the security-definer engine
-- below ever sets it.
create or replace function public.enforce_deal_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_setting('acropol.automation', true) = 'true' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.assigned_to is null then
      if not public.has_permission('crm_deals', 'assign') then
        new.assigned_to := auth.uid();
      end if;
    elsif new.assigned_to is distinct from auth.uid()
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

-- Same timeline logger as before, but an automation-driven reassignment is
-- tagged with the rule that caused it so the deal's history says why.
create or replace function public.log_deal_activity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rule_id uuid := nullif(current_setting('acropol.automation_rule', true), '')::uuid;
  v_meta jsonb;
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
    v_meta := jsonb_build_object('from', old.assigned_to, 'to', new.assigned_to);
    if v_rule_id is not null then
      v_meta := v_meta || jsonb_build_object(
        'automation_rule_id', v_rule_id,
        'automation_rule_name', (select r.name from public.automation_rules r where r.id = v_rule_id)
      );
    end if;
    insert into public.deal_activities (deal_id, type, metadata, created_by)
    values (new.id, 'assigned', v_meta, auth.uid());
  end if;

  return new;
end;
$$;

-- The engine. For every active rule, unassigns each deal that is currently
-- assigned, sitting in the rule's stage, and has been there for at least
-- after_hours. The clock starts at the LATER of
--   * when the deal entered the stage (latest stage_changed, else created_at)
--   * the last time someone assigned it
-- so a manager who deliberately hands a stale deal to someone gets a fresh
-- window instead of having it yanked back on the next run. Deals that are
-- already unassigned are skipped, which keeps every run idempotent.
-- Returns how many deals were unassigned.
create or replace function public.run_automation_rules()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_ids uuid[];
  v_total int := 0;
begin
  -- Cron has no auth.uid(); anyone who does must be an admin ("Run now").
  if auth.uid() is not null
     and not exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin) then
    raise exception 'only admins can run automation rules';
  end if;

  for r in
    select id, stage_id, after_hours from public.automation_rules
    where is_active and action = 'unassign'
  loop
    select coalesce(array_agg(d.id), '{}') into v_ids
    from public.deals d
    where d.stage_id = r.stage_id
      and d.assigned_to is not null
      and greatest(
            coalesce((select max(a.created_at) from public.deal_activities a
                      where a.deal_id = d.id and a.type = 'stage_changed'), d.created_at),
            coalesce((select max(a.created_at) from public.deal_activities a
                      where a.deal_id = d.id and a.type = 'assigned'), d.created_at)
          ) <= now() - make_interval(hours => r.after_hours);

    if array_length(v_ids, 1) is null then
      continue;
    end if;

    perform set_config('acropol.automation', 'true', true);
    perform set_config('acropol.automation_rule', r.id::text, true);

    update public.deals set assigned_to = null where id = any (v_ids);
    v_total := v_total + array_length(v_ids, 1);

    perform set_config('acropol.automation', 'false', true);
    perform set_config('acropol.automation_rule', '', true);
  end loop;

  return v_total;
end;
$$;

revoke all on function public.run_automation_rules() from public;
grant execute on function public.run_automation_rules() to authenticated;

-- Run every 10 minutes. Rules are expressed in whole hours, so this is
-- plenty of resolution without hammering the database.
create extension if not exists pg_cron with schema pg_catalog;

select cron.unschedule(jobid) from cron.job where jobname = 'acropol-automation-rules';
select cron.schedule('acropol-automation-rules', '*/10 * * * *', $$select public.run_automation_rules()$$);
