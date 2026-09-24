create table public.roles (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  created_at timestamptz not null default now()
);

-- module/action are free-text keys from the app's module registry
-- (app/utils/modules.ts), e.g. module='crm_leads', action='view_all'. Kept
-- as text rather than enums so new modules/actions never require a
-- migration to add.
create table public.role_permissions (
  id uuid primary key default gen_random_uuid(),
  role_id uuid not null references public.roles (id) on delete cascade,
  module text not null,
  action text not null,
  unique (role_id, module, action)
);

alter table public.profiles
  add constraint profiles_role_id_fkey
  foreign key (role_id) references public.roles (id) on delete set null;

alter table public.roles enable row level security;
alter table public.role_permissions enable row level security;

-- Role/permission management is an admin-only function, independent of the
-- module permission system itself (see plan: is_admin flag, not a module) —
-- otherwise granting "who can edit roles" would itself need a role to grant.
create policy roles_admin_all on public.roles
  for all
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

-- Every authenticated user needs to read their own role's permission rows
-- (to populate usePermissions() client-side), so SELECT is open; writes stay
-- admin-only.
create policy role_permissions_select on public.role_permissions
  for select
  using (true);

create policy role_permissions_admin_write on public.role_permissions
  for insert
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

create policy role_permissions_admin_update on public.role_permissions
  for update
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

create policy role_permissions_admin_delete on public.role_permissions
  for delete
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));
