-- Product categories (heating, boilers, heaters, stations, pool heating, ...)
-- become admin-managed data so new ones can be added from CRM settings
-- without a migration — same reasoning as activity_types/pipelines.
create table public.product_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

alter table public.product_categories enable row level security;

create policy product_categories_select on public.product_categories
  for select
  using (public.has_any_module_permission('crm_deals'));

create policy product_categories_admin_all on public.product_categories
  for all
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

insert into public.product_categories (name, sort_order) values
  ('تدفئة', 1),
  ('غلايات', 2),
  ('سخانات', 3),
  ('محطات', 4),
  ('تسخين حمام سباحة', 5);
