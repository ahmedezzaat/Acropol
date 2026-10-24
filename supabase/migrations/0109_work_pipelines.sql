-- Sub-workflows. A stage of a deal pipeline can hand the deal to another pipeline
-- (for example "Design" -> the technical office, with Backlog, To do, In progress,
-- Need approval, Ready to send). A work pipeline has its own stages and a board;
-- a work item is one deal inside it. Pipelines and their stages are managed in
-- Settings ("work_pipelines"); the board is the "crm_work" resource (view / edit).
create table public.work_pipelines (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create table public.work_pipeline_stages (
  id uuid primary key default gen_random_uuid(),
  work_pipeline_id uuid not null references public.work_pipelines (id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);
create index work_pipeline_stages_pipeline on public.work_pipeline_stages (work_pipeline_id, sort_order);

-- A deal stage that hands the deal to a work pipeline.
alter table public.pipeline_stages
  add column sub_pipeline_id uuid references public.work_pipelines (id) on delete set null;

create table public.work_items (
  id uuid primary key default gen_random_uuid(),
  work_pipeline_id uuid not null references public.work_pipelines (id) on delete cascade,
  stage_id uuid not null references public.work_pipeline_stages (id),
  deal_id uuid not null references public.deals (id) on delete cascade,
  title text not null,
  assigned_to uuid references public.profiles (id) on delete set null,
  created_by uuid references public.profiles (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  stage_changed_at timestamptz not null default now(),
  unique (deal_id, work_pipeline_id)
);
create index work_items_pipeline on public.work_items (work_pipeline_id, stage_id);

create or replace function public.work_items_touch()
returns trigger
language plpgsql
as $$
begin
  if new.stage_id is distinct from old.stage_id then
    new.stage_changed_at := now();
  end if;
  return new;
end;
$$;
create trigger work_items_touch before update on public.work_items
  for each row execute function public.work_items_touch();

alter table public.work_pipelines enable row level security;
alter table public.work_pipeline_stages enable row level security;
alter table public.work_items enable row level security;

-- Anyone who works with deals or the boards reads the pipelines.
create policy work_pipelines_select on public.work_pipelines
  for select using (public.has_any_module_permission('crm_work') or public.has_any_module_permission('crm_deals') or public.has_any_module_permission('settings'));
create policy work_pipelines_admin_all on public.work_pipelines
  for all using (public.has_permission('settings', 'work_pipelines')) with check (public.has_permission('settings', 'work_pipelines'));
create policy work_pipeline_stages_select on public.work_pipeline_stages
  for select using (public.has_any_module_permission('crm_work') or public.has_any_module_permission('crm_deals') or public.has_any_module_permission('settings'));
create policy work_pipeline_stages_admin_all on public.work_pipeline_stages
  for all using (public.has_permission('settings', 'work_pipelines')) with check (public.has_permission('settings', 'work_pipelines'));

-- The board: whoever has the crm_work resource sees every item; moving and editing
-- needs "edit". A deal's owner who can edit deals may send it to the board.
create policy work_items_select on public.work_items
  for select using (public.has_any_module_permission('crm_work') or public.has_any_module_permission('crm_deals'));
create policy work_items_insert on public.work_items
  for insert with check (public.has_permission('crm_work', 'edit') or public.has_permission('crm_deals', 'edit'));
create policy work_items_update on public.work_items
  for update using (public.has_permission('crm_work', 'edit')) with check (public.has_permission('crm_work', 'edit'));
create policy work_items_delete on public.work_items
  for delete using (public.has_permission('crm_work', 'edit'));

-- The technical office, as the first work pipeline.
with p as (
  insert into public.work_pipelines (name, sort_order) values ('المكتب الفني', 1) returning id
)
insert into public.work_pipeline_stages (work_pipeline_id, name, sort_order)
select p.id, s.name, s.sort_order
from p, (values ('Backlog', 1), ('To do', 2), ('In progress', 3), ('Need approval', 4), ('Ready to send', 5)) as s(name, sort_order);
