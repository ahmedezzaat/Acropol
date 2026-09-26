-- profiles only had a self-update policy (id = auth.uid()), so the new
-- Teams admin page silently failed to write other users' team_id — the
-- UPDATE statement succeeded but matched zero visible rows under RLS.
-- Admin write access to arbitrary users' profiles was previously avoided by
-- routing role_id/is_admin/is_active changes through a service-role server
-- endpoint instead; adding this policy is simpler for team_id specifically
-- (enforce_team_id_admin_only already gates team_id changes to admins at
-- the trigger level, so this just lets that trigger's caller reach the row
-- at all) and is additive — it doesn't change how the existing admin/users
-- pages work.
create policy profiles_update_admin on public.profiles
  for update
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));
