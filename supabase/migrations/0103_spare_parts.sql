-- Spare parts: the parts of each product category (heaters, boilers, ...) with
-- their price. Managed in Customer Service by the people granted the
-- "cs_spare_parts" resource: any action on it opens the page, create / edit /
-- delete are their own actions.
create table public.spare_parts (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.product_categories (id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  price numeric not null default 0 check (price >= 0),
  notes text,
  created_by uuid references public.profiles (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index spare_parts_category on public.spare_parts (category_id);

alter table public.spare_parts enable row level security;

create policy spare_parts_select on public.spare_parts
  for select using (public.has_any_module_permission('cs_spare_parts'));
create policy spare_parts_insert on public.spare_parts
  for insert with check (public.has_permission('cs_spare_parts', 'create'));
create policy spare_parts_update on public.spare_parts
  for update using (public.has_permission('cs_spare_parts', 'edit'))
  with check (public.has_permission('cs_spare_parts', 'edit'));
create policy spare_parts_delete on public.spare_parts
  for delete using (public.has_permission('cs_spare_parts', 'delete'));

create or replace function public.spare_parts_touch()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
create trigger spare_parts_touch before update on public.spare_parts
  for each row execute function public.spare_parts_touch();
