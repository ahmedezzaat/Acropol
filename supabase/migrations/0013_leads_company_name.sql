-- For company leads, `name` holds the contact person's name and
-- `company_name` the company itself — mirrors customers.company, which
-- already splits company vs. contact name the same way.
alter table public.leads add column company_name text;
