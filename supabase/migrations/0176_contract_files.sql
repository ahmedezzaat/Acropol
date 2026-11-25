-- A contract can have several files, not one. contract_files holds them all (the file itself is in the contract-files
-- bucket). contracts.file_name / file_path stay as the FIRST file of the contract, kept in step by the trigger below,
-- so the places that show "the contract's file" (the list, the customer page, the deal's files) keep working.
create table public.contract_files (
  id uuid primary key default gen_random_uuid(),
  contract_id uuid not null references public.contracts (id) on delete cascade,
  -- the name as people see it (any language); the storage key is a plain version of it
  file_name text not null,
  storage_path text not null unique,
  created_by uuid references public.profiles (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);
create index contract_files_contract on public.contract_files (contract_id, created_at);

alter table public.contract_files enable row level security;
-- seen by whoever can see the contract
create policy contract_files_select on public.contract_files for select to authenticated
  using (exists (select 1 from public.contracts c where c.id = contract_files.contract_id));
-- added / removed by the people the contract-files bucket already lets upload / delete
create policy contract_files_insert on public.contract_files for insert to authenticated
  with check (
    exists (select 1 from public.contracts c where c.id = contract_files.contract_id)
    and (
      public.has_permission('crm_customers', 'create') or public.has_permission('crm_customers', 'edit')
      or public.has_permission('cs_customers', 'edit')
      or public.has_permission('crm_deals', 'edit') or public.has_permission('crm_deals', 'create')
    )
  );
create policy contract_files_delete on public.contract_files for delete to authenticated
  using (
    exists (select 1 from public.contracts c where c.id = contract_files.contract_id)
    and (
      public.has_permission('crm_customers', 'delete') or public.has_permission('crm_customers', 'edit')
      or public.has_permission('crm_customers', 'create') or public.has_permission('cs_customers', 'edit')
    )
  );

-- the contract's own file columns follow its first file
create or replace function public.contract_files_sync()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_contract uuid := coalesce(new.contract_id, old.contract_id);
  v_name text;
  v_path text;
begin
  select f.file_name, f.storage_path into v_name, v_path
  from public.contract_files f where f.contract_id = v_contract order by f.created_at, f.id limit 1;
  update public.contracts set file_name = v_name, file_path = v_path
  where id = v_contract and (file_path is distinct from v_path or file_name is distinct from v_name);
  return null;
end;
$$;
create trigger contract_files_sync after insert or delete on public.contract_files
  for each row execute function public.contract_files_sync();

-- the files contracts already have
insert into public.contract_files (contract_id, file_name, storage_path, created_by, created_at)
select id, coalesce(file_name, code), file_path, created_by, created_at from public.contracts where file_path is not null;
