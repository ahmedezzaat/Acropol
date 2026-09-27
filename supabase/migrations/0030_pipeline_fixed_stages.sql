-- Every pipeline always has 4 fixed stages — New, Won, Bought from
-- competitor, Archive. They can be renamed but never deleted or
-- repurposed (their closed/reason semantics are locked), so "which stage
-- is Won" no longer relies on the is_closed+reason_category heuristic or
-- a name match, either of which an admin could accidentally break.
alter table public.pipeline_stages
  add column system_key text check (system_key in ('new', 'won', 'competitor', 'archive'));

-- At most one of each fixed stage per pipeline.
create unique index pipeline_stages_system_key_unique
  on public.pipeline_stages (pipeline_id, system_key)
  where system_key is not null;

-- A fixed stage's is_closed/reason_category are implied by its system_key
-- and can't drift from it — only its name is admin-editable.
alter table public.pipeline_stages
  add constraint pipeline_stages_system_key_consistency check (
    system_key is null
    or (system_key = 'new' and is_closed = false and reason_category is null)
    or (system_key = 'won' and is_closed = true and reason_category is null)
    or (system_key = 'competitor' and is_closed = true and reason_category = 'competitor')
    or (system_key = 'archive' and is_closed = true and reason_category = 'archive')
  );

-- Backfill: tag exactly one stage per pipeline per category, picking the
-- earliest by sort_order when more than one candidate exists (e.g. several
-- closed, no-reason stages) so the unique index above never trips.
with ranked as (
  select id,
    row_number() over (partition by pipeline_id order by sort_order) as rn
  from public.pipeline_stages
  where is_closed = false and reason_category is null
)
update public.pipeline_stages ps
set system_key = 'new'
from ranked r
where r.id = ps.id and r.rn = 1;

with ranked as (
  select id,
    row_number() over (partition by pipeline_id order by sort_order) as rn
  from public.pipeline_stages
  where is_closed = true and reason_category is null
)
update public.pipeline_stages ps
set system_key = 'won'
from ranked r
where r.id = ps.id and r.rn = 1;

with ranked as (
  select id,
    row_number() over (partition by pipeline_id order by sort_order) as rn
  from public.pipeline_stages
  where reason_category = 'competitor'
)
update public.pipeline_stages ps
set system_key = 'competitor'
from ranked r
where r.id = ps.id and r.rn = 1;

with ranked as (
  select id,
    row_number() over (partition by pipeline_id order by sort_order) as rn
  from public.pipeline_stages
  where reason_category = 'archive'
)
update public.pipeline_stages ps
set system_key = 'archive'
from ranked r
where r.id = ps.id and r.rn = 1;

-- Real enforcement, not just UI hiding: a fixed stage can never be deleted,
-- even by a direct API call.
create or replace function public.enforce_no_delete_system_stage()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.system_key is not null then
    raise exception 'this stage is fixed and cannot be deleted';
  end if;
  return old;
end;
$$;

create trigger pipeline_stages_no_delete_system
  before delete on public.pipeline_stages
  for each row execute function public.enforce_no_delete_system_stage();

-- Every new pipeline is born with its 4 fixed stages already in place —
-- an admin only ever adds the stages in between.
create or replace function public.seed_pipeline_fixed_stages()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.pipeline_stages (pipeline_id, name, sort_order, is_closed, reason_category, system_key)
  values
    (new.id, 'New', 1, false, null, 'new'),
    (new.id, 'Won', 2, true, null, 'won'),
    (new.id, 'Bought from competitor', 3, true, 'competitor', 'competitor'),
    (new.id, 'Archive', 4, true, 'archive', 'archive');
  return new;
end;
$$;

create trigger pipelines_seed_fixed_stages
  after insert on public.pipelines
  for each row execute function public.seed_pipeline_fixed_stages();
