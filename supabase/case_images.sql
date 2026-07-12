-- Storage bucket for investigation result images (ECG strips, X-rays, …).
--
-- The admin app uploads a JPEG here and stores the returned public URL on the
-- test (`imageURL`). Players read the image straight from the public URL, so
-- the bucket is world-readable but only admins may write to it.
--
-- Safe to run now: paste into the Supabase SQL editor and run.

-- 1. The bucket (public read).
insert into storage.buckets (id, name, public)
values ('case-images', 'case-images', true)
on conflict (id) do update set public = true;

-- 2. Anyone (including signed-out players) can read the images.
drop policy if exists "case-images public read" on storage.objects;
create policy "case-images public read" on storage.objects
  for select
  using (bucket_id = 'case-images');

-- 3. Only signed-in admins may upload / replace / delete.
drop policy if exists "case-images admin insert" on storage.objects;
create policy "case-images admin insert" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'case-images'
    and exists (select 1 from public.admins a where a.id = auth.uid())
  );

drop policy if exists "case-images admin update" on storage.objects;
create policy "case-images admin update" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'case-images'
    and exists (select 1 from public.admins a where a.id = auth.uid())
  );

drop policy if exists "case-images admin delete" on storage.objects;
create policy "case-images admin delete" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'case-images'
    and exists (select 1 from public.admins a where a.id = auth.uid())
  );
