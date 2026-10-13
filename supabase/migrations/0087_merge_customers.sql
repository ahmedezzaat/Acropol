-- Merge duplicate customers into one. Everything that hangs off the merged
-- customers (products, contracts, maintenance visits, deals, quotes and leads)
-- moves to the customer that is kept; their phone numbers become additional
-- contacts (named after the merged customer) and any empty detail of the kept
-- customer is filled from them. The merged customers are then removed.
create or replace function public.cs_merge_customers(p_keep uuid, p_merge uuid[])
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_keep public.customers;
  v_m public.customers;
  v_all uuid[];
  v_id uuid;
  v_phones text[];
  v_names text[];
  v_count int := 0;
  v_cand_phone text;
  v_cand_name text;
  i int;
  v_first_created timestamptz;
begin
  if not (public.has_permission('cs_customers', 'edit') and public.has_permission('cs_customers', 'delete')) then
    raise exception 'insufficient permission to merge customers';
  end if;
  if p_merge is null or coalesce(array_length(p_merge, 1), 0) = 0 then
    raise exception 'nothing to merge';
  end if;
  if p_keep = any(p_merge) then
    raise exception 'the kept customer cannot be merged into itself';
  end if;

  v_all := array_append(p_merge, p_keep);
  -- Every customer involved must be one the user can see (view all, assigned to
  -- them, or created by them) - the definer rights must not widen that.
  foreach v_id in array v_all loop
    if not exists (
      select 1 from public.customers c
      where c.id = v_id
        and (public.has_permission('cs_customers', 'view_all') or c.cs_agent_id = auth.uid() or c.created_by = auth.uid())
    ) then
      raise exception 'customer not found or not visible';
    end if;
  end loop;

  select * into v_keep from public.customers where id = p_keep for update;
  v_phones := coalesce(v_keep.extra_phones, '{}');
  v_names := coalesce(v_keep.extra_phone_names, '{}');
  while coalesce(array_length(v_names, 1), 0) < coalesce(array_length(v_phones, 1), 0) loop
    v_names := array_append(v_names, '');
  end loop;
  v_first_created := v_keep.created_at;

  foreach v_id in array p_merge loop
    select * into v_m from public.customers where id = v_id for update;

    -- Their numbers become contacts of the kept customer.
    for i in 0 .. coalesce(array_length(v_m.extra_phones, 1), 0) loop
      if i = 0 then
        v_cand_phone := v_m.phone;
        v_cand_name := coalesce(nullif(btrim(v_m.company), ''), v_m.name);
      else
        v_cand_phone := v_m.extra_phones[i];
        v_cand_name := coalesce(nullif(btrim(v_m.extra_phone_names[i]), ''), v_m.name);
      end if;
      if nullif(btrim(coalesce(v_cand_phone, '')), '') is not null
         and v_cand_phone is distinct from v_keep.phone
         and not (v_cand_phone = any(v_phones)) then
        v_phones := array_append(v_phones, v_cand_phone);
        v_names := array_append(v_names, v_cand_name);
      end if;
    end loop;

    -- Fill the kept customer's empty details.
    if v_keep.email is null and nullif(btrim(coalesce(v_m.email, '')), '') is not null then v_keep.email := v_m.email; end if;
    if v_keep.address is null and nullif(btrim(coalesce(v_m.address, '')), '') is not null then v_keep.address := v_m.address; end if;
    if v_keep.area_id is null and v_m.area_id is not null then v_keep.area_id := v_m.area_id; end if;
    if v_keep.converted_from_lead_id is null and v_m.converted_from_lead_id is not null then v_keep.converted_from_lead_id := v_m.converted_from_lead_id; end if;
    if v_keep.phone is null and nullif(btrim(coalesce(v_m.phone, '')), '') is not null then
      -- the kept customer has no main phone: take theirs as the main one
      v_keep.phone := v_m.phone;
      v_phones := array_remove(v_phones, v_m.phone);
    end if;
    v_first_created := least(v_first_created, v_m.created_at);

    -- Move everything that belongs to them.
    update public.contracts set customer_id = p_keep where customer_id = v_id;
    update public.customer_products set customer_id = p_keep where customer_id = v_id;
    update public.maintenance_visits set customer_id = p_keep where customer_id = v_id;
    update public.deals set customer_id = p_keep where customer_id = v_id;
    update public.quotes set customer_id = p_keep where customer_id = v_id;
    update public.leads set customer_id = p_keep where customer_id = v_id;

    delete from public.customers where id = v_id;
    v_count := v_count + 1;
  end loop;

  -- keep the numbers and names lined up
  v_names := v_names[1:coalesce(array_length(v_phones, 1), 0)];
  while coalesce(array_length(v_names, 1), 0) < coalesce(array_length(v_phones, 1), 0) loop
    v_names := array_append(v_names, '');
  end loop;

  update public.customers
  set phone = v_keep.phone, email = v_keep.email, address = v_keep.address, area_id = v_keep.area_id,
      converted_from_lead_id = v_keep.converted_from_lead_id,
      extra_phones = v_phones, extra_phone_names = v_names, created_at = v_first_created
  where id = p_keep;

  return v_count;
end;
$$;
