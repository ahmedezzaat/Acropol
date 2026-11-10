-- Contract documents: the printed contract (PDF) generated from a template for a contract, with the values the
-- user typed in and a reference number issued by the system ("SWH 2026 - 46": template prefix, year, running
-- number). The number is issued once per document and never changes when its values are edited later.

create table public.contract_documents (
  id uuid primary key default gen_random_uuid(),
  contract_id uuid not null references public.contracts (id) on delete cascade,
  template_key text not null,
  year int not null,
  seq int not null,
  doc_date date not null,
  variables jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (template_key, year, seq)
);
create index contract_documents_contract on public.contract_documents (contract_id);

-- the last number issued per template and year (read and changed only by the function below)
create table public.contract_doc_counters (
  template_key text not null,
  year int not null,
  last_seq int not null default 0,
  primary key (template_key, year)
);
alter table public.contract_doc_counters enable row level security;
-- the last heater contract written by hand was SWH 2026 - 45: numbering continues from 46
insert into public.contract_doc_counters (template_key, year, last_seq) values ('heater', 2026, 45);

alter table public.contract_documents enable row level security;
create policy contract_documents_select on public.contract_documents
  for select using (
    (select public.has_any_module_permission('crm_customers'))
    and exists (select 1 from public.contracts c where c.id = contract_documents.contract_id)
  );
create policy contract_documents_delete on public.contract_documents
  for delete using (
    (select public.has_permission('crm_customers', 'delete'))
    and exists (select 1 from public.contracts c where c.id = contract_documents.contract_id)
  );

-- Create a document (p_document_id null: a new reference number is issued) or save new values into an existing one.
create or replace function public.crm_save_contract_document(
  p_contract_id uuid,
  p_document_id uuid,
  p_template text,
  p_date date,
  p_variables jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_contract public.contracts%rowtype;
  v_year int := extract(year from p_date)::int;
  v_seq int;
  v_id uuid;
begin
  if not public.has_permission('crm_customers', 'edit') then
    raise exception 'insufficient permission to make contract documents';
  end if;
  select * into v_contract from public.contracts where id = p_contract_id;
  if not found then raise exception 'contract not found'; end if;
  if not exists (
    select 1 from public.customers c
    where c.id = v_contract.customer_id
      and (
        public.has_permission('crm_customers', 'view_all')
        or c.assigned_to = auth.uid()
        or c.created_by = auth.uid()
        or public.leads_my_team(c.assigned_to)
        or public.leads_my_team(c.created_by)
      )
  ) then
    raise exception 'contract not found';
  end if;

  if p_document_id is not null then
    update public.contract_documents
       set doc_date = p_date, variables = coalesce(p_variables, '{}'::jsonb), updated_at = now()
     where id = p_document_id and contract_id = p_contract_id
    returning id, seq, year into v_id, v_seq, v_year;
    if v_id is null then raise exception 'document not found'; end if;
    return jsonb_build_object('id', v_id, 'seq', v_seq, 'year', v_year);
  end if;

  -- a new number: the next one for this template and year (one at a time)
  insert into public.contract_doc_counters (template_key, year, last_seq) values (p_template, v_year, 1)
  on conflict (template_key, year) do update set last_seq = contract_doc_counters.last_seq + 1
  returning last_seq into v_seq;

  insert into public.contract_documents (contract_id, template_key, year, seq, doc_date, variables, created_by)
  values (p_contract_id, p_template, v_year, v_seq, p_date, coalesce(p_variables, '{}'::jsonb), auth.uid())
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'seq', v_seq, 'year', v_year);
end;
$$;
revoke all on function public.crm_save_contract_document(uuid, uuid, text, date, jsonb) from public, anon;
grant execute on function public.crm_save_contract_document(uuid, uuid, text, date, jsonb) to authenticated;
