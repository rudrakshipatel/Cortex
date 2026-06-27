-- ============================================================================
-- Allow publishing "daily" cases through the content table.
-- Run this in the Supabase SQL editor once (after schema.sql) if you intend to
-- PUBLISH daily cases to all users. Local bulk-import needs no server change.
-- ============================================================================

alter table public.content drop constraint if exists content_kind_check;
alter table public.content
  add constraint content_kind_check
  check (kind in ('mcq', 'clinical', 'mastery', 'daily'));
