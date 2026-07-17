-- ============================================================================
-- Cortex — COMPLETE database setup (single file).
-- Run this once in the Supabase SQL editor for a fresh project. Every statement
-- is idempotent, so it's safe to re-run after app updates.
--
-- This bundles, in the correct order:
--   1. schema.sql         — core tables, RLS, register_device
--   2. daily_kind.sql     — allow publishing "daily" cases
--   3. leaderboard.sql    — global leaderboard
--   4. server_grading.sql — answer-stripped feeds + server-side grading (locks
--                           the content/emergencies tables to anon)
--   5. profiles.sql       — per-account cloud-synced game state
--   6. leagues.sql        — real weekly leagues, rooms of <=30
--
-- NOT included here (do these manually — see SETUP.md):
--   • Adding your admin user id to public.admins
--   • The pg_cron job for emergency push (needs the Edge Function + your
--     service_role key — never commit that key)
-- ============================================================================



-- ############################################################################
-- ## schema.sql
-- ############################################################################

-- ============================================================================
-- Cortex backend schema (Supabase / Postgres)
-- Run this in the Supabase SQL editor once.
-- ============================================================================

create extension if not exists pgcrypto;

-- APNs device tokens of every install (so the server can push to all users).
-- `timezone` is the device's IANA zone (e.g. "Asia/Kolkata") used to fire
-- emergencies at each user's local time.
create table if not exists public.devices (
  id          uuid primary key default gen_random_uuid(),
  apns_token  text unique not null,
  timezone    text,
  created_at  timestamptz not null default now()
);

-- Upsert a device + its timezone without exposing the table to clients.
-- Only accept a timezone that Postgres recognises as a real IANA zone; any other
-- value (a malformed or malicious client string) is stored as NULL so it can
-- never reach the emergency sender. Tokens are validated as non-empty too.
create or replace function public.register_device(p_token text, p_timezone text)
returns void language sql security definer set search_path = public as $$
  insert into public.devices (apns_token, timezone)
  select
    p_token,
    (select name from pg_timezone_names where name = p_timezone)
  where coalesce(nullif(trim(p_token), ''), '') <> ''
  on conflict (apns_token) do update set timezone = excluded.timezone;
$$;
grant execute on function public.register_device(text, text) to anon, authenticated;

-- Published questions. `payload` is one item in the app's import JSON format
-- (MCQ / clinical case / mastery condition). See the app's Bulk Import screen.
create table if not exists public.content (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null check (kind in ('mcq','clinical','mastery')),
  payload     jsonb not null,
  created_at  timestamptz not null default now()
);

-- Scheduled emergency cases. `payload` is a single clinical-case object.
-- The alert fires at `local_hour:local_minute` on `send_date` *in each user's
-- own timezone*, so 8 PM means 8 PM local for everyone.
create table if not exists public.emergencies (
  id           uuid primary key default gen_random_uuid(),
  payload      jsonb not null,
  send_date    date not null,
  local_hour   int  not null,
  local_minute int  not null,
  created_at   timestamptz not null default now()
);

-- One row per (emergency, timezone) once delivered, so each zone fires once.
create table if not exists public.emergency_sends (
  emergency_id uuid not null references public.emergencies(id) on delete cascade,
  timezone     text not null,
  sent_at      timestamptz not null default now(),
  primary key (emergency_id, timezone)
);
alter table public.emergency_sends enable row level security;  -- service-role only

-- Who is allowed to publish content / broadcast emergencies.
-- After creating your admin auth user, insert its id here (see README).
create table if not exists public.admins (
  id uuid primary key references auth.users(id) on delete cascade
);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.devices     enable row level security;
alter table public.content     enable row level security;
alter table public.emergencies enable row level security;
alter table public.admins      enable row level security;

-- Anyone may register their device token (insert only; tokens are never read by clients).
drop policy if exists "register device" on public.devices;
create policy "register device" on public.devices
  for insert to anon, authenticated with check (true);

-- Content is world-readable; only admins may write.
drop policy if exists "read content" on public.content;
create policy "read content" on public.content
  for select to anon, authenticated using (true);

drop policy if exists "admin write content" on public.content;
create policy "admin write content" on public.content
  for all to authenticated
  using (exists (select 1 from public.admins a where a.id = auth.uid()))
  with check (exists (select 1 from public.admins a where a.id = auth.uid()));

-- Emergencies are world-readable (clients fetch the case after a push); admins write.
drop policy if exists "read emergencies" on public.emergencies;
create policy "read emergencies" on public.emergencies
  for select to anon, authenticated using (true);

