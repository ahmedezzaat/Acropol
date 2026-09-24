-- created_by is not null on every CRM table but the app never set it
-- explicitly on insert (it's always "whoever is authenticated right now").
-- Defaulting to auth.uid() here means every insert call site doesn't need
-- to remember to pass it, and can't forget to.
alter table public.customers alter column created_by set default auth.uid();
alter table public.leads alter column created_by set default auth.uid();
alter table public.deals alter column created_by set default auth.uid();
alter table public.quotes alter column created_by set default auth.uid();
