-- Files uploaded from the technical office (deal_attachments with from_work_pipeline_id)
-- get their own permissions: view, create (add), edit (rename) and delete, on the
-- "crm_work_files" resource. Roles that already work the boards keep what they had:
-- anyone with a board permission can view them, anyone who could edit board items can
-- add, rename and delete them.
insert into public.role_permissions (role_id, module, action)
select distinct rp.role_id, 'crm_work_files', 'view'
from public.role_permissions rp where rp.module = 'crm_work'
on conflict do nothing;

insert into public.role_permissions (role_id, module, action)
select distinct rp.role_id, 'crm_work_files', a.action
from public.role_permissions rp
cross join (values ('create'), ('edit'), ('delete')) as a(action)
where rp.module = 'crm_work' and rp.action = 'edit'
on conflict do nothing;

-- Renaming a technical office file.
create policy deal_attachments_update_work_files on public.deal_attachments
  for update
  using (from_work_pipeline_id is not null and public.has_permission('crm_work_files', 'edit'))
  with check (from_work_pipeline_id is not null and public.has_permission('crm_work_files', 'edit'));
