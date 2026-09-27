-- "Offer sent" becomes a 5th fixed stage per pipeline, alongside New/Won/
-- Bought from competitor/Archive — same rename-only, never-delete
-- guarantee, so "did we send the offer" can be identified reliably by
-- system_key instead of matching stage names (which already differ per
-- pipeline: 'تم ارسال العرض' vs 'Offer sent').
alter table public.pipeline_stages drop constraint if exists pipeline_stages_system_key_check;
alter table public.pipeline_stages add constraint pipeline_stages_system_key_check
  check (system_key in ('new', 'won', 'competitor', 'archive', 'offer_sent'));

alter table public.pipeline_stages drop constraint if exists pipeline_stages_system_key_consistency;
alter table public.pipeline_stages add constraint pipeline_stages_system_key_consistency check (
  system_key is null
  or (system_key = 'new' and is_closed = false and reason_category is null)
  or (system_key = 'offer_sent' and is_closed = false and reason_category is null)
  or (system_key = 'won' and is_closed = true and reason_category is null)
  or (system_key = 'competitor' and is_closed = true and reason_category = 'competitor')
  or (system_key = 'archive' and is_closed = true and reason_category = 'archive')
);

-- Backfill: tag the existing "offer sent"-equivalent stage per pipeline,
-- picking the earliest by sort_order if a pipeline somehow has more than
-- one candidate — same approach as the other fixed stages' backfill.
with ranked as (
  select id,
    row_number() over (partition by pipeline_id order by sort_order) as rn
  from public.pipeline_stages
  where is_closed = false
    and reason_category is null
    and system_key is null
    and lower(trim(name)) in ('offer sent', 'تم ارسال العرض')
)
update public.pipeline_stages ps
set system_key = 'offer_sent'
from ranked r
where r.id = ps.id and r.rn = 1;

-- Any pipeline that didn't already have a matching stage gets one created
-- right after its "New" stage, shifting later stages down to make room.
do $$
declare
  v_pipeline record;
  v_new_sort int;
begin
  for v_pipeline in
    select p.id
    from public.pipelines p
    where not exists (
      select 1 from public.pipeline_stages ps
      where ps.pipeline_id = p.id and ps.system_key = 'offer_sent'
    )
  loop
    select sort_order into v_new_sort
    from public.pipeline_stages
    where pipeline_id = v_pipeline.id and system_key = 'new';

    update public.pipeline_stages
    set sort_order = sort_order + 1
    where pipeline_id = v_pipeline.id and sort_order > v_new_sort;

    insert into public.pipeline_stages (pipeline_id, name, sort_order, is_closed, reason_category, system_key)
    values (v_pipeline.id, 'Offer sent', v_new_sort + 1, false, null, 'offer_sent');
  end loop;
end $$;

-- Every new pipeline going forward is born with this fixed stage too.
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
    (new.id, 'Offer sent', 2, false, null, 'offer_sent'),
    (new.id, 'Won', 3, true, null, 'won'),
    (new.id, 'Bought from competitor', 4, true, 'competitor', 'competitor'),
    (new.id, 'Archive', 5, true, 'archive', 'archive');
  return new;
end;
$$;

-- Deal attachments — right now used to require the offer document before a
-- deal can move into "Offer sent", but modeled generically (any file, any
-- deal) so it isn't a single-purpose table.
create table public.deal_attachments (
  id uuid primary key default gen_random_uuid(),
  deal_id uuid not null references public.deals (id) on delete cascade,
  file_name text not null,
  storage_path text not null unique,
  uploaded_by uuid references public.profiles (id),
  created_at timestamptz not null default now()
);

alter table public.deal_attachments enable row level security;

create policy deal_attachments_select on public.deal_attachments
  for select
  using (
    exists (
      select 1 from public.deals d
      where d.id = deal_attachments.deal_id
        and public.has_any_module_permission('crm_deals')
        and (
          public.has_permission('crm_deals', 'view_all')
          or d.assigned_to = auth.uid()
          or d.created_by = auth.uid()
          or public.leads_my_team(d.assigned_to)
          or public.leads_my_team(d.created_by)
        )
    )
  );

