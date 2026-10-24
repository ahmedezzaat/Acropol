-- Files attached when a deal is sent to a board, and a deadline with a time (24 hours,
-- 2 days, ...). The files belong to the deal (they show in its Files tab) and also
-- point at the work item, so the people who see that board can open them.
alter table public.work_items
  alter column deadline type timestamptz using deadline::timestamptz;

alter table public.deal_attachments
  add column work_item_id uuid references public.work_items (id) on delete set null;
create index deal_attachments_work_item on public.deal_attachments (work_item_id) where work_item_id is not null;

-- Can the signed-in user see the board of this work item?
create or replace function public.can_see_work_item(p_work_item_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.work_items w
    where w.id = p_work_item_id
      and (public.has_permission('crm_work', 'view') or public.has_permission('crm_work', w.work_pipeline_id::text))
  );
$$;

drop policy deal_attachments_select on public.deal_attachments;
create policy deal_attachments_select on public.deal_attachments
  for select
  using (
    exists (
      select 1 from public.deals d
      where d.id = deal_attachments.deal_id
        and public.has_any_module_permission('crm_deals')
        and (
          public.has_permission('crm_deals', 'view_all')
          or d.assigned_to = auth.uid()
          or d.created_by = auth.uid()
          or public.leads_my_team(d.assigned_to)
          or public.leads_my_team(d.created_by)
        )
    )
    or (work_item_id is not null and public.can_see_work_item(work_item_id))
  );

drop policy deal_attachments_storage_select on storage.objects;
create policy deal_attachments_storage_select on storage.objects
  for select
  using (
    bucket_id = 'deal-attachments'
    and exists (
      select 1 from public.deal_attachments da
      join public.deals d on d.id = da.deal_id
      where da.storage_path = storage.objects.name
        and (
          (
            public.has_any_module_permission('crm_deals')
            and (
              public.has_permission('crm_deals', 'view_all')
              or d.assigned_to = auth.uid()
              or d.created_by = auth.uid()
              or public.leads_my_team(d.assigned_to)
              or public.leads_my_team(d.created_by)
            )
          )
          or (da.work_item_id is not null and public.can_see_work_item(da.work_item_id))
        )
    )
  );
