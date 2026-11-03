-- Tasks: anyone can create a task for themselves or for any other active user. A task has a
-- title, a note, a priority, a deadline, an optional customer, and moves through three
-- statuses: to do, in progress, done. People see the tasks they created or that were given to
-- them; "view all" (a permission on the tasks resource, and admins) sees everyone's.
create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null check (length(trim(title)) > 0),
  note text,
  priority text not null default 'medium' check (priority in ('low', 'medium', 'high', 'urgent')),
  status text not null default 'todo' check (status in ('todo', 'in_progress', 'done')),
  deadline timestamptz,
  customer_id uuid references public.customers (id) on delete set null,
  assigned_to uuid not null references public.profiles (id) on delete cascade,
  created_by uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index tasks_assigned on public.tasks (assigned_to, status);
create index tasks_created on public.tasks (created_by);
create index tasks_customer on public.tasks (customer_id);

alter table public.tasks enable row level security;

create policy tasks_select on public.tasks
  for select using (
    created_by = auth.uid()
    or assigned_to = auth.uid()
    or public.has_permission('tasks', 'view_all')
  );
create policy tasks_insert on public.tasks
  for insert with check (
    created_by = auth.uid()
    and exists (select 1 from public.profiles p where p.id = assigned_to and p.is_active)
  );
create policy tasks_update on public.tasks
  for update
  using (
    created_by = auth.uid()
    or assigned_to = auth.uid()
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin)
  )
  with check (
    created_by = auth.uid()
    or assigned_to = auth.uid()
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin)
  );
create policy tasks_delete on public.tasks
  for delete using (
    created_by = auth.uid()
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin)
  );

-- Keeps the times: when it was last changed, and when it was finished.
create or replace function public.tasks_touch()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  if new.status = 'done' and (tg_op = 'INSERT' or old.status is distinct from 'done') then
    new.completed_at := now();
  elsif new.status <> 'done' then
    new.completed_at := null;
  end if;
  return new;
end;
$$;
create trigger tasks_touch before insert or update on public.tasks
  for each row execute function public.tasks_touch();

-- Notifications: the person a task is given to, and the person who gave it when it is done.
alter table public.notifications drop constraint notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in (
    'deal_assigned', 'lead_assigned', 'activity_scheduled', 'activity_reminder',
    'deal_unassigned', 'deals_unassigned', 'visit_pending', 'visit_update',
    'work_stage_changed', 'work_request_created', 'work_assigned', 'work_request_withdrawn',
    'work_request_done', 'task_assigned', 'task_done'
  ));

create or replace function public.notify_task_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_params jsonb;
begin
  v_params := jsonb_build_object(
    'task_id', new.id,
    'name', new.title,
    'priority', new.priority,
    'deadline', new.deadline,
    'by', auth.uid()
  );
  -- given to someone else (on creation, or when handed over)
  if (tg_op = 'INSERT' or new.assigned_to is distinct from old.assigned_to)
     and new.assigned_to is distinct from auth.uid() then
    perform public.notify_user(new.assigned_to, 'task_assigned', v_params);
  end if;
  -- finished by someone other than the person who created it
  if tg_op = 'UPDATE' and new.status = 'done' and old.status is distinct from 'done'
     and new.created_by is distinct from auth.uid() then
    perform public.notify_user(new.created_by, 'task_done', v_params);
  end if;
  return new;
end;
$$;
create trigger tasks_notify after insert or update on public.tasks
  for each row execute function public.notify_task_changes();