create policy deal_attachments_insert on public.deal_attachments
  for insert
  with check (
    exists (
      select 1 from public.deals d
      where d.id = deal_attachments.deal_id
        and public.has_permission('crm_deals', 'edit')
        and (
          public.has_permission('crm_deals', 'view_all')
          or d.assigned_to = auth.uid()
          or d.created_by = auth.uid()
          or public.leads_my_team(d.assigned_to)
          or public.leads_my_team(d.created_by)
        )
    )
  );

create policy deal_attachments_delete on public.deal_attachments
  for delete
  using (
    exists (
      select 1 from public.deals d
      where d.id = deal_attachments.deal_id
        and public.has_permission('crm_deals', 'edit')
        and (
          public.has_permission('crm_deals', 'view_all')
          or d.assigned_to = auth.uid()
          or d.created_by = auth.uid()
          or public.leads_my_team(d.assigned_to)
          or public.leads_my_team(d.created_by)
        )
    )
  );

-- Storage bucket for the actual files — private, gated by the policies
-- below (never a public URL; downloads go through signed URLs).
insert into storage.buckets (id, name, public)
values ('deal-attachments', 'deal-attachments', false)
on conflict (id) do nothing;

create policy deal_attachments_storage_select on storage.objects
  for select
  using (
    bucket_id = 'deal-attachments'
    and exists (
      select 1 from public.deal_attachments da
      join public.deals d on d.id = da.deal_id
      where da.storage_path = storage.objects.name
        and public.has_any_module_permission('crm_deals')
        and (
          public.has_permission('crm_deals', 'view_all')
          or d.assigned_to = auth.uid()
          or d.created_by = auth.uid()
          or public.leads_my_team(d.assigned_to)
          or public.leads_my_team(d.created_by)
        )
    )
  );

-- No deal_attachments row exists yet at upload time (the file lands in
-- storage first, then the tracking row is inserted), so this can only
-- gate on the general edit permission — the tracking row's own RLS is
-- what actually scopes it to a deal the uploader can edit.
create policy deal_attachments_storage_insert on storage.objects
  for insert
  with check (
    bucket_id = 'deal-attachments'
    and public.has_permission('crm_deals', 'edit')
  );

create policy deal_attachments_storage_delete on storage.objects
  for delete
  using (
    bucket_id = 'deal-attachments'
    and exists (
      select 1 from public.deal_attachments da
      join public.deals d on d.id = da.deal_id
      where da.storage_path = storage.objects.name
        and public.has_permission('crm_deals', 'edit')
        and (
          public.has_permission('crm_deals', 'view_all')
          or d.assigned_to = auth.uid()
          or d.created_by = auth.uid()
          or public.leads_my_team(d.assigned_to)
          or public.leads_my_team(d.created_by)
        )
    )
  );

-- Real enforcement, not just UI discipline: a deal can't move INTO "Offer
-- sent" without an attached file. Guarded to only check on an actual
-- transition (not every future edit of a deal already parked there) —
-- several real deals were already sitting on this stage with no
-- attachment before this rule existed, and they must stay editable.
create or replace function public.enforce_offer_sent_requires_attachment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_system_key text;
begin
  if tg_op = 'UPDATE' and new.stage_id is not distinct from old.stage_id then
    return new;
  end if;

  select system_key into v_system_key from public.pipeline_stages where id = new.stage_id;
  if v_system_key = 'offer_sent' and not exists (
    select 1 from public.deal_attachments where deal_id = new.id
  ) then
    raise exception 'a deal cannot move to the Offer Sent stage without an attached file';
  end if;
  return new;
end;
$$;

create trigger deals_enforce_offer_sent_requires_attachment
  before insert or update on public.deals
  for each row execute function public.enforce_offer_sent_requires_attachment();
