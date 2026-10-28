-- A new request sent to a sub-workflow board (e.g. the technical office) notifies
-- everyone who works that board: users with "see every board" or this board's own
-- permission, and administrators. The person who sent it is not notified.
alter table public.notifications drop constraint notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in (
    'deal_assigned', 'lead_assigned', 'activity_scheduled', 'activity_reminder',
    'deal_unassigned', 'deals_unassigned', 'visit_pending', 'visit_update',
    'work_stage_changed', 'work_request_created'
  ));

create or replace function public.notify_work_request_created()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_board text;
  v_user uuid;
  v_params jsonb;
begin
  select name into v_board from public.work_pipelines where id = new.work_pipeline_id;
  v_params := jsonb_build_object(
    'deal_id', new.deal_id,
    'name', new.title,
    'board', v_board,
    'work_item_id', new.id,
    'work_pipeline_id', new.work_pipeline_id,
    'by', auth.uid()
  );

  for v_user in
    select p.id
    from public.profiles p
    where p.is_active
      and (
        p.is_admin
        or exists (
          select 1 from public.role_permissions rp
          where rp.role_id = p.role_id
            and rp.module = 'crm_work'
            and rp.action in ('view', new.work_pipeline_id::text)
        )
      )
  loop
    if v_user is distinct from auth.uid() then
      perform public.notify_user(v_user, 'work_request_created', v_params);
    end if;
  end loop;

  return new;
end;
$$;

drop trigger if exists work_items_notify_created on public.work_items;
create trigger work_items_notify_created
  after insert on public.work_items
  for each row execute function public.notify_work_request_created();
