-- Technicians: users who carry out maintenance visits. A confirmed visit is
-- assigned to a technician (and can be reassigned); the assignment belongs to the
-- confirmed visit, so it goes away with the confirmation (rescheduling, finishing
-- or clearing the appointment). Anyone allowed to schedule maintenance can assign.
alter table public.profiles add column is_technician boolean not null default false;

-- is_technician is set by user managers (server routes) or an administrator, never
-- by the user themselves.
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
      or new.email is distinct from old.email)
     and not exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin and p.is_active) then
    raise exception 'insufficient permission to change this profile field';
  end if;

  return new;
end;
$$;

alter table public.customer_products
  add column maintenance_technician_id uuid references public.profiles (id) on delete set null,
  add column maintenance_assigned_at timestamptz;
create index customer_products_technician on public.customer_products (maintenance_technician_id) where maintenance_technician_id is not null;

-- The history records who a visit was assigned to, and who did a visit.
alter table public.product_maintenance_log
  add column technician_id uuid references public.profiles (id) on delete set null;

alter table public.product_maintenance_log drop constraint product_maintenance_log_kind_check;
alter table public.product_maintenance_log
  add constraint product_maintenance_log_kind_check
    check (kind in ('scheduled', 'rescheduled', 'done', 'cancelled', 'note', 'declined', 'resumed', 'confirmed', 'assigned'));

drop policy product_maintenance_log_insert on public.product_maintenance_log;
create policy product_maintenance_log_insert on public.product_maintenance_log
  for insert with check (
    case kind
      when 'scheduled' then public.has_permission('cs_maintenance', 'schedule')
      when 'rescheduled' then public.has_permission('cs_maintenance', 'schedule')
      when 'confirmed' then public.has_permission('cs_maintenance', 'schedule')
      when 'assigned' then public.has_permission('cs_maintenance', 'schedule')
      when 'done' then public.has_permission('cs_maintenance', 'complete')
      when 'declined' then public.has_permission('cs_maintenance', 'cancel')
      when 'resumed' then public.has_permission('cs_maintenance', 'cancel')
      when 'cancelled' then public.has_permission('cs_maintenance', 'cancel')
      when 'note' then public.has_permission('cs_maintenance', 'note')
      else false
    end
  );

create or replace function public.customer_product_guard_maintenance()
returns trigger
language plpgsql
as $$
declare
  v_skip text[] := array[
    'updated_at', 'next_maintenance_at', 'next_maintenance_note',
    'last_maintenance_on', 'maintenance_declined_at',
    'maintenance_confirmed_at', 'maintenance_confirmed_by', 'maintenance_confirm_note',
    'maintenance_technician_id', 'maintenance_assigned_at'
  ];
begin
  -- Server-side jobs and scripts (no signed-in user) are not limited.
  if auth.uid() is null then
    return new;
  end if;

  -- Anything other than the maintenance columns is a normal product edit.
  if (to_jsonb(new) - v_skip) is distinct from (to_jsonb(old) - v_skip)
     and not public.has_permission('cs_customers', 'edit') then
    raise exception 'insufficient permission to edit this product';
  end if;

  -- Each maintenance change needs its own action.
  if new.maintenance_declined_at is distinct from old.maintenance_declined_at then
    if not public.has_permission('cs_maintenance', 'cancel') then
      raise exception 'insufficient permission to cancel or resume maintenance';
    end if;
  elsif new.last_maintenance_on is distinct from old.last_maintenance_on then
    if not public.has_permission('cs_maintenance', 'complete') then
      raise exception 'insufficient permission to complete maintenance';
    end if;
  elsif new.next_maintenance_at is distinct from old.next_maintenance_at
     or new.next_maintenance_note is distinct from old.next_maintenance_note
     or new.maintenance_confirmed_at is distinct from old.maintenance_confirmed_at
     or new.maintenance_technician_id is distinct from old.maintenance_technician_id then
    if not public.has_permission('cs_maintenance', 'schedule') then
      raise exception 'insufficient permission to schedule maintenance';
    end if;
  end if;

  return new;
end;
$$;


-- The assignment goes with the confirmation (runs after the permission guard).
create or replace function public.customer_product_reset_confirmation()
returns trigger
language plpgsql
as $$
begin
  if new.next_maintenance_at is null then
    new.maintenance_confirmed_at := null;
    new.maintenance_confirmed_by := null;
    new.maintenance_confirm_note := null;
  elsif new.next_maintenance_at is distinct from old.next_maintenance_at
        and new.maintenance_confirmed_at is not distinct from old.maintenance_confirmed_at then
    new.maintenance_confirmed_at := null;
    new.maintenance_confirmed_by := null;
    new.maintenance_confirm_note := null;
  end if;
  if new.maintenance_confirmed_at is null then
    new.maintenance_technician_id := null;
    new.maintenance_assigned_at := null;
  end if;
  return new;
end;
$$;
