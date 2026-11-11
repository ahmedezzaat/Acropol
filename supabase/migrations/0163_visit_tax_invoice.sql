-- Tax invoice (فاتورة ضريبية) on a work order: when chosen, 14% value-added tax is added to the visit total (after any
-- discount). Chosen when the visit is confirmed, adjustable when it is marked done; the done entry keeps the choice and
-- the tax amount, and its cost is the total with the tax.

alter table public.customer_products add column maintenance_confirm_tax_invoice boolean not null default false;
alter table public.product_maintenance_log add column tax_invoice boolean;
alter table public.product_maintenance_log add column tax_amount numeric check (tax_amount is null or tax_amount >= 0);

-- the tax-invoice choice is one more maintenance column: no product-edit permission, only the same "schedule" action
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
    'maintenance_confirm_parts', 'maintenance_confirm_fee', 'maintenance_confirm_price_list_id',
    'maintenance_confirm_discount', 'maintenance_confirm_tax_invoice'
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
     or new.maintenance_confirm_discount is distinct from old.maintenance_confirm_discount
     or new.maintenance_confirm_tax_invoice is distinct from old.maintenance_confirm_tax_invoice
     or new.maintenance_confirm_price_list_id is distinct from old.maintenance_confirm_price_list_id then
    if not public.has_permission('cs_maintenance', 'schedule') then
      raise exception 'insufficient permission to schedule maintenance';
    end if;
  end if;

  return new;
end;
$$;

-- no confirmation, no expected fees (and so no discount and no tax invoice)
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
    new.maintenance_confirm_discount := null;
    new.maintenance_confirm_tax_invoice := false;
    new.maintenance_confirm_price_list_id := null;
  end if;
  return new;
end;
$$;

-- a customer with one visit for all its products keeps the tax-invoice choice in step too
drop trigger if exists customer_products_sync_maintenance on public.customer_products;
create or replace function public.sync_customer_maintenance()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if pg_trigger_depth() > 1 then return null; end if;
  if not exists (
    select 1 from public.customers c join public.customer_categories cc on cc.id = c.category_id
    where c.id = new.customer_id and cc.one_visit_per_customer
  ) then
    return null;
  end if;
  update public.customer_products s set
    next_maintenance_at = new.next_maintenance_at,
    next_maintenance_note = new.next_maintenance_note,
    last_maintenance_on = new.last_maintenance_on,
    maintenance_declined_at = new.maintenance_declined_at,
    maintenance_confirmed_at = new.maintenance_confirmed_at,
    maintenance_confirmed_by = new.maintenance_confirmed_by,
    maintenance_confirm_note = new.maintenance_confirm_note,
    maintenance_confirm_parts = new.maintenance_confirm_parts,
    maintenance_confirm_fee = new.maintenance_confirm_fee,
    maintenance_confirm_discount = new.maintenance_confirm_discount,
    maintenance_confirm_tax_invoice = new.maintenance_confirm_tax_invoice,
    maintenance_confirm_price_list_id = new.maintenance_confirm_price_list_id,
    maintenance_technician_id = new.maintenance_technician_id,
    maintenance_assigned_at = new.maintenance_assigned_at
  where s.customer_id = new.customer_id
    and s.id <> new.id
    and s.category_id is not distinct from new.category_id
    and exists (select 1 from public.cs_pipeline_stages st where st.id = s.stage_id and st.is_final)
    and (s.next_maintenance_at, s.next_maintenance_note, s.last_maintenance_on, s.maintenance_declined_at, s.maintenance_confirmed_at,
         s.maintenance_confirmed_by, s.maintenance_confirm_note, s.maintenance_confirm_parts, s.maintenance_confirm_fee,
         s.maintenance_confirm_discount, s.maintenance_confirm_tax_invoice, s.maintenance_confirm_price_list_id, s.maintenance_technician_id, s.maintenance_assigned_at)
        is distinct from
        (new.next_maintenance_at, new.next_maintenance_note, new.last_maintenance_on, new.maintenance_declined_at, new.maintenance_confirmed_at,
         new.maintenance_confirmed_by, new.maintenance_confirm_note, new.maintenance_confirm_parts, new.maintenance_confirm_fee,
         new.maintenance_confirm_discount, new.maintenance_confirm_tax_invoice, new.maintenance_confirm_price_list_id, new.maintenance_technician_id, new.maintenance_assigned_at);
  return null;
end;
$$;
create trigger customer_products_sync_maintenance
  after update on public.customer_products
  for each row
  when (
    old.next_maintenance_at is distinct from new.next_maintenance_at
    or old.next_maintenance_note is distinct from new.next_maintenance_note
    or old.last_maintenance_on is distinct from new.last_maintenance_on
    or old.maintenance_declined_at is distinct from new.maintenance_declined_at
    or old.maintenance_confirmed_at is distinct from new.maintenance_confirmed_at
    or old.maintenance_technician_id is distinct from new.maintenance_technician_id
    or old.maintenance_assigned_at is distinct from new.maintenance_assigned_at
    or old.maintenance_confirm_parts is distinct from new.maintenance_confirm_parts
    or old.maintenance_confirm_fee is distinct from new.maintenance_confirm_fee
    or old.maintenance_confirm_discount is distinct from new.maintenance_confirm_discount
    or old.maintenance_confirm_tax_invoice is distinct from new.maintenance_confirm_tax_invoice
  )
  execute function public.sync_customer_maintenance();
