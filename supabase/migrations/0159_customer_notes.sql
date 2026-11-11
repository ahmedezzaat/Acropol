-- A free-text notes field on customers (call notes, branches, remarks), used first by the hotels import.
alter table public.customers add column if not exists notes text;
comment on column public.customers.notes is 'Free notes about the customer (call notes, branches, remarks)';
