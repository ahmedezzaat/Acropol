-- Deal activity types (Call, Meeting, Site visit, ...) become admin-managed
-- data instead of a fixed set, so more can be added from CRM settings
-- without a migration — same reasoning as pipelines/stages. 'note' stays a
-- built-in, not part of this table (always available, not a schedulable
-- action type).
create table public.activity_types (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  name text not null,
  icon text not null default 'i-lucide-circle',
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

alter table public.activity_types enable row level security;

create policy activity_types_select on public.activity_types
  for select
  using (public.has_any_module_permission('crm_deals'));

create policy activity_types_admin_all on public.activity_types
  for all
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

insert into public.activity_types (key, name, icon, sort_order) values
  ('call', 'Call', 'i-lucide-phone', 1),
  ('meeting', 'Meeting', 'i-lucide-users', 2),
  ('site_visit', 'Site visit', 'i-lucide-map-pin', 3);

-- deal_activities.type was a rigid CHECK list — replace it with a trigger
-- so newly admin-added activity_types stay valid without a schema change
-- each time, while system event types (stage_changed/assigned/created) and
-- the built-in 'note' remain fixed.
alter table public.deal_activities drop constraint deal_activities_type_check;

create or replace function public.enforce_deal_activity_type()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.type in ('note', 'stage_changed', 'assigned', 'created') then
    return new;
  end if;
  if not exists (select 1 from public.activity_types where key = new.type) then
    raise exception 'invalid activity type: %', new.type;
  end if;
  return new;
end;
$$;

create trigger deal_activities_enforce_type
  before insert or update on public.deal_activities
  for each row execute function public.enforce_deal_activity_type();
