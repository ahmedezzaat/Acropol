-- A new lead source: leads that come from Odoo.
alter type public.lead_source add value if not exists 'odoo';
