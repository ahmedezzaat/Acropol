-- Tell the people who can reassign (crm_deals "view all", plus admins) when a
-- deal becomes unassigned, so it doesn't sit unnoticed in the pool.
--   * unassigned by a person  -> one notification per deal (to everyone with
--     view all except the person who did it)
--   * unassigned by an automation rule -> one notification per rule run: the
--     deal itself if just one, otherwise a summary ("N deals were unassigned")
--     that opens the Deals page filtered to those unassigned deals. Per-deal
--     notifications would bury a manager when a rule releases 30 deals at once.
alter table public.notifications drop constraint notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in (
    'deal_assigned', 'lead_assigned', 'activity_scheduled', 'activity_reminder',
    'deal_unassigned', 'deals_unassigned'
  ));

-- Everyone who sees all deals: admins, and anyone whose role grants
-- crm_deals:view_all (same rule as has_permission(), minus the auth.uid()).
create or replace function public.deal_reassigners()
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
        where rp.role_id = p.role_id and rp.module = 'crm_deals' and rp.action = 'view_all'
      )
    )
$$;
revoke all on function public.deal_reassigners() from public, anon, authenticated;

create or replace function public.deal_display_name(p_deal uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select l.name from public.leads l where l.id = d.lead_id),
    (select c.name from public.customers c where c.id = d.customer_id),
    d.title
  )
  from public.deals d where d.id = p_deal
$$;
revoke all on function public.deal_display_name(uuid) from public, anon, authenticated;

-- A person unassigns a deal ------------------------------------------------
create or replace function public.notify_deal_unassigned()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid;
begin
  -- Automation runs report once per rule run themselves (see
  -- run_automation_rules); skip them here.
  if current_setting('acropol.automation', true) = 'true' then
    return new;
  end if;

  for v_user in select * from public.deal_reassigners() loop
    if v_user is distinct from auth.uid() then
      perform public.notify_user(v_user, 'deal_unassigned', jsonb_build_object(
        'deal_id', new.id,
        'name', public.deal_display_name(new.id),
        'previous_assignee', old.assigned_to,
        'unassigned_by', auth.uid()
      ));
    end if;
  end loop;
  return new;
end;
$$;

create trigger deals_notify_unassigned
  after update of assigned_to on public.deals
  for each row
  when (old.assigned_to is not null and new.assigned_to is null)
  execute function public.notify_deal_unassigned();

-- Automation rule runs -----------------------------------------------------
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
