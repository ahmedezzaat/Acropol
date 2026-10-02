-- Second condition for automation rules: whether the deal's CURRENT assignee
-- has written a note on it. 'any' keeps the old behaviour (no condition).
alter table public.automation_rules
  add column note_condition text not null default 'any'
  check (note_condition in ('any', 'no_note', 'has_note'));

-- The mandatory note a user writes when moving a deal to a new stage is stored
-- as an ordinary 'note' activity right after the stage_changed row. It's a
-- hand-over comment, not follow-up work, so it must not satisfy "has written a
-- note". New ones are tagged by the app (metadata.stage_change); this tags the
-- ones already in the database — a note logged within seconds after a stage
-- change on the same deal.
update public.deal_activities n
set metadata = n.metadata || '{"stage_change": true}'::jsonb
where n.type = 'note'
  and exists (
    select 1 from public.deal_activities s
    where s.deal_id = n.deal_id
      and s.type = 'stage_changed'
      and n.created_at >= s.created_at
      and n.created_at <= s.created_at + interval '10 seconds'
  );

-- Conflict guard (replaces the one-active-rule-per-stage index): with
-- conditions, two rules on one stage are no longer simply "duplicates".
-- Rule A *covers* rule B when every deal that matches B also matches A
-- (A is 'any', or both have the same condition). If A covers B and A's
-- threshold is not later than B's, A always acts first and B can never run.
-- A *more specific* rule with an EARLIER threshold (e.g. any @48h plus
-- no_note @24h) is a legitimate layered setup and is allowed.
drop index if exists public.automation_rules_one_active_action_per_stage;

create or replace function public.validate_automation_rule()
returns trigger
language plpgsql
as $$
declare
  v_other record;
begin
  if exists (select 1 from public.pipeline_stages s where s.id = new.stage_id and s.is_closed) then
    raise exception 'automation rules cannot target a closed stage';
  end if;

  if new.is_active then
    select o.name into v_other
    from public.automation_rules o
    where o.id is distinct from new.id
      and o.is_active
      and o.stage_id = new.stage_id
      and o.action = new.action
      and (
        ((o.note_condition = 'any' or o.note_condition = new.note_condition) and o.after_hours <= new.after_hours)
        or ((new.note_condition = 'any' or new.note_condition = o.note_condition) and new.after_hours <= o.after_hours)
      )
    limit 1;

    if found then
      raise exception 'conflicts with the active rule "%" on the same stage', v_other.name;
    end if;
  end if;

  return new;
end;
$$;

-- Engine, now honouring note_condition. A note counts when it is a real
-- 'note' (not a stage-change hand-over note), written by the deal's current
-- assignee, since the clock started (the later of stage entry / last
-- assignment). Rules run lowest-threshold first so that, when a deal matches
-- several, the most urgent rule is the one recorded in its history.
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
  if auth.uid() is not null
     and not exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin) then
    raise exception 'only admins can run automation rules';
  end if;

  for r in
    select id, stage_id, after_hours, note_condition
    from public.automation_rules
    where is_active and action = 'unassign'
    order by after_hours, created_at
  loop
    select coalesce(array_agg(d.id), '{}') into v_ids
    from public.deals d
    cross join lateral (
      select greatest(
        coalesce((select max(a.created_at) from public.deal_activities a
                  where a.deal_id = d.id and a.type = 'stage_changed'), d.created_at),
        coalesce((select max(a.created_at) from public.deal_activities a
                  where a.deal_id = d.id and a.type = 'assigned'), d.created_at)
      ) as since
    ) c
    where d.stage_id = r.stage_id
      and d.assigned_to is not null
      and c.since <= now() - make_interval(hours => r.after_hours)
      and (
        r.note_condition = 'any'
        or (r.note_condition = 'has_note') = exists (
          select 1 from public.deal_activities n
          where n.deal_id = d.id
            and n.type = 'note'
            and n.created_by = d.assigned_to
            and n.created_at >= c.since
            and coalesce((n.metadata ->> 'stage_change')::boolean, false) = false
        )
      );

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
