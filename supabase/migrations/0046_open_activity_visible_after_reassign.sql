-- "Hide history" on reassignment hides everything before the handoff from
-- anyone without "view all". But a deal may hold ONE open scheduled activity
-- (unique index deal_activities_one_open_per_deal), and that activity is not
-- history — it is the deal's current to-do. Hiding it left the new assignee
-- unable to see it, while the database still refused to let them schedule
-- another ("duplicate key ... deal_activities_one_open_per_deal"), and the
-- overdue reminders still reached them for an activity they couldn't open.
-- An open scheduled activity therefore stays visible after a reassignment.
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
            and (
              d.history_hidden_before is null
              or deal_activities.created_at >= d.history_hidden_before
              -- the open follow-up is current state, not history
              or (
                deal_activities.completed_at is null
                and deal_activities.scheduled_at is not null
                and deal_activities.type <> 'note'
              )
            )
          )
        )
    )
  );
