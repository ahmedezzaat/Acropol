-- Editing a logged maintenance visit. The log used to be append-only; now the
-- people who may record an entry of a kind may also correct it — but only its
-- note, cost, date (done visits) and technician (done visits), never what kind of
-- entry it is or which product it belongs to. The edit is stamped.
alter table public.product_maintenance_log
  add column edited_at timestamptz,
  add column edited_by uuid references public.profiles (id) on delete set null;

create policy product_maintenance_log_update on public.product_maintenance_log
  for update
  using (
    case kind
      when 'done' then public.has_permission('cs_maintenance', 'complete')
      when 'scheduled' then public.has_permission('cs_maintenance', 'schedule')
      when 'rescheduled' then public.has_permission('cs_maintenance', 'schedule')
      when 'confirmed' then public.has_permission('cs_maintenance', 'schedule')
      when 'assigned' then public.has_permission('cs_maintenance', 'schedule')
      when 'declined' then public.has_permission('cs_maintenance', 'cancel')
      when 'resumed' then public.has_permission('cs_maintenance', 'cancel')
      when 'cancelled' then public.has_permission('cs_maintenance', 'cancel')
      when 'note' then public.has_permission('cs_maintenance', 'note')
      else false
    end
  )
  with check (
    case kind
      when 'done' then public.has_permission('cs_maintenance', 'complete')
      when 'scheduled' then public.has_permission('cs_maintenance', 'schedule')
      when 'rescheduled' then public.has_permission('cs_maintenance', 'schedule')
      when 'confirmed' then public.has_permission('cs_maintenance', 'schedule')
      when 'assigned' then public.has_permission('cs_maintenance', 'schedule')
      when 'declined' then public.has_permission('cs_maintenance', 'cancel')
      when 'resumed' then public.has_permission('cs_maintenance', 'cancel')
      when 'cancelled' then public.has_permission('cs_maintenance', 'cancel')
      when 'note' then public.has_permission('cs_maintenance', 'note')
      else false
    end
  );

create or replace function public.product_maintenance_log_guard_update()
returns trigger
language plpgsql
as $$
begin
  -- Server-side jobs and scripts (no signed-in user) are not limited.
  if auth.uid() is null then
    return new;
  end if;

  if (to_jsonb(new) - array['note', 'cost', 'done_on', 'technician_id', 'edited_at', 'edited_by'])
     is distinct from (to_jsonb(old) - array['note', 'cost', 'done_on', 'technician_id', 'edited_at', 'edited_by']) then
    raise exception 'only the note, cost, date and technician of a maintenance entry can be edited';
  end if;

  if new.kind <> 'done' and (new.done_on is distinct from old.done_on or new.technician_id is distinct from old.technician_id) then
    raise exception 'only a done visit has a date and technician to edit';
  end if;

  new.edited_at := now();
  new.edited_by := auth.uid();
  return new;
end;
$$;

create trigger product_maintenance_log_guard_update
  before update on public.product_maintenance_log
  for each row execute function public.product_maintenance_log_guard_update();

-- Correcting the date of the visit that is the product's last maintenance moves
-- the product's "last maintenance" with it.
create or replace function public.product_maintenance_log_sync_last_done()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.kind = 'done' and new.done_on is distinct from old.done_on then
    update public.customer_products
    set last_maintenance_on = (
      select max(done_on) from public.product_maintenance_log where product_id = new.product_id and kind = 'done'
    )
    where id = new.product_id and last_maintenance_on = old.done_on;
  end if;
  return null;
end;
$$;

create trigger product_maintenance_log_sync_last_done
  after update on public.product_maintenance_log
  for each row execute function public.product_maintenance_log_sync_last_done();

-- The visit's own note and date can be corrected by whoever may record visits.
create policy maintenance_visits_update on public.maintenance_visits
  for update
  using (
    public.has_permission('cs_maintenance', 'schedule')
    or public.has_permission('cs_maintenance', 'complete')
    or public.has_permission('cs_maintenance', 'cancel')
  )
  with check (
    public.has_permission('cs_maintenance', 'schedule')
    or public.has_permission('cs_maintenance', 'complete')
    or public.has_permission('cs_maintenance', 'cancel')
  );

create or replace function public.maintenance_visits_guard_update()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() is null then
    return new;
  end if;
  if (to_jsonb(new) - array['note', 'visit_at']) is distinct from (to_jsonb(old) - array['note', 'visit_at']) then
    raise exception 'only the note and date of a visit can be edited';
  end if;
  return new;
end;
$$;

create trigger maintenance_visits_guard_update
  before update on public.maintenance_visits
  for each row execute function public.maintenance_visits_guard_update();
