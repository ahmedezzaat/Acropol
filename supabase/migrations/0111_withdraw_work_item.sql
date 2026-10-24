-- Whoever sent a deal to a board (and can edit deals) can take it back, which removes
-- the item from that board.
drop policy work_items_delete on public.work_items;
create policy work_items_delete on public.work_items
  for delete using (
    public.has_permission('crm_work', 'edit')
    or (created_by = auth.uid() and public.has_permission('crm_deals', 'edit'))
  );
