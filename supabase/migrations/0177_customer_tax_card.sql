-- The tax card (البطاقة الضريبية) of a customer. Required for the customer categories that are set to ask for it
-- (شركات ومصانع), when the customer is saved, when a deal is won and when the customer is pushed to Customer Service.
-- It belongs to the customer (not to a lead or a deal): the files are kept in the private customer-files bucket,
-- one row in customer_files per file (a card can be several pages).

-- which categories ask for it (changeable in Settings, like "one visit per customer")
alter table public.customer_categories add column requires_tax_card boolean not null default false;
update public.customer_categories set requires_tax_card = true where name = 'شركات ومصانع';

insert into storage.buckets (id, name, public) values ('customer-files', 'customer-files', false) on conflict (id) do nothing;

create table public.customer_files (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  kind text not null check (kind in ('tax_card')),
  -- the name as people see it (any language); the storage key is a plain version of it
  file_name text not null,
  storage_path text not null unique,
  created_by uuid references public.profiles (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);
create index customer_files_customer on public.customer_files (customer_id, kind);

alter table public.customer_files enable row level security;
-- seen by whoever can see the customer
create policy customer_files_select on public.customer_files for select to authenticated
  using (exists (select 1 from public.customers c where c.id = customer_files.customer_id));
-- added / removed by the people who create and edit customers (and win deals)
create policy customer_files_insert on public.customer_files for insert to authenticated
  with check (
    exists (select 1 from public.customers c where c.id = customer_files.customer_id)
    and (
      public.has_permission('crm_customers', 'create') or public.has_permission('crm_customers', 'edit')
      or public.has_permission('cs_customers', 'create') or public.has_permission('cs_customers', 'edit')
      or public.has_permission('crm_deals', 'edit') or public.has_permission('crm_deals', 'create')
    )
  );
create policy customer_files_delete on public.customer_files for delete to authenticated
  using (
    exists (select 1 from public.customers c where c.id = customer_files.customer_id)
    and (
      public.has_permission('crm_customers', 'delete') or public.has_permission('crm_customers', 'edit')
      or public.has_permission('cs_customers', 'edit')
    )
  );

-- the files themselves
create policy customer_files_obj_select on storage.objects for select to authenticated
  using (bucket_id = 'customer-files' and (
    public.has_any_module_permission('crm_customers') or public.has_any_module_permission('cs_customers')
    or public.has_any_module_permission('cs_maintenance') or public.has_any_module_permission('crm_deals')));
create policy customer_files_obj_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'customer-files' and (
    public.has_permission('crm_customers', 'create') or public.has_permission('crm_customers', 'edit')
    or public.has_permission('cs_customers', 'create') or public.has_permission('cs_customers', 'edit')
    or public.has_permission('crm_deals', 'edit') or public.has_permission('crm_deals', 'create')));
create policy customer_files_obj_delete on storage.objects for delete to authenticated
  using (bucket_id = 'customer-files' and (
    public.has_permission('crm_customers', 'delete') or public.has_permission('crm_customers', 'edit')
    or public.has_permission('cs_customers', 'edit')));

-- true when the customer's category asks for a tax card and none is attached
create or replace function public.customer_tax_card_missing(p_customer uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(cat.requires_tax_card, false)
         and not exists (select 1 from public.customer_files f where f.customer_id = c.id and f.kind = 'tax_card')
  from public.customers c
  left join public.customer_categories cat on cat.id = c.category_id
  where c.id = p_customer
$$;
revoke all on function public.customer_tax_card_missing(uuid) from public, anon;
grant execute on function public.customer_tax_card_missing(uuid) to authenticated;

-- Pushing a customer to Customer Service needs the tax card (when the category asks for it)
do $$
declare
  d text := pg_get_functiondef('public.crm_push_customer_to_cs(uuid, uuid, text, uuid, jsonb)'::regprocedure);
  marker constant text := E'  perform set_config(''app.pushing_to_cs'', ''on'', true);';
begin
  if position(marker in d) = 0 then
    raise exception 'push function changed: marker not found';
  end if;
  execute replace(d, marker, E'  if public.customer_tax_card_missing(p_customer_id) then\n    raise exception ''tax_card_required'';\n  end if;\n' || marker);
end $$;

-- Merging customers also moves their tax cards
do $$
declare
  d text := pg_get_functiondef('public.cs_merge_customers(uuid, uuid[])'::regprocedure);
  marker constant text := '    update public.cs_work_orders set customer_id = p_keep where customer_id = v_id;';
begin
  if position(marker in d) = 0 then
    raise exception 'merge function changed: marker not found';
  end if;
  execute replace(d, marker, marker || E'\n    update public.customer_files set customer_id = p_keep where customer_id = v_id;');
end $$;
