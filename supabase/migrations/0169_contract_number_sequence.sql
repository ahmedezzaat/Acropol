-- Contract numbers become a running number instead of a random one: C-6000, C-6001, ... The contracts that exist are
-- renumbered in the order they were made (by contract date, then by when they were entered), the oldest being C-6000;
-- new contracts continue from the last one. The number still cannot be edited.

create sequence if not exists public.contract_no_seq start with 6000 minvalue 6000;

-- renumber the existing contracts (the "not editable" rule is paused for this one statement)
alter table public.contracts disable trigger contracts_keep_contract_no;
drop index if exists public.contracts_contract_no;
with ordered as (
  select id, row_number() over (order by coalesce(signed_on, created_at::date), created_at, id) as n
  from public.contracts
)
update public.contracts c set contract_no = 'C-' || (5999 + o.n)
from ordered o where o.id = c.id;
create unique index contracts_contract_no on public.contracts (contract_no);
alter table public.contracts enable trigger contracts_keep_contract_no;

-- new contracts continue after the last number given
select setval('public.contract_no_seq', greatest((select count(*) from public.contracts) + 5999, 6000), (select count(*) from public.contracts) > 0);
alter table public.contracts alter column contract_no set default ('C-' || nextval('public.contract_no_seq'));
grant usage on sequence public.contract_no_seq to authenticated;

drop function if exists public.new_contract_no();
