-- The next scheduled maintenance visit (موعد الصيانة القادمة) of an operating
-- Customer Service product: a date and time, plus a free-text note.
alter table public.customer_products
  add column next_maintenance_at timestamptz,
  add column next_maintenance_note text;

create index customer_products_next_maintenance
  on public.customer_products (next_maintenance_at)
  where next_maintenance_at is not null;
