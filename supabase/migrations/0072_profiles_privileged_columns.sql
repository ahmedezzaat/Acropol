-- Closes a gap: the "update own profile" policy let any signed-in user change
-- ANY column of their own row from the browser, including is_admin and role_id,
-- i.e. make themselves an administrator. Those columns can only be changed by
-- an administrator, or by the server-side admin routes (which run without a
-- signed-in database user).
create or replace function public.profiles_guard_privileged_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return new;
  end if;

  if (new.is_admin is distinct from old.is_admin
      or new.role_id is distinct from old.role_id
      or new.is_active is distinct from old.is_active
      or new.can_login is distinct from old.can_login
      or new.email is distinct from old.email)
     and not exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin and p.is_active) then
    raise exception 'insufficient permission to change this profile field';
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_guard_privileged_columns on public.profiles;
create trigger profiles_guard_privileged_columns
  before update on public.profiles
  for each row execute function public.profiles_guard_privileged_columns();
