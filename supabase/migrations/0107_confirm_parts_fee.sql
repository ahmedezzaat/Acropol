-- Confirming a visit also settles what it will cost: the spare parts expected to be
-- used (quantity and the price as set) and the visit fee. They are kept on the
-- confirmed visit, offered again — and changeable — when the visit is marked done,
-- and go away with the confirmation, like the technician.
alter table public.customer_products
  add column maintenance_confirm_parts jsonb,
  add column maintenance_confirm_fee numeric check (maintenance_confirm_fee is null or maintenance_confirm_fee >= 0);

create or replace function public.customer_product_guard_maintenance()
returns trigger
language plpgsql
as $$
declare
  v_skip text[] := array[
    'updated_at', 'next_maintenance_at', 'next_maintenance_note',
    'last_maintenance_on', 'maintenance_declined_at',
    'maintenance_confirmed_at', 'maintenance_confirmed_by', 'maintenance_confirm_note',
    'maintenance_technician_id', 'maintenance_assigned_at',
    'maintenance_confirm_parts', 'maintenance_confirm_fee'
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
     or new.maintenance_technician_id is distinct from old.maintenance_technician_id
     or new.maintenance_confirm_parts is distinct from old.maintenance_confirm_parts
     or new.maintenance_confirm_fee is distinct from old.maintenance_confirm_fee then
    if not public.has_permission('cs_maintenance', 'schedule') then
      raise exception 'insufficient permission to schedule maintenance';
    end if;
  end if;

  return new;
end;
$$;

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
    new.maintenance_confirm_parts := null;
    new.maintenance_confirm_fee := null;
  end if;
  return new;
end;
$$;
