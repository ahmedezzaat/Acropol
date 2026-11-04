-- Files on a task. The person who gave the task and the person it was given to can both attach
-- files and download them; so can an admin, and people who can see every task (view only).
-- The files live in a private bucket, in a folder named after the task.

-- May the signed-in user work on this task's files (add them)? Giver, receiver, admin.
create or replace function public.task_can_attach(p_task uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.tasks t
    where t.id = p_task
      and (
        t.created_by = auth.uid()
        or t.assigned_to = auth.uid()
        or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin)
      )
  );
$$;

-- May they see and download them? The same, plus people who can see every task.
create or replace function public.task_can_view_files(p_task uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.task_can_attach(p_task) or (
    exists (select 1 from public.tasks t where t.id = p_task) and public.has_permission('tasks', 'view_all')
  );
$$;

-- The same checks from a storage path ("<task id>/<file>").
create or replace function public.task_file_can(p_path text, p_for_view boolean)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_task uuid;
begin
  begin
    v_task := split_part(p_path, '/', 1)::uuid;
  exception when others then
    return false;
  end;
  return case when p_for_view then public.task_can_view_files(v_task) else public.task_can_attach(v_task) end;
end;
$$;
revoke all on function public.task_can_attach(uuid), public.task_can_view_files(uuid), public.task_file_can(text, boolean) from public, anon;
grant execute on function public.task_can_attach(uuid), public.task_can_view_files(uuid), public.task_file_can(text, boolean) to authenticated;

create table public.task_attachments (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks (id) on delete cascade,
  file_name text not null,
  storage_path text not null,
  uploaded_by uuid default auth.uid() references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);
create index task_attachments_task on public.task_attachments (task_id);

alter table public.task_attachments enable row level security;
create policy task_attachments_select on public.task_attachments
  for select using (public.task_can_view_files(task_id));
create policy task_attachments_insert on public.task_attachments
  for insert with check (public.task_can_attach(task_id));
-- removed by whoever uploaded it, the person who gave the task, or an admin
create policy task_attachments_delete on public.task_attachments
  for delete using (
    uploaded_by = auth.uid()
    or exists (select 1 from public.tasks t where t.id = task_attachments.task_id and t.created_by = auth.uid())
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin)
  );

insert into storage.buckets (id, name, public)
values ('task-attachments', 'task-attachments', false)
on conflict (id) do nothing;

create policy task_attachments_storage_select on storage.objects
  for select using (bucket_id = 'task-attachments' and public.task_file_can(name, true));
create policy task_attachments_storage_insert on storage.objects
  for insert with check (bucket_id = 'task-attachments' and public.task_file_can(name, false));
create policy task_attachments_storage_delete on storage.objects
  for delete using (
    bucket_id = 'task-attachments'
    and exists (
      select 1 from public.task_attachments a
      where a.storage_path = storage.objects.name
        and (
          a.uploaded_by = auth.uid()
          or exists (select 1 from public.tasks t where t.id = a.task_id and t.created_by = auth.uid())
          or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin)
        )
    )
  );
