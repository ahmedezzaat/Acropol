-- New lead source "External client" (عميل خارجي), listed first.
alter type public.lead_source add value if not exists 'external_client' before 'facebook';
