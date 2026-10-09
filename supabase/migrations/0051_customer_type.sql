-- A customer is an individual or a company. It is derived from the company
-- name (present => company), so it can never disagree with the data and also
-- covers customers created by the CRM (won deals) and by Customer Service.
-- For a company, `name` is the contact person and `company` the company name —
-- the same convention as leads.
alter table public.customers
  add column customer_type text
  generated always as (
    case when nullif(btrim(coalesce(company, '')), '') is not null then 'company' else 'individual' end
  ) stored;
