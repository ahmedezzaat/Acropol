-- Extra details on a Customer Service product: when it went into operation,
-- its warranty (in / out, plus free-text details) and its financial position.
alter table public.customer_products
  add column operation_date date,
  add column warranty_status text check (warranty_status in ('in_warranty', 'out_of_warranty')),
  add column warranty_details text,
  add column payment_status text check (payment_status in ('paid', 'unpaid'));
