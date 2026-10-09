-- Customer Service module.
--
-- Customers (the same table the CRM uses — a customer is created when a deal is
-- won, and customer service can also add one directly) get a richer profile:
-- address (already a column), an area chosen from an admin-managed list, and
-- any number of PRODUCTS. A product is an installation job: a package of
-- instruments with quantities, a project engineer and contract date, and a
-- progress funnel — new -> groundwork -> supply -> installation -> operation —
-- with a date for each stage.

-- Areas (المنطقة), managed in Settings. Seeded from the team's own list.
create table public.service_areas (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);
alter table public.service_areas enable row level security;

create policy service_areas_select on public.service_areas
  for select using (public.has_any_module_permission('cs_customers'));
create policy service_areas_admin_all on public.service_areas
  for all
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

insert into public.service_areas (name, sort_order) values
  ('التجمع', 1), ('اكتوبر', 2), ('الشروق', 3), ('العبور', 4), ('الغردقه', 5),
  ('الاقصر', 6), ('الشيخ زايد', 7), ('المنيا', 8), ('مرسي علم', 9),
  ('مرسي مطروح', 10), ('الساحل الشمالي', 11), ('المقطم', 12),
  ('الاسكندريه', 13), ('المنصوره', 14);

alter table public.customers
  add column area_id uuid references public.service_areas (id) on delete set null;

-- Customer service sees and manages every customer, not only the ones the CRM
-- scoping (own / team / view all) would show. These policies are additive: RLS
-- policies of the same kind are OR-ed with the existing CRM ones.
create policy customers_cs_select on public.customers
  for select using (public.has_any_module_permission('cs_customers'));
create policy customers_cs_insert on public.customers
  for insert with check (public.has_permission('cs_customers', 'create'));
create policy customers_cs_update on public.customers
  for update
  using (public.has_permission('cs_customers', 'edit'))
  with check (public.has_permission('cs_customers', 'edit'));
create policy customers_cs_delete on public.customers
  for delete using (public.has_permission('cs_customers', 'delete'));

-- Products ------------------------------------------------------------------
create table public.customer_products (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  -- Only installations (التركيبات) for now; room for other funnels later.
  kind text not null default 'installation' check (kind in ('installation')),
  name text not null,
  category_id uuid references public.product_categories (id) on delete set null,
  project_engineer text,
  engineer_phone text,
  contract_date date,
  notes text,
  stage text not null default 'new'
    check (stage in ('new', 'groundwork', 'supply', 'installation', 'operation')),
  new_at date,
  groundwork_at date,
  supply_at date,
  installation_at date,
  operation_at date,
  created_by uuid references public.profiles (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index customer_products_customer on public.customer_products (customer_id);
create index customer_products_stage on public.customer_products (stage);

-- The package of instruments in a product, each with a quantity.
create table public.customer_product_items (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.customer_products (id) on delete cascade,
  name text not null,
  quantity numeric not null default 1 check (quantity > 0),
  unit text,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);
create index customer_product_items_product on public.customer_product_items (product_id);

alter table public.customer_products enable row level security;
alter table public.customer_product_items enable row level security;

create policy customer_products_select on public.customer_products
  for select using (public.has_any_module_permission('cs_customers'));
create policy customer_products_insert on public.customer_products
  for insert with check (public.has_permission('cs_customers', 'edit'));
create policy customer_products_update on public.customer_products
  for update
  using (public.has_permission('cs_customers', 'edit'))
  with check (public.has_permission('cs_customers', 'edit'));
create policy customer_products_delete on public.customer_products
  for delete using (public.has_permission('cs_customers', 'edit'));

create policy customer_product_items_select on public.customer_product_items
  for select using (public.has_any_module_permission('cs_customers'));
create policy customer_product_items_write on public.customer_product_items
  for all
  using (public.has_permission('cs_customers', 'edit'))
  with check (public.has_permission('cs_customers', 'edit'));

-- Reaching a stage records its date: if the stage was set (or moved) without
-- a date, today's date is filled in, so "each stage has a date" always holds
-- for stages that were actually reached from here on.
create or replace function public.customer_product_stage_date()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();

  if tg_op = 'INSERT' or new.stage is distinct from old.stage then
    case new.stage
      when 'new' then new.new_at := coalesce(new.new_at, current_date);
      when 'groundwork' then new.groundwork_at := coalesce(new.groundwork_at, current_date);
      when 'supply' then new.supply_at := coalesce(new.supply_at, current_date);
      when 'installation' then new.installation_at := coalesce(new.installation_at, current_date);
      when 'operation' then new.operation_at := coalesce(new.operation_at, current_date);
    end case;
  end if;
  return new;
end;
$$;

create trigger customer_products_stage_date
  before insert or update on public.customer_products
  for each row execute function public.customer_product_stage_date();
