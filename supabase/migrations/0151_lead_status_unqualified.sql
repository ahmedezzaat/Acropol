-- Contacts (leads) now have two statuses a person chooses: new and unqualified. (Applied on its own: a new enum
-- value cannot be used in the same transaction that adds it. See 0152.)
alter type public.lead_status add value if not exists 'unqualified';
