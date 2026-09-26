-- Extends the "view_all" row-scoping pattern already used for leads to
-- deals and customers, and adds an assign permission + assigned_to column
-- to customers (mirroring leads/deals). Without view_all on a module, a
-- user only ever sees rows assigned to or created by them — never another
-- user's leads, deals, or customers, including unassigned ones.

alter table public.customers add column assigned_to uuid references public.profiles (id);

drop policy deals_select on public.deals;
create policy deals_select on public.deals
  for select
  using (
    public.has_any_module_permission('crm_deals')
    and (
      public.has_permission('crm_deals', 'view_all')
      or assigned_to = auth.uid()
      or created_by = auth.uid()
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
    )
  );

-- deal_activities previously only checked module-level permission, which
-- would have leaked another user's deal timeline once deals themselves
-- became row-scoped above — tie visibility/editability to the parent
-- deal's own row-scoping instead.
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
        )
    )
  );

-- Customer assignment, enforced the same way leads/deals already are.
-- Also honors the cascading_assignment escape hatch below, so the deal ->
-- customer cascade can write through it without the acting user needing
-- crm_customers:assign themselves.
create or replace function public.enforce_customer_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_setting('acropol.cascading_assignment', true) = 'true' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.assigned_to is not null
       and new.assigned_to is distinct from auth.uid()
       and not public.has_permission('crm_customers', 'assign') then
      raise exception 'insufficient permission to assign this customer';
    end if;
    return new;
  end if;

  if new.assigned_to is distinct from old.assigned_to
     and not public.has_permission('crm_customers', 'assign') then
    raise exception 'insufficient permission to reassign customer';
  end if;
  return new;
end;
$$;

create trigger customers_enforce_assignment
  before insert or update on public.customers
  for each row execute function public.enforce_customer_assignment();

-- Same escape hatch added to the existing lead-assignment trigger.
create or replace function public.enforce_lead_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_setting('acropol.cascading_assignment', true) = 'true' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.assigned_to is not null
       and new.assigned_to is distinct from auth.uid()
       and not public.has_permission('crm_leads', 'assign') then
      raise exception 'insufficient permission to assign this lead';
    end if;
    return new;
  end if;

  if new.assigned_to is distinct from old.assigned_to
     and not public.has_permission('crm_leads', 'assign') then
    raise exception 'insufficient permission to reassign lead';
  end if;
  return new;
end;
$$;

-- Whoever a deal is assigned to owns the whole relationship — assigning a
-- deal cascades that same assignment onto its lead and customer, so they
-- never drift apart. Runs as a transaction-local flag (not a permission
-- bypass) so the leads/customers assignment triggers above let it through
-- regardless of whether the acting user personally holds crm_leads:assign
-- or crm_customers:assign — the permission that was actually checked is
-- crm_deals:assign, on the deal itself.
create or replace function public.cascade_deal_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and new.assigned_to is not distinct from old.assigned_to then
    return new;
  end if;

  perform set_config('acropol.cascading_assignment', 'true', true);

  if new.lead_id is not null then
    update public.leads set assigned_to = new.assigned_to where id = new.lead_id;
  end if;

  update public.customers set assigned_to = new.assigned_to where id = new.customer_id;

  perform set_config('acropol.cascading_assignment', 'false', true);

  return new;
end;
$$;

create trigger deals_cascade_assignment
  after insert or update on public.deals
  for each row execute function public.cascade_deal_assignment();
