-- Spare parts price lists. Until now every part had one price (the one for individual
-- customers). That list stays, as the default, and more lists can be added with their own
-- prices; a part with no price in a list uses its default price. When a visit is confirmed
-- the right list is chosen, and people with the "override prices" permission can change
-- the prices on that order before it is created.

create table public.spare_part_price_lists (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  sort_order integer not null default 0,
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);
-- exactly one default list: the individual customers' prices (the parts' own price)
create unique index spare_part_price_lists_one_default on public.spare_part_price_lists (is_default) where is_default;
insert into public.spare_part_price_lists (name, sort_order, is_default) values ('العملاء الأفراد', 0, true);

alter table public.spare_part_price_lists enable row level security;
create policy spare_part_price_lists_select on public.spare_part_price_lists
  for select using (public.has_any_module_permission('cs_spare_parts') or public.has_any_module_permission('cs_maintenance'));
create policy spare_part_price_lists_insert on public.spare_part_price_lists
  for insert with check (public.has_permission('cs_spare_parts', 'create') and not is_default);
create policy spare_part_price_lists_update on public.spare_part_price_lists
  for update using (public.has_permission('cs_spare_parts', 'edit'))
  with check (public.has_permission('cs_spare_parts', 'edit'));
create policy spare_part_price_lists_delete on public.spare_part_price_lists
  for delete using (public.has_permission('cs_spare_parts', 'delete') and not is_default);

-- A part's price in a list other than the default one.
create table public.spare_part_prices (
  price_list_id uuid not null references public.spare_part_price_lists (id) on delete cascade,
  spare_part_id uuid not null references public.spare_parts (id) on delete cascade,
  price numeric not null check (price >= 0),
  primary key (price_list_id, spare_part_id)
);
alter table public.spare_part_prices enable row level security;
create policy spare_part_prices_select on public.spare_part_prices
  for select using (public.has_any_module_permission('cs_spare_parts') or public.has_any_module_permission('cs_maintenance'));
create policy spare_part_prices_insert on public.spare_part_prices
  for insert with check (public.has_permission('cs_spare_parts', 'edit'));
create policy spare_part_prices_update on public.spare_part_prices
  for update using (public.has_permission('cs_spare_parts', 'edit'))
  with check (public.has_permission('cs_spare_parts', 'edit'));
create policy spare_part_prices_delete on public.spare_part_prices
  for delete using (public.has_permission('cs_spare_parts', 'edit'));

-- The list chosen when the visit was confirmed (kept with the confirmed parts and fee, and
-- cleared with them).
alter table public.customer_products
  add column maintenance_confirm_price_list_id uuid references public.spare_part_price_lists (id) on delete set null;

CREATE OR REPLACE FUNCTION public.customer_product_guard_maintenance()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare
  v_skip text[] := array[
    'updated_at', 'next_maintenance_at', 'next_maintenance_note',
    'last_maintenance_on', 'maintenance_declined_at',
    'maintenance_confirmed_at', 'maintenance_confirmed_by', 'maintenance_confirm_note',
    'maintenance_technician_id', 'maintenance_assigned_at',
    'maintenance_confirm_parts', 'maintenance_confirm_fee', 'maintenance_confirm_price_list_id'
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
     or new.maintenance_confirm_fee is distinct from old.maintenance_confirm_fee
     or new.maintenance_confirm_price_list_id is distinct from old.maintenance_confirm_price_list_id then
    if not public.has_permission('cs_maintenance', 'schedule') then
      raise exception 'insufficient permission to schedule maintenance';
    end if;
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.customer_product_reset_confirmation()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
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
    new.maintenance_confirm_price_list_id := null;
  end if;
  return new;
end;
$function$;
