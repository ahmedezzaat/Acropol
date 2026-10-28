-- The deal's proposal (quote) and contract files, in the customer's Customer Service
-- profile. Technicians and other Customer Service staff cannot open deals, so they
-- could not see these files. They now can, for the customers they may see, and only
-- these two kinds (the rest of a deal's files stay with the people who work the deal).

-- Can the signed-in user see this customer in Customer Service? The same rule as the
-- customers' own policy.
create or replace function public.cs_can_see_customer(p_customer uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.customers c
    where c.id = p_customer
      and (
        (
          public.has_any_module_permission('cs_customers')
          and (public.has_permission('cs_customers', 'view_all') or c.cs_agent_id = auth.uid() or c.created_by = auth.uid())
        )
        or (public.cs_maintenance_full() and not public.has_any_module_permission('cs_customers'))
        or public.cs_customer_has_visible_visit(c.id)
      )
  );
$$;
revoke all on function public.cs_can_see_customer(uuid) from public, anon;
grant execute on function public.cs_can_see_customer(uuid) to authenticated;

-- The customer's quote and contract files, with the deal each belongs to.
create or replace function public.cs_customer_deal_files(p_customer_id uuid)
returns table (id uuid, deal_id uuid, deal_title text, file_name text, storage_path text, kind text, uploaded_by uuid, created_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select a.id, a.deal_id, d.title, a.file_name, a.storage_path, a.kind, a.uploaded_by, a.created_at
  from public.deal_attachments a
  join public.deals d on d.id = a.deal_id
  where d.customer_id = p_customer_id
    and a.kind in ('quote', 'contract')
    and public.cs_can_see_customer(p_customer_id)
  order by a.created_at desc;
$$;
revoke all on function public.cs_customer_deal_files(uuid) from public, anon;
grant execute on function public.cs_customer_deal_files(uuid) to authenticated;

-- Opening one of those files (a signed link to the private storage object).
create or replace function public.cs_can_open_deal_file(p_path text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.deal_attachments a
    join public.deals d on d.id = a.deal_id
    where a.storage_path = p_path
      and a.kind in ('quote', 'contract')
      and d.customer_id is not null
      and public.cs_can_see_customer(d.customer_id)
  );
$$;
revoke all on function public.cs_can_open_deal_file(text) from public, anon;
grant execute on function public.cs_can_open_deal_file(text) to authenticated;

create policy deal_attachments_storage_select_cs on storage.objects
  for select
  using (bucket_id = 'deal-attachments' and public.cs_can_open_deal_file(storage.objects.name));
