-- "View leads" is now its own permission on CRM leads: it controls the Leads
-- tab and the leads list / profile pages. (The leads data itself stays readable
-- for the parts of the CRM that use it, e.g. a deal's lead.)
-- Roles that already have any leads permission keep seeing the tab.
insert into public.role_permissions (role_id, module, action)
select distinct rp.role_id, 'crm_leads', 'view'
from public.role_permissions rp
where rp.module = 'crm_leads'
on conflict do nothing;
