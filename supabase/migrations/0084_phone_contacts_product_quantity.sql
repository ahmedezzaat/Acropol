-- A contact person for each extra phone number (the 2nd, 3rd... person to call),
-- and how many units of a product the customer bought.
--
-- extra_phone_names lines up with extra_phones by position; a missing name is
-- simply blank, so everything that only knows extra_phones keeps working.
alter table public.customers
  add column if not exists extra_phone_names text[] not null default '{}';

alter table public.customer_products
  add column if not exists quantity integer not null default 1 check (quantity > 0);

-- Recording the products of a won deal now carries the quantity too (it
-- defaults to 1, so an older client that does not send one still works).
create or replace function public.crm_record_deal_products(p_deal_id uuid, p_products jsonb)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deal public.deals;
  v_first uuid;
  v_item jsonb;
  v_count int := 0;
begin
  select * into v_deal from public.deals where id = p_deal_id;
  if not found then
    raise exception 'deal not found';
  end if;

  -- Same visibility and permission as changing the deal itself.
  if not (
    (public.has_permission('crm_deals', 'edit') or public.has_permission('crm_deals', 'create'))
    and (
      public.has_permission('crm_deals', 'view_all')
      or v_deal.assigned_to = auth.uid()
      or v_deal.created_by = auth.uid()
      or public.leads_my_team(v_deal.assigned_to)
      or public.leads_my_team(v_deal.created_by)
    )
  ) then
    raise exception 'insufficient permission to record products for this deal';
  end if;

  if v_deal.customer_id is null then
    raise exception 'the deal has no customer yet';
  end if;
  if p_products is null or jsonb_typeof(p_products) <> 'array' or jsonb_array_length(p_products) = 0 then
    raise exception 'at least one product is required';
  end if;

  select s.id into v_first
  from public.cs_pipeline_stages s
  join public.cs_pipelines p on p.id = s.pipeline_id
  order by p.sort_order, s.sort_order
  limit 1;

  delete from public.customer_products cp
  where cp.deal_id = p_deal_id
    and cp.created_by = auth.uid()
    and cp.created_at > now() - interval '2 hours'
    and cp.stage_id = v_first;

  for v_item in select * from jsonb_array_elements(p_products) loop
    if coalesce(btrim(v_item ->> 'name'), '') = '' then
      raise exception 'every product needs a name';
    end if;
    insert into public.customer_products (
      customer_id, deal_id, name, category_id, contract_code, contract_date,
      sales_person_id, warranty_status, warranty_details, payment_status, notes, quantity, created_by
    ) values (
      v_deal.customer_id,
      p_deal_id,
      btrim(v_item ->> 'name'),
      nullif(v_item ->> 'category_id', '')::uuid,
      nullif(btrim(coalesce(v_item ->> 'contract_code', '')), ''),
      nullif(v_item ->> 'contract_date', '')::date,
      nullif(v_item ->> 'sales_person_id', '')::uuid,
      nullif(v_item ->> 'warranty_status', ''),
      nullif(btrim(coalesce(v_item ->> 'warranty_details', '')), ''),
      nullif(v_item ->> 'payment_status', ''),
      nullif(btrim(coalesce(v_item ->> 'notes', '')), ''),
      greatest(coalesce(nullif(v_item ->> 'quantity', '')::int, 1), 1),
      auth.uid()
    );
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;
