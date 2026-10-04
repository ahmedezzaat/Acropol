-- Inbound leads API (and the WhatsApp Cloud API webhook built on it).
--
-- Leads arriving from other software have no logged-in user, so:
--   * leads.created_by becomes nullable (nothing in the app reads it; RLS
--     simply never matches a null creator, so these leads are visible to
--     assignees, their team leaders and "view all" users, like any other),
--   * two new sources identify where they came from.
alter type public.lead_source add value if not exists 'whatsapp';
alter type public.lead_source add value if not exists 'api';

alter table public.leads alter column created_by drop not null;

-- API keys for external systems. Only a SHA-256 hash of the key is stored —
-- the full key is shown once, when it is created. Managed exclusively through
-- the admin server routes (service role); RLS is on with no policies, so no
-- browser client can read or write this table.
create table public.api_keys (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  key_prefix text not null,
  key_hash text not null unique,
  -- Optional: leads created with this key are assigned to this user.
  default_assignee_id uuid references public.profiles (id) on delete set null,
  is_active boolean not null default true,
  last_used_at timestamptz,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.api_keys enable row level security;

-- Same canonical-digits rule as app/utils/phone.ts (phoneDigits): strip "+"
-- or "00", and swap a leading local 0 for Egypt's 20, so "010...", "+2010..."
-- and "002010..." all compare equal.
create or replace function public.phone_digits(p text)
returns text
language sql
immutable
as $$
  select nullif(
    case
      when d like '+%' then substr(d, 2)
      when d like '00%' then substr(d, 3)
      when d like '0%' then '20' || substr(d, 2)
      else d
    end,
    ''
  )
  from (select regexp_replace(coalesce(p, ''), '[^0-9+]', '', 'g') as d) s
$$;

-- Creates a lead on behalf of an external system, unless the phone number
-- already belongs to a lead or customer — the same "don't duplicate, point at
-- the existing record" rule as creating one in the app. Returns
--   {"status":"created","id":...} or
--   {"status":"duplicate","entity":"lead"|"customer","id":...}.
-- An advisory lock per phone number makes two simultaneous messages from the
-- same person create exactly one lead.
create or replace function public.api_create_lead(
  p_name text,
  p_phone text,
  p_phone2 text,
  p_email text,
  p_source text,
  p_notes text,
  p_lead_type text,
  p_company_name text,
  p_assigned_to uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_digits text := public.phone_digits(p_phone);
  v_digits2 text := public.phone_digits(p_phone2);
  v_existing uuid;
  v_id uuid;
begin
  if v_digits is not null then
    perform pg_advisory_xact_lock(hashtext('lead-phone:' || v_digits));

    select l.id into v_existing from public.leads l
    where public.phone_digits(l.phone) = v_digits or public.phone_digits(l.phone2) = v_digits
    limit 1;
    if v_existing is not null then
      return jsonb_build_object('status', 'duplicate', 'entity', 'lead', 'id', v_existing);
    end if;

    select c.id into v_existing from public.customers c
    where public.phone_digits(c.phone) = v_digits
    limit 1;
    if v_existing is not null then
      return jsonb_build_object('status', 'duplicate', 'entity', 'customer', 'id', v_existing);
    end if;
  end if;

  -- The lead-assignment trigger would reject assigning to someone else
  -- without a logged-in user holding crm_leads:assign; this is the same
  -- transaction-local escape hatch the deal -> lead cascade uses.
  perform set_config('acropol.cascading_assignment', 'true', true);

  insert into public.leads (name, phone, phone2, email, source, notes, lead_type, company_name, assigned_to, created_by)
  values (
    p_name,
    case when v_digits is not null then '+' || v_digits end,
    case when v_digits2 is not null then '+' || v_digits2 end,
    p_email,
    p_source::public.lead_source,
    p_notes,
    coalesce(p_lead_type, 'individual')::public.lead_type,
    p_company_name,
    p_assigned_to,
    null
  )
  returning id into v_id;

  perform set_config('acropol.cascading_assignment', 'false', true);

  return jsonb_build_object('status', 'created', 'id', v_id);
end;
$$;

revoke all on function public.api_create_lead(text, text, text, text, text, text, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.api_create_lead(text, text, text, text, text, text, text, text, uuid)
  to service_role;
