-- Sending a deal to a sub-workflow (e.g. the technical office) can attach files the deal
-- already has, instead of uploading them again. The file stays one file on the deal; it
-- is just tied to the request so the board shows it. Only the person who sent the request
-- (or someone who works the board) can do this, only for files of the same deal, and a
-- file already tied to a request is left alone.
create or replace function public.link_deal_files_to_work_item(p_work_item_id uuid, p_attachment_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.work_items;
  v_count integer;
begin
  select * into v_item from public.work_items where id = p_work_item_id;
  if v_item.id is null then
    raise exception 'request not found';
  end if;
  if not (
    public.has_permission('crm_work', 'edit')
    or (v_item.created_by = auth.uid() and public.has_permission('crm_deals', 'edit'))
  ) then
    raise exception 'insufficient permission to attach files to this request';
  end if;

  update public.deal_attachments
  set work_item_id = v_item.id
  where id = any (p_attachment_ids)
    and deal_id = v_item.deal_id
    and work_item_id is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function public.link_deal_files_to_work_item(uuid, uuid[]) from public, anon;
grant execute on function public.link_deal_files_to_work_item(uuid, uuid[]) to authenticated;
