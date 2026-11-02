-- Two new technical office permissions:
--  * crm_work_quotes (view / create): see and upload the proposal (عرض السعر) section of a
--    card's window on the board.
--  * crm_work_files.move_to_quote: from the deal's Files tab, move a file the technical office
--    uploaded into the deal's proposal section.
-- Roles that already worked the files keep what they could do: whoever could see technical
-- office files sees the proposal section, whoever could add files uploads to it, and whoever
-- could rename files can move them.
insert into public.role_permissions (role_id, module, action)
select distinct rp.role_id, 'crm_work_quotes', 'view'
from public.role_permissions rp where rp.module = 'crm_work_files' and rp.action = 'view'
on conflict do nothing;

insert into public.role_permissions (role_id, module, action)
select distinct rp.role_id, 'crm_work_quotes', 'create'
from public.role_permissions rp where rp.module = 'crm_work_files' and rp.action = 'create'
on conflict do nothing;

insert into public.role_permissions (role_id, module, action)
select distinct rp.role_id, 'crm_work_files', 'move_to_quote'
from public.role_permissions rp where rp.module = 'crm_work_files' and rp.action = 'edit'
on conflict do nothing;

-- Moving a technical office file into the proposal section of its deal.
create or replace function public.move_work_file_to_quote(p_attachment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_permission('crm_work_files', 'move_to_quote') then
    raise exception 'insufficient permission to move files to the proposal section';
  end if;
  update public.deal_attachments
  set kind = 'quote'
  where id = p_attachment_id
    and from_work_pipeline_id is not null
    and kind is null;
  if not found then
    raise exception 'this file cannot be moved to the proposal section';
  end if;
end;
$$;
revoke all on function public.move_work_file_to_quote(uuid) from public, anon;
grant execute on function public.move_work_file_to_quote(uuid) to authenticated;
