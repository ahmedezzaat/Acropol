-- A lead is only converted to a customer once its deal actually reaches the
-- pipeline's fixed "Won" stage — not at deal-creation time. Quotes and the
-- rest of the pipeline run fine against a lead alone (deals.lead_id), so
-- customer_id on both deals and quotes becomes optional until then.
alter table public.deals alter column customer_id drop not null;
alter table public.quotes alter column customer_id drop not null;

-- Real enforcement, not just app-level discipline: no deal can land on the
-- Won stage without a customer, from any code path.
create or replace function public.enforce_won_requires_customer()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_system_key text;
begin
  select system_key into v_system_key from public.pipeline_stages where id = new.stage_id;
  if v_system_key = 'won' and new.customer_id is null then
    raise exception 'a deal cannot move to the Won stage without a customer — convert its lead first';
  end if;
  return new;
end;
$$;

create trigger deals_enforce_won_requires_customer
  before insert or update on public.deals
  for each row execute function public.enforce_won_requires_customer();

-- cascade_deal_assignment() previously assumed customer_id was always
-- present; guard it exactly like the existing lead_id check now that a
-- deal can be created and reassigned before it has a customer.
create or replace function public.cascade_deal_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and new.assigned_to is not distinct from old.assigned_to then
    return new;
  end if;

  perform set_config('acropol.cascading_assignment', 'true', true);

  if new.lead_id is not null then
    update public.leads set assigned_to = new.assigned_to where id = new.lead_id;
  end if;

  if new.customer_id is not null then
    update public.customers set assigned_to = new.assigned_to where id = new.customer_id;
  end if;

  perform set_config('acropol.cascading_assignment', 'false', true);
  return new;
end;
$$;
