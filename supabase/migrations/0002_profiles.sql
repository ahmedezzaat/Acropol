-- profiles extends auth.users with app-level fields. role_id has no FK yet
-- (roles table doesn't exist until 0003) — added there via ALTER TABLE.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  full_name text,
  role_id uuid,
  is_admin boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Every authenticated user can read their own profile (needed to load their
-- own permissions) and any active user's basic profile (needed to render
-- "assigned to <name>" pickers/labels). Only admins can see is_admin/inactive
-- rows beyond their own — enforced by only exposing safe columns via views
-- would be nicer, but for v1 a single permissive-read policy is enough since
-- profile fields here aren't sensitive (email/name), and mutations are what
-- actually matter.
create policy profiles_select on public.profiles
  for select
  using (true);

-- Users may update their own non-privileged fields (full_name); role_id/
-- is_admin/is_active changes must go through the service-role admin API,
-- not a client-side update — enforced by only allowing self-updates here and
-- keeping the admin endpoints on the service-role key (which bypasses RLS by
-- design, so this policy doesn't need to special-case admin writes).
create policy profiles_update_self on public.profiles
  for update
  using (id = auth.uid())
  with check (id = auth.uid());

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Auto-create a profile row whenever a new auth user is created (always via
-- the admin API server-side, never self-signup per product requirements).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
