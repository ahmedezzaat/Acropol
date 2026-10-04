-- The activity-type check ran on EVERY update, so any row whose type was later
-- removed from Settings (e.g. an old "site_visit") became impossible to touch —
-- including cancelling it below. It now validates only inserts and changes of
-- the type itself.
create or replace function public.enforce_deal_activity_type()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and new.type is not distinct from old.type then
    return new;
  end if;
  if new.type in ('note', 'stage_changed', 'assigned', 'created') then
    return new;
  end if;
  if not exists (select 1 from public.activity_types where key = new.type) then
    raise exception 'invalid activity type: %', new.type;
  end if;
  return new;
end;
$$;

-- When a deal's assignee changes, its open scheduled activities are
-- cancelled: they were the previous agent's plan, and a deal may hold only
-- one open activity (deal_activities_one_open_per_deal), so leaving it would
-- stop the new agent from scheduling their own.
--
-- "Cancelled" is stored as completed_at = now() plus metadata
-- {"cancelled_on_reassign": true, "cancelled_from": <previous assignee>}, so
-- the timeline can tell a cancellation from a real completion. Applies
-- whenever a deal that HAD an assignee gets a different one — including
-- being unassigned (e.g. by an automation rule) — but not the first
-- assignment of a deal that was in the pool.
create or replace function public.cancel_open_activities_on_reassign()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.deal_activities
  set completed_at = now(),
      metadata = metadata || jsonb_build_object('cancelled_on_reassign', true, 'cancelled_from', old.assigned_to)
  where deal_id = new.id
    and scheduled_at is not null
    and completed_at is null
    and type <> 'note';
  return new;
end;
$$;

create trigger deals_cancel_open_activities_on_reassign
  after update of assigned_to on public.deals
  for each row
  when (old.assigned_to is not null and new.assigned_to is distinct from old.assigned_to)
  execute function public.cancel_open_activities_on_reassign();

-- Same rule, applied once to deals that were reassigned before it existed:
-- an open activity older than the deal's latest reassignment is cancelled.
update public.deal_activities a
set completed_at = now(),
    metadata = a.metadata || jsonb_build_object('cancelled_on_reassign', true, 'backfilled', true)
where a.scheduled_at is not null
  and a.completed_at is null
  and a.type <> 'note'
  and exists (
    select 1 from public.deal_activities x
    where x.deal_id = a.deal_id
      and x.type = 'assigned'
      and x.metadata ->> 'from' is not null
      and x.created_at > a.created_at
  );
