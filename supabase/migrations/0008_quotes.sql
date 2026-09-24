create type public.quote_status as enum ('draft', 'sent', 'accepted', 'rejected', 'expired');

create sequence public.quote_number_seq;

create table public.quotes (
  id uuid primary key default gen_random_uuid(),
  deal_id uuid not null references public.deals (id),
  customer_id uuid not null references public.customers (id),
  quote_number text not null unique default (
    'Q-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('public.quote_number_seq')::text, 5, '0')
  ),
  status public.quote_status not null default 'draft',
  valid_until date,
  subtotal numeric(12, 2) not null default 0,
  tax numeric(12, 2) not null default 0,
  total numeric(12, 2) not null default 0,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- No product catalog in v1 — line items are free-text description/qty/price
-- rows rather than FK'd to a formal product table (business has a handful of
-- product lines, not a large catalog needing search/inventory).
create table public.quote_items (
  id uuid primary key default gen_random_uuid(),
  quote_id uuid not null references public.quotes (id) on delete cascade,
  description text not null,
  qty numeric(10, 2) not null default 1,
  unit_price numeric(12, 2) not null default 0,
  sort_order int not null default 0,
  line_total numeric(12, 2) generated always as (qty * unit_price) stored
);

create trigger quotes_set_updated_at
  before update on public.quotes
  for each row execute function public.set_updated_at();

-- Recompute the parent quote's subtotal/total whenever its line items
-- change, so totals can never drift from a client forgetting to resave them.
-- tax is left as a manually-set amount on the quote (not a rate), applied on
-- top of the summed subtotal.
create or replace function public.recalculate_quote_totals()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quote_id uuid := coalesce(new.quote_id, old.quote_id);
  v_subtotal numeric(12, 2);
begin
  select coalesce(sum(line_total), 0) into v_subtotal
  from public.quote_items
  where quote_id = v_quote_id;

  update public.quotes
  set subtotal = v_subtotal,
      total = v_subtotal + tax
  where id = v_quote_id;

  return null;
end;
$$;

create trigger quote_items_recalculate_totals
  after insert or update or delete on public.quote_items
  for each row execute function public.recalculate_quote_totals();

alter table public.quotes enable row level security;
alter table public.quote_items enable row level security;

create policy quotes_select on public.quotes
  for select
  using (public.has_any_module_permission('crm_quotes'));

create policy quotes_insert on public.quotes
  for insert
  with check (public.has_permission('crm_quotes', 'create'));

create policy quotes_update on public.quotes
  for update
  using (public.has_permission('crm_quotes', 'edit'));

create policy quotes_delete on public.quotes
  for delete
  using (public.has_permission('crm_quotes', 'delete'));

-- quote_items are gated on the same crm_quotes module rather than their own
-- resource key — they're never managed independently of a quote.
create policy quote_items_select on public.quote_items
  for select
  using (public.has_any_module_permission('crm_quotes'));

create policy quote_items_insert on public.quote_items
  for insert
  with check (public.has_permission('crm_quotes', 'edit'));

create policy quote_items_update on public.quote_items
  for update
  using (public.has_permission('crm_quotes', 'edit'));

create policy quote_items_delete on public.quote_items
  for delete
  using (public.has_permission('crm_quotes', 'edit'));
