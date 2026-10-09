-- A user who exists only as a record (for migrated data: an owner, a sales
-- person, an assignee) and never signs in. They stay active, so they appear in
-- every user list, but their auth account is banned and has no usable password.
alter table public.profiles
  add column can_login boolean not null default true;
