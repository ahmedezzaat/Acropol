-- A funnel stage can require the date to be typed in by the user instead of
-- being proposed as today (e.g. the actual operation date for تم التشغيل).
alter table public.cs_pipeline_stages
  add column require_date boolean not null default false;

update public.cs_pipeline_stages set require_date = true where name = 'تم التشغيل';
