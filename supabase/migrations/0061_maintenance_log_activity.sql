-- The maintenance log becomes the full record of a product's maintenance:
-- besides appointments booked and visits done it also keeps cancelled
-- appointments and free-text notes, and a visit can carry its cost.
alter table public.product_maintenance_log drop constraint product_maintenance_log_kind_check;
alter table public.product_maintenance_log
  add constraint product_maintenance_log_kind_check
    check (kind in ('scheduled', 'done', 'cancelled', 'note'));
alter table public.product_maintenance_log
  add column cost numeric check (cost is null or cost >= 0);
