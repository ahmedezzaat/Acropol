-- A product created without a stage starts in the FIRST stage of its funnel
-- (جديد for التركيبات). Previously only the app form chose it, so anything
-- else that inserted a product had to know the stage id.
create or replace function public.customer_product_check_stage()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();

  if tg_op = 'INSERT' and new.stage_id is null then
    select s.id into new.stage_id
    from public.cs_pipeline_stages s
    where s.pipeline_id = new.pipeline_id
    order by s.sort_order
    limit 1;
  end if;

  if not exists (select 1 from public.cs_pipeline_stages s where s.id = new.stage_id and s.pipeline_id = new.pipeline_id) then
    raise exception 'the stage does not belong to the product''s pipeline';
  end if;
  return new;
end;
$$;

-- The BEFORE trigger fills stage_id, but NOT NULL is checked afterwards, so the
-- column itself can stay required.
