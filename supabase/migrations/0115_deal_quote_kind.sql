-- A deal's files are split into sections: the quote (عرض السعر), the contract
-- (العقد) and everything else. 'quote' joins 'contract' as a file kind.
alter table public.deal_attachments drop constraint if exists deal_attachments_kind_check;
alter table public.deal_attachments
  add constraint deal_attachments_kind_check check (kind is null or kind in ('contract', 'quote'));
