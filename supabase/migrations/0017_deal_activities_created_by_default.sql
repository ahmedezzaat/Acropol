-- Same class of bug as customers/leads/deals/quotes before it (see 0011):
-- default this at the DB level instead of relying on every insert call
-- site to remember to set it.
alter table public.deal_activities alter column created_by set default auth.uid();
