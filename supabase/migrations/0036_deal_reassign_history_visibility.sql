-- Reassigning a deal (single or bulk) can optionally "hide" everything in
-- its timeline up to that point from the new assignee/team — a clean-slate
-- handoff — while keeping the full history visible to anyone with
-- crm_deals view_all (managers/admins always see everything, nothing is
-- ever actually deleted). null means nothing is hidden — the default, so
-- every existing deal behaves exactly as before.
alter table public.deals add column history_hidden_before timestamptz;

drop policy deal_activities_select on public.deal_activities;
create policy deal_activities_select on public.deal_activities
  for select
  using (
    exists (
      select 1 from public.deals d
      where d.id = deal_activities.deal_id
        and public.has_any_module_permission('crm_deals')
        and (
          public.has_permission('crm_deals', 'view_all')
          or (
            (
              d.assigned_to = auth.uid()
              or d.created_by = auth.uid()
              or public.leads_my_team(d.assigned_to)
              or public.leads_my_team(d.created_by)
            )
            and (d.history_hidden_before is null or deal_activities.created_at >= d.history_hidden_before)
          )
        )
    )
  );
