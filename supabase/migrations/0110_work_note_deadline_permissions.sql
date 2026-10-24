-- Sending a deal to a work board now says what is wanted (a note) and by when (a
-- deadline). Seeing a board is a permission per board (the action is the work
-- pipeline's id), or "view" for all of them.
alter table public.work_items
  add column request_note text,
  add column deadline date;

drop policy work_items_select on public.work_items;
create policy work_items_select on public.work_items
  for select using (
    public.has_permission('crm_work', 'view')
    or public.has_permission('crm_work', work_pipeline_id::text)
    or public.has_any_module_permission('crm_deals')
  );
