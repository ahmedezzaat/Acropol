-- Settings pages become permissions: a role can be granted any of them
-- (module "settings", one action per page) and its users then manage that page
-- without being administrators. Administrators keep all of them.
-- has_permission() already treats an active administrator as holding everything.

-- Roles and their permissions
alter policy roles_admin_all on public.roles
  using (public.has_permission('settings', 'roles')) with check (public.has_permission('settings', 'roles'));
alter policy role_permissions_admin_write on public.role_permissions
  with check (public.has_permission('settings', 'roles'));
alter policy role_permissions_admin_update on public.role_permissions
  using (public.has_permission('settings', 'roles')) with check (public.has_permission('settings', 'roles'));
alter policy role_permissions_admin_delete on public.role_permissions
  using (public.has_permission('settings', 'roles'));

-- CRM pipelines, their stages and stage reasons
alter policy pipelines_admin_all on public.pipelines
  using (public.has_permission('settings', 'pipelines')) with check (public.has_permission('settings', 'pipelines'));
alter policy pipeline_stages_admin_all on public.pipeline_stages
  using (public.has_permission('settings', 'pipelines')) with check (public.has_permission('settings', 'pipelines'));
alter policy pipeline_stage_reasons_admin_all on public.pipeline_stage_reasons
  using (public.has_permission('settings', 'pipelines')) with check (public.has_permission('settings', 'pipelines'));

alter policy activity_types_admin_all on public.activity_types
  using (public.has_permission('settings', 'activity_types')) with check (public.has_permission('settings', 'activity_types'));
alter policy product_categories_admin_all on public.product_categories
  using (public.has_permission('settings', 'product_categories')) with check (public.has_permission('settings', 'product_categories'));
alter policy automation_rules_admin_all on public.automation_rules
  using (public.has_permission('settings', 'automation')) with check (public.has_permission('settings', 'automation'));
alter policy service_areas_admin_all on public.service_areas
  using (public.has_permission('settings', 'service_areas')) with check (public.has_permission('settings', 'service_areas'));
alter policy cs_pipelines_admin_all on public.cs_pipelines
  using (public.has_permission('settings', 'cs_pipelines')) with check (public.has_permission('settings', 'cs_pipelines'));
alter policy cs_pipeline_stages_admin_all on public.cs_pipeline_stages
  using (public.has_permission('settings', 'cs_pipelines')) with check (public.has_permission('settings', 'cs_pipelines'));
alter policy visit_types_admin_all on public.visit_types
  using (public.has_permission('settings', 'visit_types')) with check (public.has_permission('settings', 'visit_types'));

-- Teams
alter policy teams_admin_write on public.teams
  with check (public.has_permission('settings', 'teams'));
alter policy teams_admin_update on public.teams
  using (public.has_permission('settings', 'teams')) with check (public.has_permission('settings', 'teams'));
alter policy teams_admin_delete on public.teams
  using (public.has_permission('settings', 'teams'));

-- Team membership lives on the profile, and the profiles update policy stays
-- administrator-only (it would also allow changing roles). The Teams page moves
-- people through this function instead.
create or replace function public.set_profiles_team(p_profile_ids uuid[], p_team_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_permission('settings', 'teams') then
    raise exception 'insufficient permission to change team assignment';
  end if;
  update public.profiles set team_id = p_team_id where id = any (p_profile_ids);
end;
$$;

create or replace function public.enforce_team_id_admin_only()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Server-side code (no signed-in user) and the Teams permission may move people.
  if new.team_id is distinct from old.team_id
     and auth.uid() is not null
     and not public.has_permission('settings', 'teams') then
    raise exception 'insufficient permission to change team assignment';
  end if;
  return new;
end;
$$;

-- Running the automation rules ("Run now").
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
     and not public.has_permission('settings', 'automation') then
    raise exception 'insufficient permission to run automation rules';
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
