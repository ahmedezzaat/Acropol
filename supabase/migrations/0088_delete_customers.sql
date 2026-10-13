-- Delete several customers at once (from the customers list). A customer that
-- still has products is refused unless p_with_products is true, which deletes
-- its products first (with their contracts, visits and maintenance history).
-- Deals, quotes and leads of a deleted customer stay, detached from it.
-- Returns how many customers were deleted and how many were skipped.
create or replace function public.cs_delete_customers(p_ids uuid[], p_with_products boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_deleted int := 0;
  v_skipped int := 0;
begin
  if not public.has_permission('cs_customers', 'delete') then
    raise exception 'insufficient permission to delete customers';
  end if;
  if p_with_products and not public.has_permission('cs_customers', 'edit') then
    raise exception 'insufficient permission to delete products';
  end if;
  if p_ids is null or coalesce(array_length(p_ids, 1), 0) = 0 then
    raise exception 'nothing to delete';
  end if;

  foreach v_id in array p_ids loop
    -- only customers the user can see (view all, assigned to them, or created by them)
    if not exists (
      select 1 from public.customers c
      where c.id = v_id
        and (public.has_permission('cs_customers', 'view_all') or c.cs_agent_id = auth.uid() or c.created_by = auth.uid())
    ) then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    if exists (select 1 from public.customer_products where customer_id = v_id) then
      if not p_with_products then
        v_skipped := v_skipped + 1;
        continue;
      end if;
      delete from public.customer_products where customer_id = v_id;
    end if;

    delete from public.customers where id = v_id;
    v_deleted := v_deleted + 1;
  end loop;

  return jsonb_build_object('deleted', v_deleted, 'skipped', v_skipped);
end;
$$;
