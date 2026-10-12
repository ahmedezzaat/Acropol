-- Attachments of a deal can be marked as its contract. Winning a deal needs one
-- (the rule itself is in the next, separately applied migration).
alter table public.deal_attachments add column kind text check (kind is null or kind in ('contract'));
