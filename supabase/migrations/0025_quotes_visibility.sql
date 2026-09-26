-- Quotes had zero row-scoping — anyone with any crm_quotes permission could
-- see every quote for every deal, completely bypassing the deal/customer
-- row-scoping added earlier. A quote has no assignment of its own; it
-- inherits visibility from its parent deal (deals.assigned_to is kept in
-- sync with the deal's lead and customer by the cascade trigger, so this
-- one check covers "quotes for deals, leads, or customers not assigned to
-- me" in one shot).
drop policy quotes_select on public.quotes;
create policy quotes_select on public.quotes
  for select
  using (
    exists (
      select 1 from public.deals d
      where d.id = quotes.deal_id
        and public.has_any_module_permission('crm_quotes')
        and (
          public.has_permission('crm_deals', 'view_all')
          or d.assigned_to = auth.uid()
          or d.created_by = auth.uid()
        )
    )
  );

drop policy quotes_insert on public.quotes;
create policy quotes_insert on public.quotes
  for insert
  with check (
    exists (
      select 1 from public.deals d
      where d.id = quotes.deal_id
        and public.has_permission('crm_quotes', 'create')
        and (
          public.has_permission('crm_deals', 'view_all')
          or d.assigned_to = auth.uid()
          or d.created_by = auth.uid()
        )
    )
  );

drop policy quotes_update on public.quotes;
create policy quotes_update on public.quotes
  for update
  using (
    exists (
      select 1 from public.deals d
      where d.id = quotes.deal_id
        and public.has_permission('crm_quotes', 'edit')
        and (
          public.has_permission('crm_deals', 'view_all')
          or d.assigned_to = auth.uid()
          or d.created_by = auth.uid()
        )
    )
  );

drop policy quotes_delete on public.quotes;
create policy quotes_delete on public.quotes
  for delete
  using (
    exists (
      select 1 from public.deals d
      where d.id = quotes.deal_id
        and public.has_permission('crm_quotes', 'delete')
        and (
          public.has_permission('crm_deals', 'view_all')
          or d.assigned_to = auth.uid()
          or d.created_by = auth.uid()
        )
    )
  );

-- quote_items follow their parent quote the same way quotes follow their
-- parent deal.
drop policy quote_items_select on public.quote_items;
create policy quote_items_select on public.quote_items
  for select
  using (
    exists (
      select 1 from public.quotes q
      join public.deals d on d.id = q.deal_id
      where q.id = quote_items.quote_id
        and public.has_any_module_permission('crm_quotes')
        and (
          public.has_permission('crm_deals', 'view_all')
          or d.assigned_to = auth.uid()
          or d.created_by = auth.uid()
        )
    )
  );

drop policy quote_items_insert on public.quote_items;
create policy quote_items_insert on public.quote_items
  for insert
  with check (
    exists (
      select 1 from public.quotes q
      join public.deals d on d.id = q.deal_id
      where q.id = quote_items.quote_id
        and public.has_permission('crm_quotes', 'edit')
        and (
          public.has_permission('crm_deals', 'view_all')
          or d.assigned_to = auth.uid()
          or d.created_by = auth.uid()
        )
    )
  );

drop policy quote_items_update on public.quote_items;
create policy quote_items_update on public.quote_items
  for update
  using (
    exists (
      select 1 from public.quotes q
      join public.deals d on d.id = q.deal_id
      where q.id = quote_items.quote_id
        and public.has_permission('crm_quotes', 'edit')
        and (
          public.has_permission('crm_deals', 'view_all')
          or d.assigned_to = auth.uid()
          or d.created_by = auth.uid()
        )
    )
  );

drop policy quote_items_delete on public.quote_items;
create policy quote_items_delete on public.quote_items
  for delete
  using (
    exists (
      select 1 from public.quotes q
      join public.deals d on d.id = q.deal_id
      where q.id = quote_items.quote_id
        and public.has_permission('crm_quotes', 'edit')
        and (
          public.has_permission('crm_deals', 'view_all')
          or d.assigned_to = auth.uid()
          or d.created_by = auth.uid()
        )
    )
  );
