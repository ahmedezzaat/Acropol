-- Winning a deal makes its contract. Until now the contract was made only by the dialog that records the products
-- when a deal is won, so a deal that reached the Won stage another way (or before that dialog existed) had none.
-- From now on, whenever a deal is in the Won stage and has a customer, it has a contract: made with the deal's
-- win date and value if there is none yet, or filled in (date, value) if the dialog already made one.
create or replace function public.deal_contract_on_won()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.customer_id is null
     or not exists (select 1 from public.pipeline_stages s where s.id = new.stage_id and s.system_key = 'won') then
    return new;
  end if;
  insert into public.contracts (customer_id, deal_id, signed_on, value, created_by)
  values (new.customer_id, new.id, coalesce(new.expected_close_date, current_date), new.value, auth.uid())
  on conflict (deal_id) do update
    set signed_on = coalesce(public.contracts.signed_on, excluded.signed_on),
        value = coalesce(public.contracts.value, excluded.value);
  return new;
end;
$$;

drop trigger if exists deals_contract_on_won on public.deals;
create trigger deals_contract_on_won
  after insert or update of stage_id, customer_id on public.deals
  for each row execute function public.deal_contract_on_won();

-- The deals already won that have no contract (their code stays empty: it is not recorded anywhere).
insert into public.contracts (customer_id, deal_id, signed_on, value)
select d.customer_id, d.id, coalesce(d.expected_close_date, d.updated_at::date), d.value
from public.deals d
join public.pipeline_stages s on s.id = d.stage_id and s.system_key = 'won'
where d.customer_id is not null
  and not exists (select 1 from public.contracts c where c.deal_id = d.id);
