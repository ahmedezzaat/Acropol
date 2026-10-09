-- Periodic maintenance. A product category can have a maintenance interval (in
-- months, e.g. 12 for heating): maintenance falls due every N months counted
-- from the product's operation date. When a visit is done, its date is kept on
-- the product so the next due date moves on.
alter table public.product_categories
  add column maintenance_interval_months int
    check (maintenance_interval_months is null or maintenance_interval_months > 0);

alter table public.customer_products
  add column last_maintenance_on date;
