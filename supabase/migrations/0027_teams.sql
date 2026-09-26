-- Teams: a team leader sees everything their team members can see, on top
-- of whatever their own role permissions already grant (additive, never a
-- restriction) — so a leader who only has "see my own" now also sees their
-- team's leads/deals/customers/quotes/activities, while a leader who
-- already has view_all is unaffected (they already saw everything). Each
-- team has exactly one leader; a profile has at most one team_id, so a
-- member can never belong to two teams at once by construction.

create table public.teams (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  leader_id uuid not null unique references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger teams_set_updated_at
  before update on public.teams
  for each row execute function public.set_updated_at();

alter table public.teams enable row level security;

-- Teams are an admin-managed resource, same tier as roles/pipelines — not
-- part of the module/permission system itself.
create policy teams_admin_all on public.teams
  for all
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

alter table public.profiles add column team_id uuid references public.teams (id) on delete set null;

-- team_id is an admin-controlled assignment, same category as role_id/
-- is_admin/is_active — a plain self-update (profiles_update_self already
-- allows updating your own row) must not be able to move yourself into a
-- team, since team membership grants that team's leader extra visibility
-- into your data.
create or replace function public.enforce_team_id_admin_only()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.team_id is distinct from old.team_id
     and not exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin) then
    raise exception 'insufficient permission to change team assignment';
  end if;
  return new;
end;
$$;

create trigger profiles_enforce_team_id
  before update on public.profiles
  for each row execute function public.enforce_team_id_admin_only();

-- True when auth.uid() leads the team that p_profile_id belongs to.
-- security definer + stable so it's cheap to use inside RLS policies
-- across tables that don't otherwise expose team membership to the caller.
create or replace function public.leads_my_team(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    join public.teams t on t.id = p.team_id
    where p.id = p_profile_id and t.leader_id = auth.uid()
  );
$$;

drop policy leads_select on public.leads;
create policy leads_select on public.leads
  for select
  using (
    public.has_any_module_permission('crm_leads')
    and (
      public.has_permission('crm_leads', 'view_all')
      or assigned_to = auth.uid()
      or created_by = auth.uid()
      or public.leads_my_team(assigned_to)
      or public.leads_my_team(created_by)
    )
  );

drop policy deals_select on public.deals;
create policy deals_select on public.deals
  for select
  using (
    public.has_any_module_permission('crm_deals')
    and (
      public.has_permission('crm_deals', 'view_all')
      or assigned_to = auth.uid()
      or created_by = auth.uid()
      or public.leads_my_team(assigned_to)
      or public.leads_my_team(created_by)
    )
  );

drop policy customers_select on public.customers;
create policy customers_select on public.customers
  for select
  using (
    public.has_any_module_permission('crm_customers')
    and (
      public.has_permission('crm_customers', 'view_all')
      or assigned_to = auth.uid()
      or created_by = auth.uid()
      or public.leads_my_team(assigned_to)
      or public.leads_my_team(created_by)
    )
  );

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
          or d.assigned_to = auth.uid()
          or d.created_by = auth.uid()
          or public.leads_my_team(d.assigned_to)
          or public.leads_my_team(d.created_by)
        )
    )
  );

drop policy deal_activities_insert on public.deal_activities;
create policy deal_activities_insert on public.deal_activities
  for insert
  with check (
    exists (
      select 1 from public.deals d
      where d.id = deal_activities.deal_id
        and public.has_permission('crm_deals', 'edit')
        and (
          public.has_permission('crm_deals', 'view_all')
          or d.assigned_to = auth.uid()
          or d.created_by = auth.uid()
          or public.leads_my_team(d.assigned_to)
          or public.leads_my_team(d.created_by)
        )
    )
  );

drop policy deal_activities_update on public.deal_activities;
create policy deal_activities_update on public.deal_activities
  for update
  using (
    exists (
      select 1 from public.deals d
      where d.id = deal_activities.deal_id
        and public.has_permission('crm_deals', 'edit')
        and (
          public.has_permission('crm_deals', 'view_all')
          or d.assigned_to = auth.uid()
          or d.created_by = auth.uid()
          or public.leads_my_team(d.assigned_to)
          or public.leads_my_team(d.created_by)
        )
    )
  );

drop policy deal_activities_delete on public.deal_activities;
create policy deal_activities_delete on public.deal_activities
  for delete
  using (
    exists (
      select 1 from public.deals d
      where d.id = deal_activities.deal_id
        and public.has_permission('crm_deals', 'edit')
        and (
          public.has_permission('crm_deals', 'view_all')
          or d.assigned_to = auth.uid()
          or d.created_by = auth.uid()
          or public.leads_my_team(d.assigned_to)
          or public.leads_my_team(d.created_by)
        )
    )
  );

