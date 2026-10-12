-- Product category policies, managed in Settings -> Product categories:
--  * warranty_policy: the warranty terms for the category, offered when a product
--    of that category is created or edited.
--  * maintenance_tasks: what recurring maintenance does for the category, as a
--    list of {every_months, title, replace}. Visits already come every
--    maintenance_interval_months from the operating date (تم التشغيل); a task
--    with "every N months" is part of the visits that fall on its interval, and
--    "replace" names the parts to change.
alter table public.product_categories
  add column warranty_policy text,
  add column maintenance_tasks jsonb not null default '[]'::jsonb;
