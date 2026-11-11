-- Classification of customers and contacts (leads): فرد / فنادق / شركات ومصانع / مكاتب هندسة ... The list is kept in
-- Settings (customer_categories) so it can grow. A lead's classification is copied to the customer when it is converted.

create table public.customer_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);
alter table public.customer_categories enable row level security;
create policy customer_categories_select on public.customer_categories
  for select using (auth.uid() is not null);
create policy customer_categories_admin_all on public.customer_categories
  for all using (public.has_permission('settings', 'customer_categories'))
  with check (public.has_permission('settings', 'customer_categories'));

insert into public.customer_categories (name, sort_order) values
  ('فرد', 1), ('فنادق', 2), ('شركات ومصانع', 3), ('مكاتب هندسة', 4);

alter table public.leads add column category_id uuid references public.customer_categories (id) on delete set null;
alter table public.customers add column category_id uuid references public.customer_categories (id) on delete set null;
create index leads_category on public.leads (category_id);
create index customers_category on public.customers (category_id);

-- Existing records: individuals are "فرد", companies "شركات ومصانع", and the imported hotels (their products carry the
-- hotel code H&A###) are "فنادق".
update public.leads set category_id = (select id from public.customer_categories where name = case when lead_type = 'company' then 'شركات ومصانع' else 'فرد' end);
update public.customers set category_id = (select id from public.customer_categories where name = case when customer_type = 'company' then 'شركات ومصانع' else 'فرد' end);
update public.customers c set category_id = (select id from public.customer_categories where name = 'فنادق')
where exists (select 1 from public.customer_products p where p.customer_id = c.id and p.contract_code like 'H&A%');
update public.leads l set category_id = c.category_id
from public.customers c where l.customer_id = c.id and c.category_id is not null;

-- New records without a classification get the one that matches their type (any way they are created).
create or replace function public.default_lead_category()
returns trigger language plpgsql as $$
begin
  if new.category_id is null then
    select id into new.category_id from public.customer_categories where name = case when new.lead_type = 'company' then 'شركات ومصانع' else 'فرد' end;
  end if;
  return new;
end;
$$;
create trigger leads_default_category before insert on public.leads
  for each row execute function public.default_lead_category();

create or replace function public.default_customer_category()
returns trigger language plpgsql as $$
begin
  if new.category_id is null then
    select id into new.category_id from public.customer_categories
    where name = case when nullif(btrim(coalesce(new.company, '')), '') is not null then 'شركات ومصانع' else 'فرد' end;
  end if;
  return new;
end;
$$;
create trigger customers_default_category before insert on public.customers
  for each row execute function public.default_customer_category();

-- Converting a lead carries its classification over.
create or replace function public.crm_convert_lead(p_lead_id uuid, p_pending boolean default false)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer_id uuid;
  v_lead record;
begin
  if not public.has_permission('crm_customers', 'create') then
    raise exception 'insufficient permission to create customer';
  end if;

  select * into v_lead from public.leads where id = p_lead_id;
  if not found then
    raise exception 'lead % not found', p_lead_id;
  end if;

  -- security definer bypasses the leads RLS policy's row-scoping, so it's
  -- re-checked explicitly here — otherwise a user without view_all could
  -- convert a lead they have no visibility into.
  if not (
    public.has_permission('crm_leads', 'edit')
    and (
      public.has_permission('crm_leads', 'view_all')
      or v_lead.assigned_to = auth.uid()
      or v_lead.created_by = auth.uid()
    )
  ) then
    raise exception 'insufficient permission to convert this lead';
  end if;

  insert into public.customers (name, company, phone, extra_phones, email, area_id, converted_from_lead_id, created_by, cs_pending, category_id)
  values (
    v_lead.name,
    case when v_lead.lead_type = 'company' then v_lead.company_name else null end,
    v_lead.phone,
    case when nullif(btrim(coalesce(v_lead.phone2, '')), '') is not null then array[v_lead.phone2] else '{}'::text[] end,
    v_lead.email,
    v_lead.area_id,
    p_lead_id,
    auth.uid(),
    coalesce(p_pending, false),
    v_lead.category_id
  )
  returning id into v_customer_id;

  update public.leads
  set status = 'converted', customer_id = v_customer_id
  where id = p_lead_id;

  return v_customer_id;
end;
$$;
grant execute on function public.crm_convert_lead(uuid, boolean) to authenticated;
