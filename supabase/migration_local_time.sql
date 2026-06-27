-- ============================================================================
-- Migration: per-timezone emergency scheduling.
-- Run this ONCE if you already ran the original schema.sql.
-- (A fresh schema.sql already includes everything below.)
-- ============================================================================

-- Devices learn their timezone.
alter table public.devices add column if not exists timezone text;

create or replace function public.register_device(p_token text, p_timezone text)
returns void language sql security definer set search_path = public as $$
  insert into public.devices (apns_token, timezone)
  values (p_token, p_timezone)
  on conflict (apns_token) do update set timezone = excluded.timezone;
$$;
grant execute on function public.register_device(text, text) to anon, authenticated;

-- Emergencies move from a single absolute instant to local wall-clock + date.
alter table public.emergencies add column if not exists send_date    date;
alter table public.emergencies add column if not exists local_hour   int;
alter table public.emergencies add column if not exists local_minute int;
alter table public.emergencies drop column if exists send_at;
alter table public.emergencies drop column if exists sent;

-- Track delivery per timezone so each zone fires exactly once.
create table if not exists public.emergency_sends (
  emergency_id uuid not null references public.emergencies(id) on delete cascade,
  timezone     text not null,
  sent_at      timestamptz not null default now(),
  primary key (emergency_id, timezone)
);
alter table public.emergency_sends enable row level security;
