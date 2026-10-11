-- Deleting a customer removes only the customer. The lead it was converted from
-- (and any deals or quotes made for it) stay: they are detached from the deleted
-- customer instead of blocking the delete, and a converted lead goes back to
-- "qualified" so it shows in the leads list as an open lead again.
-- (Customers that still have products are refused separately, before this
-- takes effect: see customers_block_delete_with_products.)
create or replace function public.customer_detach_before_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.leads
  set customer_id = null,
      status = case when status = 'converted' then 'qualified' else status end
  where customer_id = old.id;

  update public.deals set customer_id = null where customer_id = old.id;
  update public.quotes set customer_id = null where customer_id = old.id;

  return old;
end;
$$;

drop trigger if exists customers_a_detach_before_delete on public.customers;
create trigger customers_a_detach_before_delete
  before delete on public.customers
  for each row execute function public.customer_detach_before_delete();
