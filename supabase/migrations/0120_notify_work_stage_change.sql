-- When a card moves to another stage on a sub-workflow board (e.g. the technical
-- office), the deal's assigned agent and everyone who can view all deals are
-- notified. The person who moved it is not.
alter table public.notifications drop constraint notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in (
    'deal_assigned', 'lead_assigned', 'activity_scheduled', 'activity_reminder',
    'deal_unassigned', 'deals_unassigned', 'visit_pending', 'visit_update',
    'work_stage_changed'
  ));

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
begin
  if new.stage_id is not distinct from old.stage_id then
    return new;
  end if;

  select * into v_deal from public.deals where id = new.deal_id;
  select name into v_board from public.work_pipelines where id = new.work_pipeline_id;
  select name into v_from from public.work_pipeline_stages where id = old.stage_id;
  select name into v_to from public.work_pipeline_stages where id = new.stage_id;

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

  -- the deal's agent, and every active user who can view all deals (or is an admin)
  for v_user in
    select v_deal.assigned_to where v_deal.assigned_to is not null
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
      perform public.notify_user(v_user, 'work_stage_changed', v_params);
    end if;
  end loop;

  return new;
end;
$$;

drop trigger if exists work_items_notify_stage_change on public.work_items;
create trigger work_items_notify_stage_change
  after update of stage_id on public.work_items
  for each row execute function public.notify_work_stage_change();
