-- Who uploaded a deal file was never saved (none of the existing files has an uploader):
-- the column had no default and the app did not fill it in. From now on the database
-- records the signed-in user on every new file, with the upload time already kept in
-- created_at. Files uploaded before this stay without an uploader.
alter table public.deal_attachments
  alter column uploaded_by set default auth.uid();
