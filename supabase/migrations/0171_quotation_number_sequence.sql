-- Quotation numbers start at QT-6000 and run on: QT-6000, QT-6001, ... The quotations that exist are renumbered in the
-- order they were made (the oldest is QT-6000); new ones continue from the last one.
with ordered as (
  select id, row_number() over (order by created_at, id) as n
  from public.cs_quotations
)
update public.cs_quotations q set number = 'QT-' || (5999 + o.n)
from ordered o where o.id = q.id;

select setval('public.cs_quotation_no_seq', greatest((select count(*) from public.cs_quotations) + 5999, 6000), (select count(*) from public.cs_quotations) > 0);
alter table public.cs_quotations alter column number set default ('QT-' || nextval('public.cs_quotation_no_seq'));