drop policy quotes_select on public.quotes;
create policy quotes_select on public.quotes
  for select
  using (
    exists (
      select 1 from public.deals d
      where d.id = quotes.deal_id
        and public.has_any_module_permission('crm_quotes')
        and (
          public.has_permission('crm_deals', 'view_all')
          or d.assigned_to = auth.uid()
          or d.created_by = auth.uid()
          or public.leads_my_team(d.assigned_to)
          or public.leads_my_team(d.created_by)
        )
    )
  );

drop policy quotes_insert on public.quotes;
create policy quotes_insert on public.quotes
  for insert
  with check (
    exists (
      select 1 from public.deals d
      where d.id = quotes.deal_id
        and public.has_permission('crm_quotes', 'create')
        and (
          public.has_permission('crm_deals', 'view_all')
          or d.assigned_to = auth.uid()
          or d.created_by = auth.uid()
          or public.leads_my_team(d.assigned_to)
          or public.leads_my_team(d.created_by)
        )
    )
  );

drop policy quotes_update on public.quotes;
create policy quotes_update on public.quotes
  for update
  using (
    exists (
      select 1 from public.deals d
      where d.id = quotes.deal_id
        and public.has_permission('crm_quotes', 'edit')
        and (
          public.has_permission('crm_deals', 'view_all')
          or d.assigned_to = auth.uid()
          or d.created_by = auth.uid()
          or public.leads_my_team(d.assigned_to)
          or public.leads_my_team(d.created_by)
        )
    )
  );

drop policy quotes_delete on public.quotes;
create policy quotes_delete on public.quotes
  for delete
  using (
    exists (
      select 1 from public.deals d
      where d.id = quotes.deal_id
        and public.has_permission('crm_quotes', 'delete')
        and (
          public.has_permission('crm_deals', 'view_all')
          or d.assigned_to = auth.uid()
          or d.created_by = auth.uid()
          or public.leads_my_team(d.assigned_to)
          or public.leads_my_team(d.created_by)
        )
    )
  );

drop policy quote_items_select on public.quote_items;
create policy quote_items_select on public.quote_items
  for select
  using (
    exists (
      select 1 from public.quotes q
      join public.deals d on d.id = q.deal_id
      where q.id = quote_items.quote_id
        and public.has_any_module_permission('crm_quotes')
        and (
          public.has_permission('crm_deals', 'view_all')
          or d.assigned_to = auth.uid()
          or d.created_by = auth.uid()
          or public.leads_my_team(d.assigned_to)
          or public.leads_my_team(d.created_by)
        )
    )
  );

drop policy quote_items_insert on public.quote_items;
create policy quote_items_insert on public.quote_items
  for insert
  with check (
    exists (
      select 1 from public.quotes q
      join public.deals d on d.id = q.deal_id
      where q.id = quote_items.quote_id
        and public.has_permission('crm_quotes', 'edit')
        and (
          public.has_permission('crm_deals', 'view_all')
          or d.assigned_to = auth.uid()
          or d.created_by = auth.uid()
          or public.leads_my_team(d.assigned_to)
          or public.leads_my_team(d.created_by)
        )
    )
  );

drop policy quote_items_update on public.quote_items;
create policy quote_items_update on public.quote_items
  for update
  using (
    exists (
      select 1 from public.quotes q
      join public.deals d on d.id = q.deal_id
      where q.id = quote_items.quote_id
        and public.has_permission('crm_quotes', 'edit')
        and (
          public.has_permission('crm_deals', 'view_all')
          or d.assigned_to = auth.uid()
          or d.created_by = auth.uid()
          or public.leads_my_team(d.assigned_to)
          or public.leads_my_team(d.created_by)
        )
    )
  );

drop policy quote_items_delete on public.quote_items;
create policy quote_items_delete on public.quote_items
  for delete
  using (
    exists (
      select 1 from public.quotes q
      join public.deals d on d.id = q.deal_id
      where q.id = quote_items.quote_id
        and public.has_permission('crm_quotes', 'edit')
        and (
          public.has_permission('crm_deals', 'view_all')
          or d.assigned_to = auth.uid()
          or d.created_by = auth.uid()
          or public.leads_my_team(d.assigned_to)
          or public.leads_my_team(d.created_by)
        )
    )
  );
