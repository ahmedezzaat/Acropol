-- The order of the cards inside a column of a sub-workflow board: cards can be
-- dragged up and down, and the order is kept. Existing cards keep the order they
-- had (oldest in the stage first); a new card goes to the end.
alter table public.work_items
  add column position double precision not null default extract(epoch from now());
update public.work_items set position = extract(epoch from stage_changed_at);
