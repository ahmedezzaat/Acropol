-- The product category (heaters, boilers, ...) a technical office request is about.
-- Chosen when the deal is sent to the board; shown on the card and in its window.
alter table public.work_items
  add column product_category_id uuid references public.product_categories (id) on delete set null;
