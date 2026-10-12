-- The ids of the deals that have at least one written note, among the deals'
-- activity the caller is allowed to see (it runs as the caller, so the usual
-- visibility rules apply). Used by the "notes" filter on the Deals page.
create or replace function public.deals_with_notes()
returns setof uuid
language sql
stable
as $$
  select distinct a.deal_id from public.deal_activities a where a.type = 'note';
$$;
