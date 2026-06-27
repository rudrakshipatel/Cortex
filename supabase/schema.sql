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
create or replace function public.register_device(p_token text, p_timezone text)
returns void language sql security definer set search_path = public as $$
  insert into public.devices (apns_token, timezone)
  values (p_token, p_timezone)
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
