-- ============================================================================
-- Cortex — one-shot DB upgrade. Run this ONCE in the Supabase SQL editor to
-- bring an existing project fully in sync with the current app. Safe to re-run
-- (every statement is idempotent).
-- ============================================================================

-- ── 1. Per-timezone emergency scheduling ───────────────────────────────────
-- Adds the columns the app writes when broadcasting an emergency. (Fixes:
-- "Could not find the 'local_hour' column of 'emergencies' in the schema cache".)
alter table public.devices     add column if not exists timezone text;
alter table public.emergencies add column if not exists send_date    date;
alter table public.emergencies add column if not exists local_hour   int;
alter table public.emergencies add column if not exists local_minute int;
alter table public.emergencies drop column if exists send_at;
alter table public.emergencies drop column if exists sent;

-- ── 2. Allow publishing "daily" cases ──────────────────────────────────────
alter table public.content drop constraint if exists content_kind_check;
alter table public.content
  add constraint content_kind_check
  check (kind in ('mcq', 'clinical', 'mastery', 'daily'));

-- ── 3. Global leaderboard ───────────────────────────────────────────────────
create table if not exists public.leaderboard (
  player_id  uuid primary key,
  username   text not null,
  xp         int  not null default 0,
  updated_at timestamptz not null default now()
);
create index if not exists leaderboard_xp_idx on public.leaderboard (xp desc, updated_at asc);

create or replace function public.submit_score(p_player uuid, p_username text, p_xp int)
returns void language sql security definer set search_path = public as $$
  insert into public.leaderboard (player_id, username, xp, updated_at)
  values (p_player, left(coalesce(nullif(trim(p_username), ''), 'Anonymous'), 40),
          greatest(coalesce(p_xp, 0), 0), now())
  on conflict (player_id) do update
    set username = excluded.username, xp = excluded.xp, updated_at = now();
$$;
grant execute on function public.submit_score(uuid, text, int) to anon, authenticated;

create or replace function public.get_leaderboard(p_player uuid, p_limit int default 50)
returns table (rank bigint, player_id uuid, username text, xp int)
language sql stable security definer set search_path = public as $$
  with ranked as (
    select l.player_id, l.username, l.xp,
           row_number() over (order by l.xp desc, l.updated_at asc) as rn
    from public.leaderboard l
  )
  select rn as rank, player_id, username, xp from ranked where rn <= greatest(p_limit, 1)
  union
  select rn as rank, player_id, username, xp from ranked where player_id = p_player
  order by rank;
$$;
grant execute on function public.get_leaderboard(uuid, int) to anon, authenticated;

alter table public.leaderboard enable row level security;

-- ── 4. Refresh PostgREST's schema cache (so new columns are visible now) ─────
notify pgrst, 'reload schema';
