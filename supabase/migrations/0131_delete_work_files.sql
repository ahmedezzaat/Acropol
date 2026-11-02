-- Deleting a file uploaded from the technical office is its own permission ("delete" on
-- crm_work_files). The people who hold it work the board and may not be allowed to edit
-- deals, which the old delete rules required, so they could never delete these files.
create policy deal_attachments_delete_work_files on public.deal_attachments
  for delete
  using (from_work_pipeline_id is not null and public.has_permission('crm_work_files', 'delete'));

-- The file itself, in the private storage.
create policy deal_attachments_storage_delete_work on storage.objects
  for delete
  using (
    bucket_id = 'deal-attachments'
    and public.has_permission('crm_work_files', 'delete')
    and exists (
      select 1 from public.deal_attachments da
      where da.storage_path = storage.objects.name and da.from_work_pipeline_id is not null
    )
  );
