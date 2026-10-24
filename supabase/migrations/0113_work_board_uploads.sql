-- People who work a board can attach files to an item from the board. Those files
-- are marked with the work pipeline they came from, and show in the deal's Files tab
-- with a tag saying so.
alter table public.deal_attachments
  add column from_work_pipeline_id uuid references public.work_pipelines (id) on delete set null;

drop policy deal_attachments_insert on public.deal_attachments;
create policy deal_attachments_insert on public.deal_attachments
  for insert
  with check (
    exists (
      select 1 from public.deals d
      where d.id = deal_attachments.deal_id
        and public.has_permission('crm_deals', 'edit')
        and (
          public.has_permission('crm_deals', 'view_all')
          or d.assigned_to = auth.uid()
          or d.created_by = auth.uid()
          or public.leads_my_team(d.assigned_to)
          or public.leads_my_team(d.created_by)
        )
    )
    or (
      work_item_id is not null
      and from_work_pipeline_id is not null
      and public.has_permission('crm_work', 'edit')
      and public.can_see_work_item(work_item_id)
      and exists (
        select 1 from public.work_items w
        where w.id = deal_attachments.work_item_id
          and w.deal_id = deal_attachments.deal_id
          and w.work_pipeline_id = deal_attachments.from_work_pipeline_id
      )
    )
  );

-- The file itself goes to storage first: allowed to those who edit deals or work a board.
drop policy deal_attachments_storage_insert on storage.objects;
create policy deal_attachments_storage_insert on storage.objects
  for insert
  with check (
    bucket_id = 'deal-attachments'
    and (public.has_permission('crm_deals', 'edit') or public.has_permission('crm_work', 'edit'))
  );
