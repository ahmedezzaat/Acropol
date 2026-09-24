-- Single source of truth for "can this user do <action> on <module>",
-- called from every RLS policy below. security definer so it can read
-- profiles/role_permissions regardless of the calling user's own row-level
-- visibility into those tables; search_path is pinned to guard against
-- search-path hijacking on a security definer function.
create or replace function public.has_permission(p_module text, p_action text)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles pr
    join public.role_permissions rp on rp.role_id = pr.role_id
    where pr.id = auth.uid()
      and pr.is_active
      and rp.module = p_module
      and rp.action = p_action
  ) or exists (
    select 1 from public.profiles pr
    where pr.id = auth.uid() and pr.is_admin and pr.is_active
  );
$$;

-- "Has any permission on this module" — used for plain view/list access,
-- since view itself is implicit from holding any action on the module.
create or replace function public.has_any_module_permission(p_module text)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles pr
    join public.role_permissions rp on rp.role_id = pr.role_id
    where pr.id = auth.uid()
      and pr.is_active
      and rp.module = p_module
  ) or exists (
    select 1 from public.profiles pr
    where pr.id = auth.uid() and pr.is_admin and pr.is_active
  );
$$;
