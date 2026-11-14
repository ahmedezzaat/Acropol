-- Customer Service quotations (عروض الأسعار): a quotation for a customer with spare parts and free lines (labour,
-- services), a discount and the 14% tax invoice option. Status: مسودة / مُرسل / مقبول / مرفوض (nothing happens
-- automatically when it is accepted). Anyone with access to Customer Service customers can make and edit them.
-- The totals are worked out by the database from the lines, the discount and the tax choice.

create sequence public.cs_quotation_no_seq;

create table public.cs_quotations (
  id uuid primary key default gen_random_uuid(),
  number text not null unique default ('QT-' || lpad(nextval('public.cs_quotation_no_seq')::text, 5, '0')),
  customer_id uuid not null references public.customers (id) on delete cascade,
  status text not null default 'draft' check (status in ('draft', 'sent', 'approved', 'rejected')),
  price_list_id uuid references public.spare_part_price_lists (id) on delete set null,
  issue_date date not null default current_date,
  valid_until date,
  discount numeric not null default 0 check (discount >= 0),
  tax_invoice boolean not null default false,
  notes text,
  subtotal numeric not null default 0,
  tax numeric not null default 0,
  total numeric not null default 0,
  created_by uuid references auth.users (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  status_changed_at timestamptz
);
create index cs_quotations_customer on public.cs_quotations (customer_id);

create table public.cs_quotation_items (
  id uuid primary key default gen_random_uuid(),
  quotation_id uuid not null references public.cs_quotations (id) on delete cascade,
  -- empty for a free line (labour, a service...)
  spare_part_id uuid references public.spare_parts (id) on delete set null,
  description text not null,
  qty numeric not null check (qty > 0),
  unit_price numeric not null check (unit_price >= 0),
  line_total numeric generated always as (qty * unit_price) stored,
  sort_order int not null default 0
);
create index cs_quotation_items_quotation on public.cs_quotation_items (quotation_id);

-- ---- totals: the lines, minus the discount (never below zero), plus 14% when it is a tax invoice
create or replace function public.cs_quotation_totals(p_subtotal numeric, p_discount numeric, p_tax boolean)
returns table (subtotal numeric, tax numeric, total numeric)
language sql
immutable
as $$
  select p_subtotal,
         case when p_tax then round(greatest(p_subtotal - least(p_discount, p_subtotal), 0) * 0.14, 2) else 0 end,
         greatest(p_subtotal - least(p_discount, p_subtotal), 0)
           + case when p_tax then round(greatest(p_subtotal - least(p_discount, p_subtotal), 0) * 0.14, 2) else 0 end;
$$;

create or replace function public.cs_quotation_before_write()
returns trigger
language plpgsql
as $$
declare
  v_sub numeric;
begin
  select coalesce(sum(line_total), 0) into v_sub from public.cs_quotation_items where quotation_id = new.id;
  select t.subtotal, t.tax, t.total into new.subtotal, new.tax, new.total from public.cs_quotation_totals(v_sub, new.discount, new.tax_invoice) t;
  new.updated_at := now();
  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    new.status_changed_at := now();
  end if;
  return new;
end;
$$;
create trigger cs_quotations_before_write
  before insert or update on public.cs_quotations
  for each row execute function public.cs_quotation_before_write();

-- a line added, changed or removed: the quotation's totals follow
create or replace function public.cs_quotation_items_changed()
returns trigger
language plpgsql
as $$
begin
  update public.cs_quotations set updated_at = now() where id = coalesce(new.quotation_id, old.quotation_id);
  return null;
end;
$$;
create trigger cs_quotation_items_changed
  after insert or update or delete on public.cs_quotation_items
  for each row execute function public.cs_quotation_items_changed();

-- ---- who: anyone with access to Customer Service customers
alter table public.cs_quotations enable row level security;
alter table public.cs_quotation_items enable row level security;
create policy cs_quotations_all on public.cs_quotations
  for all using ((select public.has_any_module_permission('cs_customers')))
  with check ((select public.has_any_module_permission('cs_customers')));
create policy cs_quotation_items_all on public.cs_quotation_items
  for all using ((select public.has_any_module_permission('cs_customers')))
  with check ((select public.has_any_module_permission('cs_customers')));
grant usage on sequence public.cs_quotation_no_seq to authenticated;

-- They pick spare parts and their prices from a price list, so they need to read them.
create policy spare_parts_select_quotations on public.spare_parts
  for select using ((select public.has_any_module_permission('cs_customers')));
create policy spare_part_prices_select_quotations on public.spare_part_prices
  for select using ((select public.has_any_module_permission('cs_customers')));
create policy spare_part_price_lists_select_quotations on public.spare_part_price_lists
  for select using ((select public.has_any_module_permission('cs_customers')));

-- ---- saving: the quotation and all its lines in one step (the lines sent replace the ones it had)
-- p_quotation: { customer_id, status, price_list_id, issue_date, valid_until, discount, tax_invoice, notes }
-- p_items: [{ spare_part_id?, description, qty, unit_price }]
create or replace function public.cs_save_quotation(p_id uuid, p_quotation jsonb, p_items jsonb)
returns uuid
language plpgsql
as $$
declare
  v_id uuid := p_id;
  v_item jsonb;
  v_n int := 0;
begin
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'at least one line is required';
  end if;
  if v_id is null then
    insert into public.cs_quotations (customer_id, status, price_list_id, issue_date, valid_until, discount, tax_invoice, notes)
    values (
      (p_quotation ->> 'customer_id')::uuid,
      coalesce(nullif(p_quotation ->> 'status', ''), 'draft'),
      nullif(p_quotation ->> 'price_list_id', '')::uuid,
      coalesce(nullif(p_quotation ->> 'issue_date', '')::date, current_date),
      nullif(p_quotation ->> 'valid_until', '')::date,
      coalesce(nullif(p_quotation ->> 'discount', '')::numeric, 0),
      coalesce((p_quotation ->> 'tax_invoice')::boolean, false),
      nullif(btrim(coalesce(p_quotation ->> 'notes', '')), '')
    )
    returning id into v_id;
  else
    update public.cs_quotations set
      customer_id = (p_quotation ->> 'customer_id')::uuid,
      status = coalesce(nullif(p_quotation ->> 'status', ''), status),
      price_list_id = nullif(p_quotation ->> 'price_list_id', '')::uuid,
      issue_date = coalesce(nullif(p_quotation ->> 'issue_date', '')::date, issue_date),
      valid_until = nullif(p_quotation ->> 'valid_until', '')::date,
      discount = coalesce(nullif(p_quotation ->> 'discount', '')::numeric, 0),
      tax_invoice = coalesce((p_quotation ->> 'tax_invoice')::boolean, false),
      notes = nullif(btrim(coalesce(p_quotation ->> 'notes', '')), '')
    where id = v_id;
    if not found then raise exception 'quotation not found'; end if;
    delete from public.cs_quotation_items where quotation_id = v_id;
  end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    if coalesce(btrim(v_item ->> 'description'), '') = '' then
      raise exception 'every line needs a description';
    end if;
    insert into public.cs_quotation_items (quotation_id, spare_part_id, description, qty, unit_price, sort_order)
    values (
      v_id,
      nullif(v_item ->> 'spare_part_id', '')::uuid,
      btrim(v_item ->> 'description'),
      (v_item ->> 'qty')::numeric,
      (v_item ->> 'unit_price')::numeric,
      v_n
    );
    v_n := v_n + 1;
  end loop;
  -- the totals, now that the lines are in
  update public.cs_quotations set updated_at = now() where id = v_id;
  return v_id;
end;
$$;
grant execute on function public.cs_save_quotation(uuid, jsonb, jsonb) to authenticated;
