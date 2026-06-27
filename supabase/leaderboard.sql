-- ============================================================================
-- Cortex global leaderboard (Supabase / Postgres)
-- Run this in the Supabase SQL editor once (after schema.sql).
--
-- Players are anonymous: each install generates a stable client UUID
-- (`player_id`) and reports its own username + lifetime XP. All access is
-- through SECURITY DEFINER RPCs, so the table itself is never exposed to
-- clients (same approach as register_device in schema.sql).
-- ============================================================================

create table if not exists public.leaderboard (
  player_id  uuid primary key,
  username   text not null,
  xp         int  not null default 0,
  updated_at timestamptz not null default now()
);

create index if not exists leaderboard_xp_idx on public.leaderboard (xp desc, updated_at asc);

-- Upsert THIS player's own score. Anyone may call it (no auth); a player can
-- only write the row whose UUID they hold.
create or replace function public.submit_score(p_player uuid, p_username text, p_xp int)
returns void language sql security definer set search_path = public as $$
  insert into public.leaderboard (player_id, username, xp, updated_at)
  values (
    p_player,
    left(coalesce(nullif(trim(p_username), ''), 'Anonymous'), 40),
    greatest(coalesce(p_xp, 0), 0),
    now()
  )
  on conflict (player_id) do update
    set username   = excluded.username,
        xp         = excluded.xp,
        updated_at = now();
$$;
grant execute on function public.submit_score(uuid, text, int) to anon, authenticated;

-- Global ranking: the top `p_limit` players, plus the caller's own row even if
-- they fall outside the top N (so users always see their position).
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

-- Lock the table down; access is only via the two RPCs above.
alter table public.leaderboard enable row level security;
