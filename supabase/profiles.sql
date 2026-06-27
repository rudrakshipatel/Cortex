-- ============================================================================
-- Cortex — per-account game state (cloud-synced).
-- Run in the Supabase SQL editor. Idempotent.
--
-- Each signed-in player gets one row keyed by their auth user id. The whole
-- game state (XP, coins, streak, level, trophies, solved cases, …) is stored as
-- a JSON blob in `state`. RLS makes a player able to read/write ONLY their own
-- row, so accounts are fully isolated and progress follows the account across
-- devices. The client reads/writes it directly over PostgREST with the player's
-- token (no service role, no RPC needed).
-- ============================================================================

create table if not exists public.profiles (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  state      jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- A player may read and write only their own profile.
drop policy if exists "own profile" on public.profiles;
create policy "own profile" on public.profiles
  for all to authenticated
  using      (user_id = auth.uid())
  with check (user_id = auth.uid());

notify pgrst, 'reload schema';
