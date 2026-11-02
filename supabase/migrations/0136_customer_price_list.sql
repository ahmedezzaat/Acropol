-- A price list per customer (for example companies vs individuals). The confirm-visit window
-- starts on the customer's list; no list means the default one (the individual customers').
alter table public.customers
  add column price_list_id uuid references public.spare_part_price_lists (id) on delete set null;
