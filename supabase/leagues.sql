-- ============================================================================
-- Cortex — real weekly leagues, sharded into rooms of at most 30 players.
-- Run in the Supabase SQL editor (after schema.sql). Idempotent.
--
-- Rules implemented here:
--   • Leagues are between REAL players (no bots).
--   • Each league room holds at most 30 players.
--   • When a room for a given (week, kind) fills up, the next player starts a
--     NEW room of the same kind.
--   • Each player is in exactly ONE league per week — enforced by the
--     primary key (week, player_id).
-- "kind" is the player's skill tier (e.g. "Medical Student"), so players only
-- compete within their own tier.
-- ============================================================================

create table if not exists public.league_members (
  week       int  not null,
  kind       text not null,
  room       int  not null,
  player_id  uuid not null,
  username   text not null,
  weekly_xp  int  not null default 0,
  total_xp   int  not null default 0,
  trophies   int  not null default 0,
  joined_at  timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (week, player_id)               -- one league per player per week
);
create index if not exists league_room_idx on public.league_members (week, kind, room);

alter table public.league_members enable row level security;  -- RPC-only access

-- Join (or update) the caller's league for the week. Assigns the first room of
-- the same (week, kind) that has < 30 members, or starts a new room when they're
-- all full. Keeps the player in their original room once joined. Returns the
-- room number. Requires a signed-in player.
create or replace function public.report_league(
  p_week int, p_kind text, p_weekly_xp int, p_total_xp int, p_trophies int, p_username text
) returns int
language plpgsql volatile security definer set search_path = public as $$
declare
  v_uid  uuid := auth.uid();
  v_room int;
  v_name text := left(coalesce(nullif(trim(p_username), ''), 'Anonymous'), 40);
begin
  if v_uid is null then return null; end if;

  -- Already in a league this week → just update the score, keep room & kind.
  select room into v_room from public.league_members where week = p_week and player_id = v_uid;
  if found then
    update public.league_members set
      weekly_xp = greatest(0, p_weekly_xp),
      total_xp  = greatest(0, p_total_xp),
      trophies  = greatest(0, p_trophies),
      username  = v_name,
      updated_at = now()
    where week = p_week and player_id = v_uid;
    return v_room;
  end if;

  -- Serialize room assignment per (week, kind) so two players can't both grab
  -- the last seat in a room.
  perform pg_advisory_xact_lock(hashtextextended(p_week::text || '|' || p_kind, 0));

  select t.room into v_room
  from (
    select room, count(*) AS c
    from public.league_members
    where week = p_week and kind = p_kind
    group by room
  ) t
  where t.c < 30
  order by t.room
  limit 1;

  if v_room is null then
    select coalesce(max(room), 0) + 1 into v_room
    from public.league_members where week = p_week and kind = p_kind;
  end if;

  insert into public.league_members (week, kind, room, player_id, username, weekly_xp, total_xp, trophies)
  values (p_week, p_kind, v_room, v_uid, v_name,
          greatest(0, p_weekly_xp), greatest(0, p_total_xp), greatest(0, p_trophies));
  return v_room;
end;
$$;
grant execute on function public.report_league(int, text, int, int, int, text) to authenticated;

-- The caller's league room for the week, ranked by weekly XP (ties: lifetime XP,
-- then who joined first). Returns only the ≤30 players in the caller's room.
create or replace function public.get_league(p_week int)
returns table (player_id uuid, username text, weekly_xp int, total_xp int, trophies int, rank bigint)
language sql stable security definer set search_path = public as $$
  with me as (
    select kind, room from public.league_members
    where week = p_week and player_id = auth.uid()
  )
  select m.player_id, m.username, m.weekly_xp, m.total_xp, m.trophies,
         row_number() over (order by m.weekly_xp desc, m.total_xp desc, m.joined_at asc) as rank
  from public.league_members m
  join me on m.kind = me.kind and m.room = me.room
  where m.week = p_week;
$$;
grant execute on function public.get_league(int) to authenticated;

notify pgrst, 'reload schema';
