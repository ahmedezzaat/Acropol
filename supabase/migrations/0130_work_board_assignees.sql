-- A card on a sub-workflow board can only be assigned to someone who can open that board
-- (an admin, a user with "see every board", or one with this board's own permission).

-- The people a card of this board can be assigned to; asked by people who see the board.
create or replace function public.work_board_assignees(p_pipeline_id uuid)
returns table (id uuid, full_name text, email text)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not (public.has_permission('crm_work', 'view') or public.has_permission('crm_work', p_pipeline_id::text)) then
    raise exception 'insufficient permission to see this board';
  end if;
  return query
  select p.id, p.full_name, p.email
  from public.profiles p
  where p.id in (select public.work_board_users(p_pipeline_id))
  order by coalesce(nullif(p.full_name, ''), p.email);
end;
$$;
revoke all on function public.work_board_assignees(uuid) from public, anon;
grant execute on function public.work_board_assignees(uuid) to authenticated;

-- The same rule in the database: assigning a card to someone without access is refused.
create or replace function public.work_items_check_assignee()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.assigned_to is not null
     and new.assigned_to is distinct from old.assigned_to
     and not exists (select 1 from public.work_board_users(new.work_pipeline_id) u where u = new.assigned_to) then
    raise exception 'that user cannot open this board';
  end if;
  return new;
end;
$$;

drop trigger if exists work_items_check_assignee on public.work_items;
create trigger work_items_check_assignee
  before update of assigned_to on public.work_items
  for each row execute function public.work_items_check_assignee();
