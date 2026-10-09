-- A customer can decline maintenance for good. The product then drops out of
-- the periodic due dates and the overdue lists until maintenance is resumed.
-- The log also records appointments being rescheduled, declined and resumed.
alter table public.customer_products
  add column maintenance_declined_at timestamptz;

alter table public.product_maintenance_log drop constraint product_maintenance_log_kind_check;
alter table public.product_maintenance_log
  add constraint product_maintenance_log_kind_check
    check (kind in ('scheduled', 'rescheduled', 'done', 'cancelled', 'note', 'declined', 'resumed'));
