-- Daily cap on "Ask AI" questions (Pro feature): 25 questions per signed-in
-- user per UTC calendar day. Enforced server-side in the ask-ai Edge
-- Function (via increment_ai_usage) so it can't be bypassed by reinstalling
-- the app or clearing local data.
--
-- Safe to run now: paste into the Supabase SQL editor and run.

create table if not exists public.ai_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  day     date not null default (now() at time zone 'utc')::date,
  count   int  not null default 0,
  primary key (user_id, day)
);

alter table public.ai_usage enable row level security;
-- No client-facing policies — only the service-role Edge Function (via the
-- security-definer RPC below) ever touches this table.

-- Atomically bumps today's count for a user and returns the new total, so
-- the caller can compare it against the daily cap in one round trip.
create or replace function public.increment_ai_usage(p_uid uuid)
returns int
language plpgsql volatile security definer set search_path = public as $$
declare
  v_count int;
begin
  insert into public.ai_usage (user_id, day, count)
  values (p_uid, (now() at time zone 'utc')::date, 1)
  on conflict (user_id, day) do update
    set count = public.ai_usage.count + 1
  returning count into v_count;
  return v_count;
end;
$$;

-- Only the Edge Function (calling with the service-role key) should invoke
-- this — never directly from the app, or a player could inflate their own
-- (or someone else's) usage count.
revoke execute on function public.increment_ai_usage(uuid) from anon, authenticated;
grant  execute on function public.increment_ai_usage(uuid) to service_role;
