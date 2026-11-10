-- Notes the WhatsApp assistants read about each product category (what it is, who it suits, prices the team may
-- quote, typical questions and answers...). Written in Admin -> Product categories.
alter table public.product_categories add column if not exists ai_notes text;
comment on column public.product_categories.ai_notes is 'Free text the WhatsApp assistants use to answer questions about this category';