drop policy if exists "admin write emergencies" on public.emergencies;
create policy "admin write emergencies" on public.emergencies
  for all to authenticated
  using (exists (select 1 from public.admins a where a.id = auth.uid()))
  with check (exists (select 1 from public.admins a where a.id = auth.uid()));

-- Admins table: a signed-in user may check whether they themselves are an admin.
drop policy if exists "self admin read" on public.admins;
create policy "self admin read" on public.admins
  for select to authenticated using (id = auth.uid());


-- ############################################################################
-- ## daily_kind.sql
-- ############################################################################

-- ============================================================================
-- Allow publishing "daily" cases through the content table.
-- Run this in the Supabase SQL editor once (after schema.sql) if you intend to
-- PUBLISH daily cases to all users. Local bulk-import needs no server change.
-- ============================================================================

alter table public.content drop constraint if exists content_kind_check;
alter table public.content
  add constraint content_kind_check
  check (kind in ('mcq', 'clinical', 'mastery', 'daily'));


-- ############################################################################
-- ## leaderboard.sql
-- ############################################################################

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
--
-- Hardening (this is an anonymous, client-reported leaderboard, so it can never
-- be fully cheat-proof, but we limit the damage):
--   • XP is clamped to [0, 100_000_000] so a single call can't inject an absurd
--     value or a negative.
--   • Username is trimmed and capped at 40 chars (and defaulted to 'Anonymous').
--   • On conflict the stored XP only ever moves UP (greatest of old/new), so a
--     known UUID can't be griefed downward, only legitimately increased.
-- For true anti-cheat, move scoring server-side and require authenticated users.
create or replace function public.submit_score(p_player uuid, p_username text, p_xp int)
returns void language sql security definer set search_path = public as $$
  insert into public.leaderboard (player_id, username, xp, updated_at)
  values (
    p_player,
    left(coalesce(nullif(trim(p_username), ''), 'Anonymous'), 40),
    least(greatest(coalesce(p_xp, 0), 0), 100000000),
    now()
  )
  on conflict (player_id) do update
    set username   = left(coalesce(nullif(trim(excluded.username), ''), 'Anonymous'), 40),
        xp         = greatest(public.leaderboard.xp, excluded.xp),
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


-- ############################################################################
-- ## server_grading.sql
-- ############################################################################

-- ============================================================================
-- Cortex — hide answers / grade on the server.
-- Run this in the Supabase SQL editor AFTER schema.sql + leaderboard.sql.
-- Every statement is idempotent.
--
-- Why: the case payload contains the answer key (diagnoses[].correct,
-- tests[].helpful, treatments[].appropriate, their per-option rationale/tag,
-- and the outcome/mentor text). If
-- clients can read the table, they can read every answer. After this migration:
--   • the content/emergencies tables are NOT readable by anon at all;
--   • clients fetch questions through get_cases() / get_emergencies(), which
--     return the payload with the answer key STRIPPED OUT;
--   • the score is computed by grade_case() on the server from the stored
--     answers; the full answer is only returned in response to a graded attempt.
-- ============================================================================

-- 1a) Remove the answer key from a single case object (order of options is
--     preserved, so the client can refer to picks by array index).
create or replace function public.strip_case(p jsonb)
returns jsonb language sql immutable as $$
  select (p - 'outcomeTitle' - 'outcomeBody' - 'mentorInsight')
    || jsonb_build_object(
      'diagnoses', coalesce(
        (select jsonb_agg(e - 'correct' - 'rationale' - 'tag') from jsonb_array_elements(p->'diagnoses') e), '[]'::jsonb),
      'tests', coalesce(
        (select jsonb_agg(e - 'helpful' - 'rationale' - 'tag') from jsonb_array_elements(p->'tests') e), '[]'::jsonb),
      'treatments', coalesce(
        (select jsonb_agg(e - 'appropriate' - 'rationale' - 'tag') from jsonb_array_elements(p->'treatments') e), '[]'::jsonb)
    );
$$;

-- 1b) Wrapper-aware strip: daily payloads nest the case under "case"
--     ({date, case:{...}}); clinical/emergency payloads ARE the case.
create or replace function public.strip_answers(p jsonb)
returns jsonb language sql immutable as $$
  select case
    when p ? 'case' then jsonb_set(p, '{case}', public.strip_case(p->'case'))
    else public.strip_case(p)
  end;
$$;

-- 2) Question feeds (answers stripped). SECURITY DEFINER so they work even
--    though anon can no longer read the tables directly.
create or replace function public.get_cases()
returns table (id uuid, kind text, payload jsonb)
language sql stable security definer set search_path = public as $$
  select c.id, c.kind, public.strip_answers(c.payload)
  from public.content c
  order by c.created_at asc;
