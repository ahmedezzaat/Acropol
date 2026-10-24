-- A phone number on a user, so people (technicians) can sign in with phone + password.
-- Set by an administrator or user manager through the admin routes; stored as canonical
-- international digits so the same number always matches.
alter table public.profiles add column phone text;
create unique index profiles_phone_unique on public.profiles (phone) where phone is not null;

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
      or new.is_technician is distinct from old.is_technician
      or new.phone is distinct from old.phone
      or new.email is distinct from old.email)
     and not exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin and p.is_active) then
    raise exception 'insufficient permission to change this profile field';
  end if;

  return new;
end;
$$;
