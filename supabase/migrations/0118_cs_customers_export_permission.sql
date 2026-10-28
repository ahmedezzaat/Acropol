-- Exporting the customers list to CSV is its own permission ("export" on cs_customers).
-- Roles that see every customer keep the export they had.
insert into public.role_permissions (role_id, module, action)
select distinct rp.role_id, 'cs_customers', 'export'
from public.role_permissions rp
where rp.module = 'cs_customers' and rp.action = 'view_all'
on conflict do nothing;
