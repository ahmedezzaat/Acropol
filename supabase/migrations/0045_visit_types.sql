-- Admin-managed types for trip/inspection requests. Beyond the two original
-- types (مأمورية, معاينة — both tied to a deal) there is "جولة خارجية": an
-- outdoor round that is NOT tied to any deal or customer (e.g. a salesperson
-- canvassing an area full of prospective manufacturers). Each type says
-- whether a deal is required.
create table public.visit_types (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  name text not null,
  requires_deal boolean not null default true,
  icon text not null default 'i-lucide-map-pin',
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

alter table public.visit_types enable row level security;

create policy visit_types_select on public.visit_types
  for select
  using (public.has_any_module_permission('crm_visits'));

create policy visit_types_admin_all on public.visit_types
  for all
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

insert into public.visit_types (key, name, requires_deal, icon, sort_order) values
  ('field_trip', 'مأمورية', true, 'i-lucide-car', 1),
  ('inspection', 'معاينة', true, 'i-lucide-clipboard-check', 2),
  ('outdoor_round', 'جولة خارجية', false, 'i-lucide-footprints', 3);

-- Requests now point at a type, and the deal becomes optional.
alter table public.field_visits drop constraint field_visits_kind_check;
alter table public.field_visits
  add constraint field_visits_kind_fkey
  foreign key (kind) references public.visit_types (key) on update cascade on delete restrict;

alter table public.field_visits alter column deal_id drop not null;

-- A type that needs a deal must have one; a type that doesn't must not.
create or replace function public.field_visit_check_type()
returns trigger
language plpgsql
as $$
declare
  v_requires boolean;
begin
  select t.requires_deal into v_requires from public.visit_types t where t.key = new.kind;
  if v_requires and new.deal_id is null then
    raise exception 'this type of request needs a deal';
  end if;
  if not v_requires and new.deal_id is not null then
    raise exception 'this type of request is not tied to a deal';
  end if;
  return new;
end;
$$;

create trigger field_visits_check_type
  before insert or update of kind, deal_id on public.field_visits
  for each row execute function public.field_visit_check_type();

-- Inserting without a deal must pass RLS too (the old check demanded a visible deal).
drop policy field_visits_insert on public.field_visits;
create policy field_visits_insert on public.field_visits
  for insert
  with check (
    requested_by = auth.uid()
    and public.has_permission('crm_visits', 'create')
    and (deal_id is null or exists (select 1 from public.deals d where d.id = deal_id))
  );

-- Notifications name the deal's contact, or — with no deal — the address/area.
create or replace function public.field_visit_after_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_leader uuid := public.visit_leader_of(new.requested_by);
  v_user uuid;
  v_params jsonb := jsonb_build_object(
    'visit_id', new.id,
    'kind', new.kind,
    'name', coalesce(public.deal_display_name(new.deal_id), new.address),
    'visit_date', new.visit_date,
    'requested_by', new.requested_by
  );
begin
  insert into public.field_visit_events (visit_id, action, actor_id) values (new.id, 'submitted', new.requested_by);

  if new.status = 'pending_leader' then
    perform public.notify_user(v_leader, 'visit_pending', v_params || '{"step":"leader"}'::jsonb);
  else
    for v_user in select * from public.visit_final_approvers() loop
      if v_user <> new.requested_by then
        perform public.notify_user(v_user, 'visit_pending', v_params || '{"step":"final"}'::jsonb);
      end if;
    end loop;
  end if;
  return new;
end;
$$;

-- field_visit_action(): same as before, with the notification name made
-- null-safe for requests that have no deal.
do $$
declare
  v_src text;
begin
  select pg_get_functiondef('public.field_visit_action(uuid, text, text)'::regprocedure) into v_src;
  v_src := replace(
    v_src,
    $q$'name', public.deal_display_name(v.deal_id),$q$,
    $q$'name', coalesce(public.deal_display_name(v.deal_id), v.address),$q$
  );
  if v_src not like '%coalesce(public.deal_display_name(v.deal_id), v.address)%' then
    raise exception 'field_visit_action patch did not apply';
  end if;
  execute v_src;
end $$;
