-- An invalid stage used to fail inside the date trigger with an unhelpful
-- "case not found"; fall through instead so the table's own CHECK constraint
-- reports it clearly.
create or replace function public.customer_product_stage_date()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();

  if tg_op = 'INSERT' or new.stage is distinct from old.stage then
    case new.stage
      when 'new' then new.new_at := coalesce(new.new_at, current_date);
      when 'groundwork' then new.groundwork_at := coalesce(new.groundwork_at, current_date);
      when 'supply' then new.supply_at := coalesce(new.supply_at, current_date);
      when 'installation' then new.installation_at := coalesce(new.installation_at, current_date);
      when 'operation' then new.operation_at := coalesce(new.operation_at, current_date);
      else null;
    end case;
  end if;
  return new;
end;
$$;
