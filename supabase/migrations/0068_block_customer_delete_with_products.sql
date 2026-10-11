-- A customer that has products (and so installations and maintenance records)
-- cannot be deleted: deleting would silently wipe those products and their
-- whole maintenance history. Remove the products first, deliberately.
create or replace function public.customer_block_delete_with_products()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (select 1 from public.customer_products where customer_id = old.id) then
    raise exception 'customer_has_products';
  end if;
  return old;
end;
$$;

drop trigger if exists customers_block_delete_with_products on public.customers;
create trigger customers_block_delete_with_products
  before delete on public.customers
  for each row execute function public.customer_block_delete_with_products();
