-- A deal cannot move into the Won stage until its contract file has been
-- uploaded (a deal attachment of kind 'contract'). Applied after the app that
-- uploads it is live, so winning deals never breaks in between.
create or replace function public.deal_require_won_contract()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return new;
  end if;
  if new.stage_id is distinct from old.stage_id
     and exists (select 1 from public.pipeline_stages s where s.id = new.stage_id and s.system_key = 'won')
     and not exists (select 1 from public.deal_attachments a where a.deal_id = new.id and a.kind = 'contract') then
    raise exception 'won_requires_contract';
  end if;
  return new;
end;
$$;

drop trigger if exists deals_require_won_contract on public.deals;
create trigger deals_require_won_contract
  before update of stage_id on public.deals
  for each row execute function public.deal_require_won_contract();
