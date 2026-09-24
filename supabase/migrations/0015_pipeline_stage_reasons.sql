-- A stage can require picking a reason when a deal moves into it (e.g.
-- "Archive" or "Bought from competitor") — reason_category marks which
-- reason list applies; null means no reason is required for that stage.
-- Reasons themselves are admin-configurable per pipeline, not a fixed enum,
-- consistent with stages/pipelines being data rather than code.
alter table public.pipeline_stages
  add column reason_category text
  check (reason_category in ('archive', 'competitor'));

create table public.pipeline_stage_reasons (
  id uuid primary key default gen_random_uuid(),
  pipeline_id uuid not null references public.pipelines (id) on delete cascade,
  category text not null check (category in ('archive', 'competitor')),
  name text not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

alter table public.pipeline_stage_reasons enable row level security;

create policy pipeline_stage_reasons_select on public.pipeline_stage_reasons
  for select
  using (public.has_any_module_permission('crm_deals'));

create policy pipeline_stage_reasons_admin_all on public.pipeline_stage_reasons
  for all
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

-- Records which reason was picked when a deal was moved into a
-- reason-requiring stage. Nullable: most stage moves don't need one.
alter table public.deals
  add column stage_reason_id uuid references public.pipeline_stage_reasons (id);

-- Tag the seeded Archive / Bought from competitor stages on all three
-- pipelines so the reason picker knows when to appear.
update public.pipeline_stages set reason_category = 'archive' where name = 'Archive';
update public.pipeline_stages set reason_category = 'competitor' where name = 'Bought from competitor';

-- Real enforcement, not just a UI nicety: a deal can't land on a
-- reason-requiring stage without a valid reason from that stage's pipeline
-- and category, and stage_reason_id is cleared when moving off one (so a
-- stale "Archive" reason doesn't linger once a deal is reopened).
create or replace function public.enforce_deal_stage_reason()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_category text;
begin
  select reason_category into v_category from public.pipeline_stages where id = new.stage_id;

  if v_category is not null then
    if new.stage_reason_id is null then
      raise exception 'a reason is required when moving a deal to this stage';
    end if;
    if not exists (
      select 1 from public.pipeline_stage_reasons r
      where r.id = new.stage_reason_id
        and r.pipeline_id = new.pipeline_id
        and r.category = v_category
    ) then
      raise exception 'selected reason does not match this stage''s pipeline and category';
    end if;
  else
    new.stage_reason_id := null;
  end if;

  return new;
end;
$$;

create trigger deals_enforce_stage_reason
  before insert or update on public.deals
  for each row execute function public.enforce_deal_stage_reason();
