-- "Hide history" on reassignment hides a deal's older timeline from the new
-- assignee (anyone without crm_deals view all). A note written by someone who
-- HAS view all (a manager or admin) is guidance for whoever works the deal, so
-- it always stays visible to the people who can see the deal.

-- Same rule as has_permission(), but for a given user instead of the caller.
create or replace function public.user_has_permission(p_user uuid, p_module text, p_action text)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select p_user is not null and (
    exists (
      select 1
      from public.profiles pr
      join public.role_permissions rp on rp.role_id = pr.role_id
      where pr.id = p_user and pr.is_active and rp.module = p_module and rp.action = p_action
    )
    or exists (select 1 from public.profiles pr where pr.id = p_user and pr.is_admin and pr.is_active)
  );
$$;

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
              -- a note from someone with view all stays visible
              or (
                deal_activities.type = 'note'
                and public.user_has_permission(deal_activities.created_by, 'crm_deals', 'view_all')
              )
            )
          )
        )
    )
  );
