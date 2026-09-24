-- Deals move from a single fixed stage enum to admin-configurable pipelines,
-- each with its own ordered list of stages (mirrors how roles are
-- admin-managed data rather than a code enum) — the business runs distinct
-- pipelines (End User, B2B Direct, Tender) with different stage flows.
create table public.pipelines (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create table public.pipeline_stages (
  id uuid primary key default gen_random_uuid(),
  pipeline_id uuid not null references public.pipelines (id) on delete cascade,
  name text not null,
  sort_order int not null default 0,
  -- Open vs closed only (not won/lost) — that's the one distinction asked
  -- for; a closed stage like "Won" is still just identified by its name.
  is_closed boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.pipelines enable row level security;
alter table public.pipeline_stages enable row level security;

-- Anyone with crm_deals access needs to read pipelines/stages to render
-- deal forms and the pipeline board.
create policy pipelines_select on public.pipelines
  for select
  using (public.has_any_module_permission('crm_deals'));

create policy pipeline_stages_select on public.pipeline_stages
  for select
  using (public.has_any_module_permission('crm_deals'));

-- Managing the pipelines/stages themselves is admin-only configuration,
-- same tier as roles — not a crm_deals action.
create policy pipelines_admin_all on public.pipelines
  for all
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

create policy pipeline_stages_admin_all on public.pipeline_stages
  for all
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

insert into public.pipelines (name, sort_order) values
  ('End User', 1),
  ('B2B Direct', 2),
  ('Tender', 3);

-- Same starting stage set on all three pipelines per instruction — each can
-- be edited independently later via the admin Pipelines UI.
insert into public.pipeline_stages (pipeline_id, name, sort_order, is_closed)
select p.id, s.name, s.sort_order, s.is_closed
from public.pipelines p
cross join (values
  ('New', 1, false),
  ('Try to reach', 2, false),
  ('Followup', 3, false),
  ('Need offer', 4, false),
  ('Offer sent', 5, false),
  ('Negotiation', 6, false),
  ('Won', 7, true),
  ('Bought from competitor', 8, true),
  ('Archive', 9, true)
) as s(name, sort_order, is_closed);

alter table public.deals
  add column pipeline_id uuid references public.pipelines (id),
  add column stage_id uuid references public.pipeline_stages (id);

-- Backfill existing deals onto the first pipeline's first stage.
update public.deals
set pipeline_id = (select id from public.pipelines order by sort_order limit 1),
    stage_id = (
      select ps.id from public.pipeline_stages ps
      join public.pipelines p on p.id = ps.pipeline_id
      where p.name = 'End User'
      order by ps.sort_order
      limit 1
    )
where pipeline_id is null;

alter table public.deals
  alter column pipeline_id set not null,
  alter column stage_id set not null;

alter table public.deals drop column stage;
drop type if exists public.deal_stage;
