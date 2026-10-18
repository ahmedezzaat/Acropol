-- A scheduled maintenance visit is not confirmed until someone calls the
-- customer and agrees the visit; only a confirmed visit can be marked done
-- (the app enforces that on its Mark as done buttons). Confirming is part of
-- scheduling, so anyone allowed to schedule maintenance can confirm.
--
-- The confirmation belongs to the appointment: rescheduling it, or finishing or
-- clearing it, removes the confirmation (the new time has to be confirmed again),
-- unless the same update confirms it.
alter table public.customer_products
  add column maintenance_confirmed_at timestamptz,
  add column maintenance_confirmed_by uuid references public.profiles (id) on delete set null,
  add column maintenance_confirm_note text;

alter table public.product_maintenance_log drop constraint product_maintenance_log_kind_check;
alter table public.product_maintenance_log
  add constraint product_maintenance_log_kind_check
    check (kind in ('scheduled', 'rescheduled', 'done', 'cancelled', 'note', 'declined', 'resumed', 'confirmed'));

drop policy product_maintenance_log_insert on public.product_maintenance_log;
create policy product_maintenance_log_insert on public.product_maintenance_log
  for insert with check (
    case kind
      when 'scheduled' then public.has_permission('cs_maintenance', 'schedule')
      when 'rescheduled' then public.has_permission('cs_maintenance', 'schedule')
      when 'confirmed' then public.has_permission('cs_maintenance', 'schedule')
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
    'maintenance_confirmed_at', 'maintenance_confirmed_by', 'maintenance_confirm_note'
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
     or new.maintenance_confirmed_at is distinct from old.maintenance_confirmed_at then
    if not public.has_permission('cs_maintenance', 'schedule') then
      raise exception 'insufficient permission to schedule maintenance';
    end if;
  end if;

  return new;
end;
$$;


-- Runs after the permission guard (triggers fire in name order).
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
  return new;
end;
$$;

drop trigger if exists customer_products_zz_reset_confirmation on public.customer_products;
create trigger customer_products_zz_reset_confirmation
  before update on public.customer_products
  for each row execute function public.customer_product_reset_confirmation();
