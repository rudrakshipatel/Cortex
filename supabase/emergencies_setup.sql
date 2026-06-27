-- ============================================================================
-- Cortex — Emergencies setup / repair.
-- Run once in Supabase → SQL Editor. Every statement is idempotent (safe to
-- re-run). This guarantees the table, the columns the app writes, the RLS
-- policies (world-readable, admin-writable), and the admins allow-list.
-- ============================================================================

-- 1) Admins allow-list — controls who can broadcast emergencies / publish content.
create table if not exists public.admins (
  id uuid primary key references auth.users(id) on delete cascade
);
alter table public.admins enable row level security;
drop policy if exists "self admin read" on public.admins;
create policy "self admin read" on public.admins
  for select to authenticated using (id = auth.uid());

-- 2) Emergencies table + the columns the app writes (send_date / local time).
create table if not exists public.emergencies (
  id           uuid primary key default gen_random_uuid(),
  payload      jsonb not null,
  send_date    date,
  local_hour   int,
  local_minute int,
  created_at   timestamptz not null default now()
);
alter table public.emergencies add column if not exists send_date    date;
alter table public.emergencies add column if not exists local_hour   int;
alter table public.emergencies add column if not exists local_minute int;

alter table public.emergencies enable row level security;

-- 3) RLS: anyone may READ (the player pulls active emergencies); only admins WRITE.
drop policy if exists "read emergencies" on public.emergencies;
create policy "read emergencies" on public.emergencies
  for select to anon, authenticated using (true);

drop policy if exists "admin write emergencies" on public.emergencies;
create policy "admin write emergencies" on public.emergencies
  for all to authenticated
  using      (exists (select 1 from public.admins a where a.id = auth.uid()))
  with check (exists (select 1 from public.admins a where a.id = auth.uid()));

-- 4) *** REQUIRED *** Register YOUR admin account so the admin app can broadcast.
--    a) Sign in ONCE in the CortexAdmin app (Cloud Sync) with your email/password.
--    b) In Supabase → Authentication → Users, copy the UUID of that user.
--    c) Uncomment the line below, paste the UUID, and run it:
--
-- insert into public.admins (id) values ('PASTE-YOUR-AUTH-USER-UUID-HERE')
--   on conflict (id) do nothing;

-- 5) Refresh PostgREST's schema cache so any new columns are visible immediately.
notify pgrst, 'reload schema';

-- ── Handy checks (optional) ──────────────────────────────────────────────────
-- Who are the admins?            select * from public.admins;
-- What emergencies are stored?   select id, send_date, local_hour, local_minute, created_at
--                                from public.emergencies order by created_at desc;
