-- Atomically marks an existing deal activity complete and inserts the
-- mandatory next scheduled action in the same call, so a rep can never
-- complete an activity on an open deal without a next action queued right
-- behind it (enforce_deal_activity_type still validates p_next_type on
-- the insert since triggers fire regardless of function security context).
-- security invoker: runs as the caller, so the existing deal_activities
-- RLS policies (crm_deals:edit) still gate both the update and the insert.
create or replace function complete_deal_activity_with_followup(
  p_activity_id uuid,
  p_next_type text,
  p_next_content text,
  p_next_scheduled_at timestamptz
)
returns void
language plpgsql
security invoker
as $$
declare
  v_deal_id uuid;
begin
  update deal_activities
  set completed_at = now()
  where id = p_activity_id
  returning deal_id into v_deal_id;

  if v_deal_id is null then
    raise exception 'Activity not found or not permitted';
  end if;

  insert into deal_activities (deal_id, type, content, scheduled_at)
  values (v_deal_id, p_next_type, p_next_content, p_next_scheduled_at);
end;
$$;

grant execute on function complete_deal_activity_with_followup(uuid, text, text, timestamptz) to authenticated;
