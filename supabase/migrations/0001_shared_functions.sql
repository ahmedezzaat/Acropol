-- Generic "touch updated_at" trigger function, reused by every table that has
-- an updated_at column, so we don't repeat the same trigger body everywhere.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
