-- Automation stay time counts WORKING hours only: Friday and Saturday (the
-- weekend, in Cairo time) are not counted. A deal that entered a stage on
-- Thursday 10:00 has stayed 24 working hours by Sunday 10:00 — not 72.
--
-- Hours elapsed between two instants, skipping every Friday and Saturday
-- (local Cairo calendar days). Weekday numbering: Sunday = 0 ... Friday = 5,
-- Saturday = 6. Working time can never exceed real elapsed time, so callers
-- can safely pre-filter on real elapsed time before calling this.
create or replace function public.working_hours_between(p_from timestamptz, p_to timestamptz)
returns numeric
language sql
stable
as $$
  select coalesce(sum(
    greatest(
      0,
      extract(epoch from (
        least(d.day + interval '1 day', t.local_to) - greatest(d.day, t.local_from)
      ))
    )
  ), 0) / 3600.0
  from (
    select (p_from at time zone 'Africa/Cairo') as local_from,
           (p_to at time zone 'Africa/Cairo') as local_to
  ) t
  cross join lateral generate_series(
    date_trunc('day', t.local_from),
    date_trunc('day', t.local_to),
    interval '1 day'
  ) as d(day)
  where p_to > p_from
    and extract(dow from d.day) not in (5, 6)
$$;

-- Same engine as before, with the stay-time test measured in working hours.
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
      -- cheap pre-filter: working time is never more than real time
      and c.since <= now() - make_interval(hours => r.after_hours)
      and public.working_hours_between(c.since, now()) >= r.after_hours
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
