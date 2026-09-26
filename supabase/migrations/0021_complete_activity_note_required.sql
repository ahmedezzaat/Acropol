-- Completing a deal activity now always requires a note describing what
-- happened (p_content replaces the old, unused p_next_content — the next
-- action no longer carries a note of its own, per product decision: notes
-- belong to what already happened, not to a placeholder on the calendar).
-- The next-action args are now optional so this same function also covers
-- completing an activity on a CLOSED deal, where no next action is needed
-- at all — previously that path bypassed this function entirely with a
-- plain client-side update that captured no note.
-- Postgres refuses to rename existing parameters via create-or-replace
-- (even when the type list otherwise matches), so the old signature has to
-- be dropped explicitly first.
drop function if exists public.complete_deal_activity_with_followup(uuid, text, text, timestamptz);

create or replace function public.complete_deal_activity_with_followup(
  p_activity_id uuid,
  p_content text,
  p_next_type text default null,
  p_next_scheduled_at timestamptz default null
)
returns void
language plpgsql
security invoker
as $$
declare
  v_deal_id uuid;
begin
  update deal_activities
  set completed_at = now(), content = p_content
  where id = p_activity_id
  returning deal_id into v_deal_id;

  if v_deal_id is null then
    raise exception 'Activity not found or not permitted';
  end if;

  if p_next_type is not null then
    insert into deal_activities (deal_id, type, scheduled_at)
    values (v_deal_id, p_next_type, p_next_scheduled_at);
  end if;
end;
$$;
