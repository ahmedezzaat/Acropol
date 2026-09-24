create type public.lead_status as enum ('new', 'contacted', 'qualified', 'converted', 'lost');

create table public.leads (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  email text,
  source text,
  status public.lead_status not null default 'new',
  notes text,
  assigned_to uuid references public.profiles (id),
  created_by uuid not null references public.profiles (id),
  customer_id uuid references public.customers (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.customers
  add constraint customers_converted_from_lead_fkey
  foreign key (converted_from_lead_id) references public.leads (id);

create trigger leads_set_updated_at
  before update on public.leads
  for each row execute function public.set_updated_at();

alter table public.leads enable row level security;

-- Row-level scoping: without view_all, a user only sees leads assigned to
-- or created by them, per product requirement.
create policy leads_select on public.leads
  for select
  using (
    public.has_any_module_permission('crm_leads')
    and (
      public.has_permission('crm_leads', 'view_all')
      or assigned_to = auth.uid()
      or created_by = auth.uid()
    )
  );

create policy leads_insert on public.leads
  for insert
  with check (public.has_permission('crm_leads', 'create'));

create policy leads_update on public.leads
  for update
  using (
    public.has_permission('crm_leads', 'edit')
    and (
      public.has_permission('crm_leads', 'view_all')
      or assigned_to = auth.uid()
      or created_by = auth.uid()
    )
  );

create policy leads_delete on public.leads
  for delete
  using (public.has_permission('crm_leads', 'delete'));

-- RLS is row-level only; it can't restrict which columns an otherwise-
-- permitted UPDATE touches. Reassignment is gated separately here so the
-- 'assign' permission is enforced no matter how the update reaches the
-- table.
create or replace function public.enforce_lead_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.assigned_to is distinct from old.assigned_to
     and not public.has_permission('crm_leads', 'assign') then
    raise exception 'insufficient permission to reassign lead';
  end if;
  return new;
end;
$$;

create trigger leads_enforce_assignment
  before update on public.leads
  for each row execute function public.enforce_lead_assignment();
