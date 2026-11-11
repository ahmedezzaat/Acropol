-- One maintenance visit per customer (for categories such as "فنادق"): a hotel that bought heaters in several batches
-- on different dates is serviced in ONE visit, not one per product.
--   * customer_categories.one_visit_per_customer turns it on per category (on for فنادق).
--   * The maintenance state of such a customer's products (next appointment, confirmation, technician, last
--     maintenance, declined...) is kept identical across its products of the same category: when it changes on
--     one product, the database copies it to the others. The maintenance board shows one row for them.

alter table public.customer_categories add column one_visit_per_customer boolean not null default false;
update public.customer_categories set one_visit_per_customer = true where name = 'فنادق';

create or replace function public.sync_customer_maintenance()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- the copies below fire this trigger again: stop there
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
    maintenance_confirm_price_list_id = new.maintenance_confirm_price_list_id,
    maintenance_technician_id = new.maintenance_technician_id,
    maintenance_assigned_at = new.maintenance_assigned_at
  where s.customer_id = new.customer_id
    and s.id <> new.id
    and s.category_id is not distinct from new.category_id
    and exists (select 1 from public.cs_pipeline_stages st where st.id = s.stage_id and st.is_final)
    and (s.next_maintenance_at, s.next_maintenance_note, s.last_maintenance_on, s.maintenance_declined_at, s.maintenance_confirmed_at,
         s.maintenance_confirmed_by, s.maintenance_confirm_note, s.maintenance_confirm_parts, s.maintenance_confirm_fee,
         s.maintenance_confirm_price_list_id, s.maintenance_technician_id, s.maintenance_assigned_at)
        is distinct from
        (new.next_maintenance_at, new.next_maintenance_note, new.last_maintenance_on, new.maintenance_declined_at, new.maintenance_confirmed_at,
         new.maintenance_confirmed_by, new.maintenance_confirm_note, new.maintenance_confirm_parts, new.maintenance_confirm_fee,
         new.maintenance_confirm_price_list_id, new.maintenance_technician_id, new.maintenance_assigned_at);
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
  )
  execute function public.sync_customer_maintenance();

-- Align what already exists: every product of such a customer takes the state of the one maintained most recently.
with rep as (
  select distinct on (p.customer_id, p.category_id) p.*
  from public.customer_products p
  join public.customers c on c.id = p.customer_id
  join public.customer_categories cc on cc.id = c.category_id and cc.one_visit_per_customer
  join public.cs_pipeline_stages st on st.id = p.stage_id and st.is_final
  order by p.customer_id, p.category_id, p.last_maintenance_on desc nulls last, p.next_maintenance_at desc nulls last, p.id
)
update public.customer_products s set
  next_maintenance_at = rep.next_maintenance_at,
  next_maintenance_note = rep.next_maintenance_note,
  last_maintenance_on = rep.last_maintenance_on,
  maintenance_declined_at = rep.maintenance_declined_at,
  maintenance_confirmed_at = rep.maintenance_confirmed_at,
  maintenance_confirmed_by = rep.maintenance_confirmed_by,
  maintenance_confirm_note = rep.maintenance_confirm_note,
  maintenance_confirm_parts = rep.maintenance_confirm_parts,
  maintenance_confirm_fee = rep.maintenance_confirm_fee,
  maintenance_confirm_price_list_id = rep.maintenance_confirm_price_list_id,
  maintenance_technician_id = rep.maintenance_technician_id,
  maintenance_assigned_at = rep.maintenance_assigned_at
from rep
where s.customer_id = rep.customer_id and s.category_id is not distinct from rep.category_id and s.id <> rep.id
  and exists (select 1 from public.cs_pipeline_stages st where st.id = s.stage_id and st.is_final);
