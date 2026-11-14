-- Imported product notes ("البائع: … / الزيارات: … / تكلفة الزيارة: … / تاريخ الزيارة: … / ملاحظات: …") move from the
-- product card to the maintenance history: a note with a visit date becomes a done visit on that date (its cost as
-- the visit cost), one without becomes a note entry; the product's notes are then cleared.
create temp table moved as
select p.id as product_id, p.created_at, p.last_maintenance_on,
       substring(p.notes from 'تاريخ الزيارة: *([0-9]{1,2}/[0-9]{1,2}/[0-9]{4})') as visit_date,
       substring(p.notes from 'تكلفة الزيارة: *([^\n]+)') as cost_text,
       substring(p.notes from 'ملاحظات: *([^\n]+)') as remark,
       nullif(array_to_string(array(
         select l from unnest(string_to_array(p.notes, E'\n')) l
         where split_part(l, ':', 1) in ('البائع', 'الزيارات', 'الزيارة القادمة')), E'\n'), '') as extra
from customer_products p
where (p.notes like '%الزيارات:%' or p.notes like '%تكلفة الزيارة:%')
  -- only notes made of the imported lines
  and not exists (select 1 from unnest(string_to_array(p.notes, E'\n')) l
                  where split_part(l, ':', 1) not in ('البائع', 'الزيارات', 'الزيارة القادمة', 'تكلفة الزيارة', 'تاريخ الزيارة', 'ملاحظات'));

insert into product_maintenance_log (product_id, kind, happened_at, done_on, note, cost, visit_cost, created_by)
select product_id,
       case when visit_date is null then 'note' else 'done' end,
       coalesce(to_date(visit_date, 'DD/MM/YYYY')::timestamptz, created_at),
       to_date(visit_date, 'DD/MM/YYYY'),
       nullif(concat_ws(E'\n', remark, extra), ''),
       case when visit_date is null then null when cost_text ~ '^[0-9.]+$' then cost_text::numeric else 0 end,
       case when visit_date is null then null when cost_text ~ '^[0-9.]+$' then cost_text::numeric else 0 end,
       null
from moved;

-- the visit counts as the product's last maintenance when it is the latest one
update customer_products p
set last_maintenance_on = to_date(m.visit_date, 'DD/MM/YYYY')
from moved m
where p.id = m.product_id and m.visit_date is not null
  and (p.last_maintenance_on is null or p.last_maintenance_on < to_date(m.visit_date, 'DD/MM/YYYY'));

update customer_products p set notes = null from moved m where p.id = m.product_id;