$$;
grant execute on function public.get_cases() to anon, authenticated;

create or replace function public.get_emergencies()
returns table (id uuid, payload jsonb, send_date date, local_hour int, local_minute int)
language sql stable security definer set search_path = public as $$
  select e.id, public.strip_answers(e.payload), e.send_date, e.local_hour, e.local_minute
  from public.emergencies e
  order by e.send_date desc;
$$;
grant execute on function public.get_emergencies() to anon, authenticated;

create or replace function public.get_emergency(p_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select public.strip_answers(payload) from public.emergencies where id = p_id;
$$;
grant execute on function public.get_emergency(uuid) to anon, authenticated;

-- 3) Per-user attempt log. Ties each graded attempt to an authenticated player
--    so grading can be rate-limited and abuse detected. RPC-only (no client RLS).
create table if not exists public.case_attempts (
  user_id  uuid not null,
  source   text not null,
  case_id  uuid not null,
  attempts int  not null default 1,
  first_at timestamptz not null default now(),
  last_at  timestamptz not null default now(),
  primary key (user_id, source, case_id)
);
alter table public.case_attempts enable row level security;
create index if not exists case_attempts_user_time_idx
  on public.case_attempts (user_id, last_at desc);

-- 3b) Grade an attempt on the server. The client sends the ARRAY INDICES of the
--     options it picked; the server reads the true answers from storage, scores
--     the attempt (same formula as the app), and returns the score plus the full
--     case so the outcome screen can reveal the answer AFTER the attempt.
--       diagnosis 60% · helpful tests 20% · appropriate treatments 20%,
--       with a 0.25 penalty per wasteful test/treatment.
--
--     Grading REQUIRES an authenticated player (so anonymous scripts can't
--     scrape answers one case at a time) and is rate-limited per user, which
--     closes the "grade every case once to harvest the bank" hole.
drop function if exists public.grade_case(text, uuid, int[], int, int[]);
create or replace function public.grade_case(
  p_source     text,
  p_id         uuid,
  p_test_idx   int[]  default '{}',
  p_dx_idx     int    default null,
  p_tx_idx     int[]  default '{}',
  p_dx_name    text   default null,
  p_test_names text[] default null,
  p_tx_names   text[] default null
) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_uid       uuid := auth.uid();
  v_recent    int;
  pay         jsonb;
  diagnoses   jsonb;
  tests       jsonb;
  treatments  jsonb;
  dx_ok       boolean := false;
  h_total int; h_good int; h_bad int;
  a_total int; a_good int; a_bad int;
  tests_score numeric := 0;
  tx_score    numeric := 0;
  score       numeric := 0;
  xp_reward   int;
