-- WhatsApp (WAHA) sales agent: learns from the existing chats, then answers customers and opens deals.
--  * waha_mode: off | draft (the agent writes a reply for a person to send) | auto (it sends by itself)
--  * playbook: what the agent learned (tone, common questions and the team's answers, the usual flow),
--    written by Claude from past chats and editable by hand
--  * wa_agent_notes: the per-chat notes the learning is built from (done a few chats at a time)
--  * ai_draft: the reply waiting for a person in the inbox

alter table public.whatsapp_ai_settings
  add column waha_mode text not null default 'off' check (waha_mode in ('off', 'draft', 'auto')),
  add column playbook text not null default '',
  add column playbook_built_at timestamptz,
  add column deal_pipeline_id uuid references public.pipelines (id) on delete set null,
  add column deal_stage_id uuid references public.pipeline_stages (id) on delete set null;

alter table public.whatsapp_conversations
  add column ai_draft text,
  add column ai_draft_at timestamptz,
  add column ai_deal_id uuid references public.deals (id) on delete set null;

create table public.wa_agent_notes (
  chat_id text primary key,
  notes text not null,
  messages integer not null default 0,
  created_at timestamptz not null default now()
);
alter table public.wa_agent_notes enable row level security;
create policy wa_agent_notes_select on public.wa_agent_notes for select
  using (public.has_permission('settings', 'whatsapp_ai'));
create policy wa_agent_notes_delete on public.wa_agent_notes for delete
  using (public.has_permission('settings', 'whatsapp_ai'));
