create type public.lead_type as enum ('individual', 'company');

alter table public.leads
  add column lead_type public.lead_type not null default 'individual',
  add column phone2 text;

create type public.lead_source as enum (
  'facebook', 'instagram', 'meta', 'google', 'website', 'event', 'referral'
);

-- Existing free-text source values that don't match one of the fixed
-- options become null rather than failing the migration outright.
alter table public.leads
  alter column source type public.lead_source
  using (
    case
      when source in ('facebook', 'instagram', 'meta', 'google', 'website', 'event', 'referral')
      then source::public.lead_source
      else null
    end
  );
