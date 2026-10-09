-- The sales person (البائع) who sold a Customer Service product: one of the
-- existing users.
alter table public.customer_products
  add column sales_person_id uuid references public.profiles (id) on delete set null;
create index customer_products_sales_person on public.customer_products (sales_person_id);
