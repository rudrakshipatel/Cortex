-- Migration: grade cases by option NAME (robust to editing / reordering).
--
-- The old grade_case scored the attempt by array INDEX, which silently breaks
-- whenever a case is edited or reordered after a player has loaded it (the
-- player's index no longer lines up with the stored payload). This version
-- matches the picked diagnosis / tests / treatments by NAME, so a correct pick
-- always scores correctly regardless of order. It stays backward-compatible:
-- older app builds that send only indices still work (name params default null).
--
-- Safe to run now: paste into the Supabase SQL editor and run.

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
  if v_uid is null then return jsonb_build_object('error', 'auth required'); end if;
  select count(*) into v_recent from public.case_attempts
    where user_id = v_uid and last_at > now() - interval '1 hour';
  if v_recent >= 120 then return jsonb_build_object('error', 'rate limited'); end if;

  if p_source = 'emergency' then
    select payload into pay from public.emergencies where id = p_id;
  else
    select payload into pay from public.content where id = p_id;
  end if;
  if pay is null then return jsonb_build_object('error', 'not found'); end if;
  if pay ? 'case' then pay := pay->'case'; end if;

  diagnoses  := coalesce(pay->'diagnoses',  '[]'::jsonb);
  tests      := coalesce(pay->'tests',       '[]'::jsonb);
  treatments := coalesce(pay->'treatments',  '[]'::jsonb);
  xp_reward  := coalesce((pay->>'xpReward')::int, 20);

  -- Diagnosis — 60%. Prefer name match; fall back to index for old clients.
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
  if h_total > 0 then tests_score := greatest(0, h_good::numeric / h_total - 0.25 * h_bad) * 0.20; end if;

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
  if a_total > 0 then tx_score := greatest(0, a_good::numeric / a_total - 0.25 * a_bad) * 0.20; end if;

  score := least(1.0, (case when dx_ok then 0.60 else 0 end) + tests_score + tx_score);

  insert into public.case_attempts (user_id, source, case_id)
  values (v_uid, p_source, p_id)
  on conflict (user_id, source, case_id) do update
    set attempts = public.case_attempts.attempts + 1, last_at = now();

  return jsonb_build_object(
    'score',        score,
    'earned_xp',    round(score * 100),
    'earned_coins', round(score * xp_reward),
    'case',         pay);
end;
$$;

revoke execute on function public.grade_case(text, uuid, int[], int, int[], text, text[], text[]) from anon;
grant  execute on function public.grade_case(text, uuid, int[], int, int[], text, text[], text[]) to authenticated;
