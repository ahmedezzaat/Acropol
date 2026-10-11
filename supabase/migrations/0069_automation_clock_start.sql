-- The automation stay-time clock starts at 11:59 AM (Cairo), on a working day
-- (Sunday to Thursday):
--   * a deal that enters a stage before 11:59 AM starts counting at 11:59 AM that
--     day, so at 11:30 AM its stay time is still zero;
--   * between 11:59 AM and 5:00 PM it starts counting at once;
--   * after 5:00 PM it starts the next working day at 11:59 AM;
--   * on a Friday or Saturday it starts the next Sunday at 11:59 AM.
-- From there the stay time counts working hours as before (Friday and Saturday
-- are never counted).
create or replace function public.automation_clock_start(p_since timestamptz)
returns timestamptz
language plpgsql
stable
as $$
declare
  v_local timestamp := p_since at time zone 'Africa/Cairo';
  v_day timestamp := date_trunc('day', v_local);
  v_next timestamp;
begin
  if extract(dow from v_day) in (5, 6) or v_local > v_day + interval '17 hours' then
    -- next working day
    v_next := v_day + interval '1 day';
    while extract(dow from v_next) in (5, 6) loop
      v_next := v_next + interval '1 day';
    end loop;
    return (v_next + interval '11 hours 59 minutes') at time zone 'Africa/Cairo';
  end if;
  if v_local < v_day + interval '11 hours 59 minutes' then
    return (v_day + interval '11 hours 59 minutes') at time zone 'Africa/Cairo';
  end if;
  return p_since;
end;
$$;

-- The rule engine, with the stay time measured from that clock start.
create or replace function public.run_automation_rules()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_ids uuid[];
  v_count int;
  v_user uuid;
  v_pipeline uuid;
  v_stage_name text;
  v_total int := 0;
begin
  if auth.uid() is not null
     and not exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin) then
    raise exception 'only admins can run automation rules';
  end if;

  for r in
    select id, name, stage_id, after_hours, note_condition
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
      -- cheap pre-filter: working time is never more than real time
      and c.since <= now() - make_interval(hours => r.after_hours)
      and public.working_hours_between(public.automation_clock_start(c.since), now()) >= r.after_hours
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

    v_count := coalesce(array_length(v_ids, 1), 0);
    if v_count = 0 then
      continue;
    end if;

    perform set_config('acropol.automation', 'true', true);
    perform set_config('acropol.automation_rule', r.id::text, true);

    update public.deals set assigned_to = null where id = any (v_ids);
    v_total := v_total + v_count;

    perform set_config('acropol.automation', 'false', true);
    perform set_config('acropol.automation_rule', '', true);

    -- One notification per rule run, to everyone who can reassign.
    select s.pipeline_id, trim(s.name) into v_pipeline, v_stage_name from public.pipeline_stages s where s.id = r.stage_id;
    for v_user in select * from public.deal_reassigners() loop
      if v_count = 1 then
        perform public.notify_user(v_user, 'deal_unassigned', jsonb_build_object(
          'deal_id', v_ids[1],
          'name', public.deal_display_name(v_ids[1]),
          'rule_id', r.id,
          'rule_name', r.name
        ));
      else
        perform public.notify_user(v_user, 'deals_unassigned', jsonb_build_object(
          'count', v_count,
          'rule_id', r.id,
          'rule_name', r.name,
          'pipeline_id', v_pipeline,
          'stage_id', r.stage_id,
          'stage_name', v_stage_name
        ));
      end if;
    end loop;
  end loop;

  return v_total;
end;
$$;
