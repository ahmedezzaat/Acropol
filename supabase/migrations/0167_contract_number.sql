-- Every contract gets a contract number made by the system: one letter and five digits (e.g. K48213), random, unique
-- and never changed. The code typed by people (contracts.code) is now called "كود الأرشيف" (the archive code).

create or replace function public.new_contract_no()
returns text
language plpgsql
as $$
declare
  v text;
begin
  loop
    v := chr(65 + floor(random() * 26)::int) || lpad(floor(random() * 100000)::int::text, 5, '0');
    exit when not exists (select 1 from public.contracts where contract_no = v);
  end loop;
  return v;
end;
$$;

alter table public.contracts add column contract_no text;

-- the contracts that exist get theirs one by one (so two of them can never draw the same number)
do $$
declare
  r record;
begin
  for r in select id from public.contracts where contract_no is null order by created_at loop
    update public.contracts set contract_no = public.new_contract_no() where id = r.id;
  end loop;
end;
$$;

alter table public.contracts alter column contract_no set default public.new_contract_no();
alter table public.contracts alter column contract_no set not null;
create unique index contracts_contract_no on public.contracts (contract_no);

-- not editable: whatever an update sends, the number stays
create or replace function public.contracts_keep_contract_no()
returns trigger
language plpgsql
as $$
begin
  new.contract_no := old.contract_no;
  return new;
end;
$$;
create trigger contracts_keep_contract_no
  before update of contract_no on public.contracts
  for each row execute function public.contracts_keep_contract_no();
