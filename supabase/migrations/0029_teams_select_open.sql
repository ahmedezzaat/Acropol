-- teams_admin_all gated SELECT on is_admin too, so a non-admin (even a
-- team leader) couldn't resolve team names — e.g. for a "deals per team"
-- breakdown. Team names aren't sensitive, only membership/leadership
-- changes are; split into an open-read + admin-write pair, same pattern
-- already used for role_permissions.
drop policy teams_admin_all on public.teams;

create policy teams_select on public.teams
  for select
  using (true);

create policy teams_admin_write on public.teams
  for insert
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

create policy teams_admin_update on public.teams
  for update
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

create policy teams_admin_delete on public.teams
  for delete
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));
