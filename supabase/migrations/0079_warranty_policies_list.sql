-- A category can have several warranty policies (each product of the category
-- uses one of them): a list of {name, text}. The single warranty_policy text from
-- the previous migration becomes the first entry.
alter table public.product_categories
  add column warranty_policies jsonb not null default '[]'::jsonb;

update public.product_categories
set warranty_policies = jsonb_build_array(jsonb_build_object('name', 'الضمان', 'text', warranty_policy))
where nullif(btrim(coalesce(warranty_policy, '')), '') is not null;

alter table public.product_categories drop column warranty_policy;
