-- A printed contract can also be made from a deal (its Files tab, section "العقد"), before the deal is won and
-- before a contract record exists. So a document belongs to a contract, to a deal, or to both (a document made on a
-- contract keeps the contract's deal).

alter table public.contract_documents alter column contract_id drop not null;
alter table public.contract_documents add column deal_id uuid references public.deals (id) on delete cascade;
alter table public.contract_documents add constraint contract_documents_scope check (contract_id is not null or deal_id is not null);
create index contract_documents_deal on public.contract_documents (deal_id);
update public.contract_documents d set deal_id = c.deal_id from public.contracts c where c.id = d.contract_id and d.deal_id is null;

drop policy contract_documents_select on public.contract_documents;
create policy contract_documents_select on public.contract_documents
  for select using (
    (
      (select public.has_any_module_permission('crm_customers')) and contract_id is not null
      and exists (select 1 from public.contracts c where c.id = contract_documents.contract_id)
    ) or (
      (select public.has_any_module_permission('crm_deals')) and deal_id is not null
      and exists (select 1 from public.deals d where d.id = contract_documents.deal_id)
    )
  );
drop policy contract_documents_delete on public.contract_documents;
create policy contract_documents_delete on public.contract_documents
  for delete using (
    (
      (select public.has_permission('crm_customers', 'delete')) and contract_id is not null
      and exists (select 1 from public.contracts c where c.id = contract_documents.contract_id)
    ) or (
      (select public.has_permission('crm_deals', 'delete')) and deal_id is not null
      and exists (select 1 from public.deals d where d.id = contract_documents.deal_id)
    )
  );

-- Save a document for a contract (needs crm_customers.edit and that the contract is visible) or for a deal (needs
-- crm_deals.edit and that the deal is visible). No document id: a new reference number is issued.
drop function public.crm_save_contract_document(uuid, uuid, text, date, jsonb);
create or replace function public.crm_save_contract_document(
  p_contract_id uuid,
  p_deal_id uuid,
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
  v_deal public.deals%rowtype;
  v_deal_id uuid := p_deal_id;
  v_year int := extract(year from p_date)::int;
  v_seq int;
  v_id uuid;
begin
  if p_contract_id is not null then
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
    v_deal_id := coalesce(p_deal_id, v_contract.deal_id);
  elsif p_deal_id is not null then
    if not public.has_permission('crm_deals', 'edit') then
      raise exception 'insufficient permission to make contract documents';
    end if;
    select * into v_deal from public.deals where id = p_deal_id;
    if not found then raise exception 'deal not found'; end if;
    if not (
      public.has_permission('crm_deals', 'view_all')
      or v_deal.assigned_to = auth.uid()
      or v_deal.created_by = auth.uid()
      or public.leads_my_team(v_deal.assigned_to)
      or public.leads_my_team(v_deal.created_by)
    ) then
      raise exception 'deal not found';
    end if;
  else
    raise exception 'a contract or a deal is required';
  end if;

  if p_document_id is not null then
    update public.contract_documents
       set doc_date = p_date, variables = coalesce(p_variables, '{}'::jsonb), updated_at = now()
     where id = p_document_id
       and ((p_contract_id is not null and contract_id = p_contract_id) or (v_deal_id is not null and deal_id = v_deal_id))
    returning id, seq, year into v_id, v_seq, v_year;
    if v_id is null then raise exception 'document not found'; end if;
    return jsonb_build_object('id', v_id, 'seq', v_seq, 'year', v_year);
  end if;

  -- a new number: the next one for this template and year (one at a time)
  insert into public.contract_doc_counters (template_key, year, last_seq) values (p_template, v_year, 1)
  on conflict (template_key, year) do update set last_seq = contract_doc_counters.last_seq + 1
  returning last_seq into v_seq;

  insert into public.contract_documents (contract_id, deal_id, template_key, year, seq, doc_date, variables, created_by)
  values (p_contract_id, v_deal_id, p_template, v_year, v_seq, p_date, coalesce(p_variables, '{}'::jsonb), auth.uid())
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'seq', v_seq, 'year', v_year);
end;
$$;
revoke all on function public.crm_save_contract_document(uuid, uuid, uuid, text, date, jsonb) from public, anon;
grant execute on function public.crm_save_contract_document(uuid, uuid, uuid, text, date, jsonb) to authenticated;