begin
  -- Must be a signed-in player.
  if v_uid is null then
    return jsonb_build_object('error', 'auth required');
  end if;
  -- Rate limit: at most 120 graded cases per user per rolling hour.
  select count(*) into v_recent from public.case_attempts
    where user_id = v_uid and last_at > now() - interval '1 hour';
  if v_recent >= 120 then
    return jsonb_build_object('error', 'rate limited');
  end if;

  if p_source = 'emergency' then
    select payload into pay from public.emergencies where id = p_id;
  else
    select payload into pay from public.content where id = p_id;
  end if;
  if pay is null then
    return jsonb_build_object('error', 'not found');
  end if;
  -- Daily rows wrap the case under "case" ({date, case:{...}}); unwrap it.
  if pay ? 'case' then
    pay := pay->'case';
  end if;

  diagnoses  := coalesce(pay->'diagnoses',  '[]'::jsonb);
  tests      := coalesce(pay->'tests',       '[]'::jsonb);
  treatments := coalesce(pay->'treatments',  '[]'::jsonb);
  xp_reward  := coalesce((pay->>'xpReward')::int, 20);

  -- Diagnosis — 60%. Prefer name match (robust to reordering); else index.
  if p_dx_name is not null then
    dx_ok := exists (
      select 1 from jsonb_array_elements(diagnoses) d
      where lower(btrim(d->>'name')) = lower(btrim(p_dx_name))
        and coalesce((d->>'correct')::boolean, false));
  elsif p_dx_idx is not null and p_dx_idx >= 0 and p_dx_idx < jsonb_array_length(diagnoses) then
    dx_ok := coalesce((diagnoses->p_dx_idx->>'correct')::boolean, false);
  end if;

  -- Tests — up to 20%.
  h_total := (select count(*) from jsonb_array_elements(tests) t
              where coalesce((t->>'helpful')::boolean, false));
  if p_test_names is not null then
    h_good := (select count(*) from jsonb_array_elements(tests) t
               where lower(btrim(t->>'name')) = any (select lower(btrim(x)) from unnest(p_test_names) x)
                 and coalesce((t->>'helpful')::boolean, false));
    h_bad  := (select count(*) from jsonb_array_elements(tests) t
               where lower(btrim(t->>'name')) = any (select lower(btrim(x)) from unnest(p_test_names) x)
                 and not coalesce((t->>'helpful')::boolean, false));
  else
    h_good := (select count(*) from unnest(p_test_idx) i
               where i >= 0 and i < jsonb_array_length(tests)
                 and coalesce((tests->i->>'helpful')::boolean, false));
    h_bad  := (select count(*) from unnest(p_test_idx) i
               where i >= 0 and i < jsonb_array_length(tests)
                 and not coalesce((tests->i->>'helpful')::boolean, false));
  end if;
  if h_total > 0 then
    tests_score := greatest(0, h_good::numeric / h_total - 0.25 * h_bad) * 0.20;
  end if;

  -- Treatments — up to 20%.
  a_total := (select count(*) from jsonb_array_elements(treatments) t
              where coalesce((t->>'appropriate')::boolean, false));
  if p_tx_names is not null then
    a_good := (select count(*) from jsonb_array_elements(treatments) t
               where lower(btrim(t->>'name')) = any (select lower(btrim(x)) from unnest(p_tx_names) x)
                 and coalesce((t->>'appropriate')::boolean, false));
    a_bad  := (select count(*) from jsonb_array_elements(treatments) t
               where lower(btrim(t->>'name')) = any (select lower(btrim(x)) from unnest(p_tx_names) x)
                 and not coalesce((t->>'appropriate')::boolean, false));
  else
    a_good := (select count(*) from unnest(p_tx_idx) i
               where i >= 0 and i < jsonb_array_length(treatments)
                 and coalesce((treatments->i->>'appropriate')::boolean, false));
    a_bad  := (select count(*) from unnest(p_tx_idx) i
               where i >= 0 and i < jsonb_array_length(treatments)
                 and not coalesce((treatments->i->>'appropriate')::boolean, false));
  end if;
  if a_total > 0 then
    tx_score := greatest(0, a_good::numeric / a_total - 0.25 * a_bad) * 0.20;
  end if;

  score := least(1.0, (case when dx_ok then 0.60 else 0 end) + tests_score + tx_score);

  -- Record the attempt (drives the rate limit + abuse detection).
  insert into public.case_attempts (user_id, source, case_id)
  values (v_uid, p_source, p_id)
  on conflict (user_id, source, case_id) do update
    set attempts = public.case_attempts.attempts + 1, last_at = now();

  return jsonb_build_object(
    'score',        score,
    'earned_xp',    round(score * 100),
    'earned_coins', round(score * xp_reward),
    'case',         pay     -- full payload (answers) — revealed only post-attempt
  );
end;
$$;
-- Only signed-in players may grade (anon callers get "auth required").
revoke execute on function public.grade_case(text, uuid, int[], int, int[], text, text[], text[]) from anon;
grant  execute on function public.grade_case(text, uuid, int[], int, int[], text, text[], text[]) to authenticated;

-- 4) Lock the tables: anon may no longer read raw rows (so the answer key can't
--    be scraped). Access is only through the stripped feeds + grade_case above.
--    Admin write policies (from schema.sql) are unchanged.
drop policy if exists "read content" on public.content;
drop policy if exists "read emergencies" on public.emergencies;

-- 5) Refresh PostgREST so the new RPCs are visible immediately.
notify pgrst, 'reload schema';


-- ############################################################################
-- ## profiles.sql
-- ############################################################################

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


-- ############################################################################
-- ## leagues.sql
-- ############################################################################

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

-- ============================================================================
-- Case images — the bucket a test's result image (ECG strip, X-ray, …) lives in.
-- Public to read (players fetch it straight from the result card); only an admin
-- may write, matching the content tables above.
-- ============================================================================
insert into storage.buckets (id, name, public)
values ('case-images', 'case-images', true)
on conflict (id) do update set public = true;

drop policy if exists "case images are public" on storage.objects;
create policy "case images are public"
  on storage.objects for select
  using (bucket_id = 'case-images');

drop policy if exists "admins write case images" on storage.objects;
create policy "admins write case images"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'case-images'
              and exists (select 1 from public.admins a where a.id = auth.uid()));

drop policy if exists "admins update case images" on storage.objects;
create policy "admins update case images"
  on storage.objects for update to authenticated
  using (bucket_id = 'case-images'
         and exists (select 1 from public.admins a where a.id = auth.uid()));

notify pgrst, 'reload schema';

