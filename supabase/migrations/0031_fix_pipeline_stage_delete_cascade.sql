-- 0030's delete guard blocked ANY delete of a fixed stage row, including the
-- cascade delete that fires when the whole pipeline is removed — since every
-- pipeline always has its 4 fixed stages, that made "delete pipeline"
-- unusable. Only block a direct delete of the stage while its pipeline
-- still exists; once the parent pipeline itself is gone (mid cascade,
-- same transaction), let the cascade proceed.
create or replace function public.enforce_no_delete_system_stage()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.system_key is not null and exists (select 1 from public.pipelines where id = old.pipeline_id) then
    raise exception 'this stage is fixed and cannot be deleted';
  end if;
  return old;
end;
$$;
