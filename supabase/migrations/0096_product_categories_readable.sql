-- Product categories are reference data (heaters, boilers, ...). Customer
-- Service staff filter and label customers by them, but the old policy only let
-- people with a CRM deals permission read the list, so their category filter was
-- empty. Any signed-in user can read it; only admins can change it.
drop policy if exists product_categories_select on public.product_categories;
create policy product_categories_select on public.product_categories
  for select
  using (auth.uid() is not null);
