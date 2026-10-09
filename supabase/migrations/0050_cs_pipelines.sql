-- Customer Service funnels become admin-managed, like CRM pipelines: any
-- number of pipelines (the first is "التركيبات"), each with ordered stages that
-- can be added, renamed, reordered and removed in Settings. A stage can be
-- marked completed (is_final) and given a maximum stay time that drives the
-- overdue alerts. Each product records WHEN it reached each stage.
create table public.cs_pipelines (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create table public.cs_pipeline_stages (
  id uuid primary key default gen_random_uuid(),
  pipeline_id uuid not null references public.cs_pipelines (id) on delete cascade,
  name text not null,
  sort_order int not null default 0,
  -- A completed stage: products that reach it count as done.
  is_final boolean not null default false,
  max_stay_days int check (max_stay_days is null or max_stay_days >= 0),
  max_stay_hours int check (max_stay_hours is null or (max_stay_hours >= 0 and max_stay_hours <= 23)),
  created_at timestamptz not null default now()
);
create index cs_pipeline_stages_pipeline on public.cs_pipeline_stages (pipeline_id, sort_order);

alter table public.cs_pipelines enable row level security;
alter table public.cs_pipeline_stages enable row level security;

create policy cs_pipelines_select on public.cs_pipelines
  for select using (public.has_any_module_permission('cs_customers'));
create policy cs_pipelines_admin_all on public.cs_pipelines
  for all
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

create policy cs_pipeline_stages_select on public.cs_pipeline_stages
  for select using (public.has_any_module_permission('cs_customers'));
create policy cs_pipeline_stages_admin_all on public.cs_pipeline_stages
  for all
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

-- The existing funnel, as the first pipeline.
do $$
declare
  v_pipe uuid;
begin
  insert into public.cs_pipelines (name, sort_order) values ('التركيبات', 1) returning id into v_pipe;
  insert into public.cs_pipeline_stages (pipeline_id, name, sort_order, is_final) values
    (v_pipe, 'جديد', 1, false),
    (v_pipe, 'تأسيس', 2, false),
    (v_pipe, 'توريد', 3, false),
    (v_pipe, 'تركيب', 4, false),
    (v_pipe, 'تشغيل', 5, true);
end $$;

-- Products point at a pipeline and a stage instead of the five fixed columns.
alter table public.customer_products
  add column pipeline_id uuid references public.cs_pipelines (id) on delete restrict,
  add column stage_id uuid references public.cs_pipeline_stages (id) on delete restrict;

-- Carry over any existing product onto the matching seeded stage.
update public.customer_products p
set pipeline_id = s.pipeline_id,
    stage_id = s.id
from public.cs_pipeline_stages s
where s.pipeline_id = (select id from public.cs_pipelines order by sort_order limit 1)
  and s.sort_order = case p.stage
    when 'new' then 1 when 'groundwork' then 2 when 'supply' then 3
    when 'installation' then 4 when 'operation' then 5 end;

-- Per-stage dates, one row per (product, stage reached).
create table public.customer_product_stage_dates (
  product_id uuid not null references public.customer_products (id) on delete cascade,
  stage_id uuid not null references public.cs_pipeline_stages (id) on delete cascade,
  reached_on date not null,
  primary key (product_id, stage_id)
);

insert into public.customer_product_stage_dates (product_id, stage_id, reached_on)
select p.id, s.id, d.reached_on
from public.customer_products p
join public.cs_pipeline_stages s on s.pipeline_id = p.pipeline_id
join lateral (
  select case s.sort_order when 1 then p.new_at when 2 then p.groundwork_at when 3 then p.supply_at
                           when 4 then p.installation_at when 5 then p.operation_at end as reached_on
) d on d.reached_on is not null
on conflict do nothing;

alter table public.customer_product_stage_dates enable row level security;
create policy customer_product_stage_dates_select on public.customer_product_stage_dates
  for select using (public.has_any_module_permission('cs_customers'));
create policy customer_product_stage_dates_write on public.customer_product_stage_dates
  for all
  using (public.has_permission('cs_customers', 'edit'))
  with check (public.has_permission('cs_customers', 'edit'));

drop trigger if exists customer_products_stage_date on public.customer_products;
drop function if exists public.customer_product_stage_date();

alter table public.customer_products
  drop column stage,
  drop column new_at,
  drop column groundwork_at,
  drop column supply_at,
  drop column installation_at,
  drop column operation_at,
  drop column kind;

alter table public.customer_products
  alter column pipeline_id set not null,
  alter column stage_id set not null;
create index customer_products_stage_id on public.customer_products (stage_id);
create index customer_products_pipeline on public.customer_products (pipeline_id);

-- The stage must belong to the product's pipeline.
create or replace function public.customer_product_check_stage()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  if not exists (select 1 from public.cs_pipeline_stages s where s.id = new.stage_id and s.pipeline_id = new.pipeline_id) then
    raise exception 'the stage does not belong to the product''s pipeline';
  end if;
  return new;
end;
$$;

create trigger customer_products_check_stage
  before insert or update on public.customer_products
  for each row execute function public.customer_product_check_stage();

-- Reaching a stage records its date: today, unless a date was already given.
create or replace function public.customer_product_record_stage_date()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' or new.stage_id is distinct from old.stage_id then
    insert into public.customer_product_stage_dates (product_id, stage_id, reached_on)
    values (new.id, new.stage_id, current_date)
    on conflict (product_id, stage_id) do nothing;
  end if;
  return new;
end;
$$;

create trigger customer_products_record_stage_date
  after insert or update of stage_id on public.customer_products
  for each row execute function public.customer_product_record_stage_date();
