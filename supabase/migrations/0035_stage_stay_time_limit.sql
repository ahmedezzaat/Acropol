-- Per-stage expected "stay time" (days + hours), set by an admin per
-- pipeline stage. Both null means no limit is set for that stage — the
-- default, so existing stages behave exactly as before until someone
-- opts in. The app compares a deal's time-in-stage against
-- max_stay_days/max_stay_hours to flag it as overdue in the Kanban/list.
alter table public.pipeline_stages
  add column max_stay_days int check (max_stay_days is null or max_stay_days >= 0),
  add column max_stay_hours int check (max_stay_hours is null or (max_stay_hours >= 0 and max_stay_hours < 24));
