-- A deal should have at most one open (scheduled, not yet completed)
-- activity at a time — not a growing pile of pending follow-ups. Before
-- enforcing that as a real constraint, collapse any deal that currently
-- has more than one down to just its earliest-scheduled one; the rest get
-- marked completed (this is cleanup for rows created before the
-- constraint existed, not a feature).
with ranked as (
  select id, deal_id,
         row_number() over (partition by deal_id order by scheduled_at asc) as rn
  from public.deal_activities
  where completed_at is null and scheduled_at is not null and type <> 'note'
)
update public.deal_activities da
set completed_at = now()
from ranked r
where da.id = r.id and r.rn > 1;

-- type <> 'note' matches the app's own definition of "open" (see
-- upcomingActivities in crm/deals/[id].vue) — notes are never scheduled in
-- practice, but excluding them keeps the constraint's meaning exact.
create unique index deal_activities_one_open_per_deal
  on public.deal_activities (deal_id)
  where completed_at is null and scheduled_at is not null and type <> 'note';
