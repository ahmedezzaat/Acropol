-- A deal cannot move into the Won stage until the products bought in it have been
-- recorded (crm_record_deal_products). Applied after the app that records them
-- is live, so winning deals never breaks in between.
-- The rule itself, for every way a deal can be moved to Won.
create or replace function public.deal_require_won_products()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Server-side jobs and scripts are not limited.
  if auth.uid() is null then
    return new;
  end if;
  if new.stage_id is distinct from old.stage_id
     and exists (select 1 from public.pipeline_stages s where s.id = new.stage_id and s.system_key = 'won')
     and not exists (select 1 from public.customer_products where deal_id = new.id) then
    raise exception 'won_requires_products';
  end if;
  return new;
end;
$$;

drop trigger if exists deals_require_won_products on public.deals;
create trigger deals_require_won_products
  before update of stage_id on public.deals
  for each row execute function public.deal_require_won_products();
