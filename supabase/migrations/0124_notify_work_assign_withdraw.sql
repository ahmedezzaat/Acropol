-- More notifications from the sub-workflow boards:
--   * a card is assigned to someone on the board -> that person
--   * a card changes stage -> now also the person who sent the request
--   * a request is withdrawn -> everyone who works that board
--   * a card reaches the last stage of the board -> the requester gets a "your request is
--     done" notification (instead of the plain stage-change one)
alter table public.notifications drop constraint notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in (
    'deal_assigned', 'lead_assigned', 'activity_scheduled', 'activity_reminder',
    'deal_unassigned', 'deals_unassigned', 'visit_pending', 'visit_update',
    'work_stage_changed', 'work_request_created', 'work_assigned', 'work_request_withdrawn',
    'work_request_done'
  ));

-- Everyone who works a board: "see every board", that board's own permission, and admins.
create or replace function public.work_board_users(p_pipeline_id uuid)
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select p.id
  from public.profiles p
  where p.is_active
    and (
      p.is_admin
      or exists (
        select 1 from public.role_permissions rp
        where rp.role_id = p.role_id
          and rp.module = 'crm_work'
          and rp.action in ('view', p_pipeline_id::text)
      )
    );
$$;
revoke all on function public.work_board_users(uuid) from public, anon, authenticated;

-- 1. A card is assigned on the board.
create or replace function public.notify_work_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.assigned_to is null or new.assigned_to is not distinct from auth.uid() then
    return new;
  end if;
  perform public.notify_user(new.assigned_to, 'work_assigned', jsonb_build_object(
    'deal_id', new.deal_id,
    'name', new.title,
    'board', (select name from public.work_pipelines where id = new.work_pipeline_id),
    'work_item_id', new.id,
    'work_pipeline_id', new.work_pipeline_id,
    'by', auth.uid()
  ));
  return new;
end;
$$;

drop trigger if exists work_items_notify_assignment on public.work_items;
create trigger work_items_notify_assignment
  after update of assigned_to on public.work_items
  for each row
  when (new.assigned_to is distinct from old.assigned_to)
  execute function public.notify_work_assignment();

-- 4. Stage change: the requester hears about it too.
create or replace function public.notify_work_stage_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deal public.deals;
  v_board text;
  v_from text;
  v_to text;
  v_user uuid;
  v_params jsonb;
  v_is_last boolean;
begin
  if new.stage_id is not distinct from old.stage_id then
    return new;
  end if;

  select * into v_deal from public.deals where id = new.deal_id;
  select name into v_board from public.work_pipelines where id = new.work_pipeline_id;
  select name into v_from from public.work_pipeline_stages where id = old.stage_id;
  select name into v_to from public.work_pipeline_stages where id = new.stage_id;
  -- the last stage of the board: nothing comes after it
  select not exists (
    select 1 from public.work_pipeline_stages s
    where s.work_pipeline_id = new.work_pipeline_id
      and s.sort_order > (select sort_order from public.work_pipeline_stages where id = new.stage_id)
  ) into v_is_last;

  v_params := jsonb_build_object(
    'deal_id', new.deal_id,
    'name', new.title,
    'board', v_board,
    'from_stage', v_from,
    'to_stage', v_to,
    'work_item_id', new.id,
    'work_pipeline_id', new.work_pipeline_id,
    'by', auth.uid()
  );

  -- the deal's agent, the person who sent the request, and everyone who can view all
  -- deals (or is an admin)
  for v_user in
    select v_deal.assigned_to where v_deal.assigned_to is not null
    union
    select new.created_by where new.created_by is not null
    union
    select p.id
    from public.profiles p
    where p.is_active
      and (
        p.is_admin
        or exists (
          select 1 from public.role_permissions rp
          where rp.role_id = p.role_id and rp.module = 'crm_deals' and rp.action = 'view_all'
        )
      )
  loop
    if v_user is distinct from auth.uid() then
      perform public.notify_user(
        v_user,
        case when v_is_last and v_user = new.created_by then 'work_request_done' else 'work_stage_changed' end,
        v_params
      );
    end if;
  end loop;

  return new;
end;
$$;

-- 2. A request is withdrawn.
create or replace function public.notify_work_request_withdrawn()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_params jsonb;
  v_user uuid;
begin
  v_params := jsonb_build_object(
    'deal_id', old.deal_id,
    'name', old.title,
    'board', (select name from public.work_pipelines where id = old.work_pipeline_id),
    'work_pipeline_id', old.work_pipeline_id,
    'by', auth.uid()
  );
  for v_user in select * from public.work_board_users(old.work_pipeline_id) loop
    if v_user is distinct from auth.uid() then
      perform public.notify_user(v_user, 'work_request_withdrawn', v_params);
    end if;
  end loop;
  return old;
end;
$$;

drop trigger if exists work_items_notify_withdrawn on public.work_items;
create trigger work_items_notify_withdrawn
  after delete on public.work_items
  for each row execute function public.notify_work_request_withdrawn();
