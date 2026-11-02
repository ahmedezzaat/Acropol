-- The other way round: from the deal's Files tab, move a proposal (عرض السعر) file back into
-- the technical office's own files. A new permission on crm_work_files ("move_from_quote"),
-- given to the roles that can already move files into the proposal.
insert into public.role_permissions (role_id, module, action)
select distinct rp.role_id, 'crm_work_files', 'move_from_quote'
from public.role_permissions rp where rp.module = 'crm_work_files' and rp.action = 'move_to_quote'
on conflict do nothing;

-- A file marked as a proposal becomes one of the technical office's files again. A proposal
-- uploaded directly on the deal (not from the board) is tied to the deal's technical office
-- request first; a deal with no request has nowhere to put it.
create or replace function public.move_quote_file_to_work(p_attachment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_file public.deal_attachments;
  v_item public.work_items;
begin
  if not public.has_permission('crm_work_files', 'move_from_quote') then
    raise exception 'insufficient permission to move files out of the proposal section';
  end if;

  select * into v_file from public.deal_attachments where id = p_attachment_id and kind = 'quote';
  if v_file.id is null then
    raise exception 'this file is not in the proposal section';
  end if;

  if v_file.from_work_pipeline_id is null then
    select * into v_item from public.work_items where deal_id = v_file.deal_id order by created_at limit 1;
    if v_item.id is null then
      raise exception 'this deal has no technical office request to move the file to';
    end if;
    update public.deal_attachments
    set kind = null, from_work_pipeline_id = v_item.work_pipeline_id, work_item_id = coalesce(work_item_id, v_item.id)
    where id = p_attachment_id;
  else
    update public.deal_attachments set kind = null where id = p_attachment_id;
  end if;
end;
$$;
revoke all on function public.move_quote_file_to_work(uuid) from public, anon;
grant execute on function public.move_quote_file_to_work(uuid) to authenticated;
