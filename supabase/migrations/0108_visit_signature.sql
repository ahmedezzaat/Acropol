-- The customer signs on the technician's phone when a visit is marked done. The
-- signature is a PNG kept in a private bucket; the visit's log entry points to it.
alter table public.product_maintenance_log
  add column signature_path text;

insert into storage.buckets (id, name, public)
values ('visit-signatures', 'visit-signatures', false)
on conflict (id) do nothing;

create policy visit_signatures_insert on storage.objects
  for insert
  with check (
    bucket_id = 'visit-signatures'
    and public.has_permission('cs_maintenance', 'complete')
  );

create policy visit_signatures_select on storage.objects
  for select
  using (
    bucket_id = 'visit-signatures'
    and (public.has_any_module_permission('cs_maintenance') or public.has_any_module_permission('cs_customers'))
  );
