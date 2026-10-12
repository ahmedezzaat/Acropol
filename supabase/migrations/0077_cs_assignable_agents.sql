-- Who a Customer Service customer can be assigned to: active users who work in
-- the module, i.e. whose role holds at least one Customer Service permission
-- (customers or maintenance), plus administrators, who can do all of it.
-- Only people allowed to assign customers can ask.
create or replace function public.cs_assignable_agents()
returns table (id uuid, full_name text, email text)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.has_permission('cs_customers', 'assign') then
    raise exception 'insufficient permission to assign customers';
  end if;

  return query
  select p.id, p.full_name, p.email
  from public.profiles p
  where p.is_active
    and (
      p.is_admin
      or exists (
        select 1 from public.role_permissions rp
        where rp.role_id = p.role_id and rp.module in ('cs_customers', 'cs_maintenance')
      )
    )
  order by coalesce(nullif(p.full_name, ''), p.email);
end;
$$;
