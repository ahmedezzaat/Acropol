-- The "has a written note or a logged activity" filter on the Deals page. A deal
-- counts when its timeline has a note, or an activity someone logged or completed
-- (a call, a meeting, ...). Automatic entries (stage changes, assignments) and
-- activities that are only scheduled and not yet done do not count. Runs as the
-- caller, so the usual visibility rules apply.
create or replace function public.deals_with_activity()
returns setof uuid
language sql
stable
as $$
  select distinct a.deal_id
  from public.deal_activities a
  where a.type = 'note'
     or (
       a.type in (select t.key from public.activity_types t)
       and (a.completed_at is not null or a.scheduled_at is null)
     );
$$;

drop function public.deals_with_notes();
