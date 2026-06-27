-- ============================================================================
-- Cortex — hide answers / grade on the server.
-- Run this in the Supabase SQL editor AFTER schema.sql + leaderboard.sql.
-- Every statement is idempotent.
--
-- Why: the case payload contains the answer key (diagnoses[].correct,
-- tests[].helpful, treatments[].appropriate, and the outcome/mentor text). If
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
        (select jsonb_agg(e - 'correct') from jsonb_array_elements(p->'diagnoses') e), '[]'::jsonb),
      'tests', coalesce(
        (select jsonb_agg(e - 'helpful') from jsonb_array_elements(p->'tests') e), '[]'::jsonb),
      'treatments', coalesce(
        (select jsonb_agg(e - 'appropriate') from jsonb_array_elements(p->'treatments') e), '[]'::jsonb)
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

-- 3) Grade an attempt on the server. The client sends the ARRAY INDICES of the
--    options it picked; the server reads the true answers from storage, scores
--    the attempt (same formula as the app), and returns the score plus the full
--    case so the outcome screen can reveal the answer AFTER the attempt.
--      diagnosis 60% · helpful tests 20% · appropriate treatments 20%,
--      with a 0.25 penalty per wasteful test/treatment.
create or replace function public.grade_case(
  p_source   text,
  p_id       uuid,
  p_test_idx int[] default '{}',
  p_dx_idx   int   default null,
  p_tx_idx   int[] default '{}'
) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
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

  -- Diagnosis — 60%.
  if p_dx_idx is not null and p_dx_idx >= 0 and p_dx_idx < jsonb_array_length(diagnoses) then
    dx_ok := coalesce((diagnoses->p_dx_idx->>'correct')::boolean, false);
  end if;

  -- Tests — up to 20%.
  h_total := (select count(*) from jsonb_array_elements(tests) t
              where coalesce((t->>'helpful')::boolean, false));
  h_good  := (select count(*) from unnest(p_test_idx) i
              where i >= 0 and i < jsonb_array_length(tests)
                and coalesce((tests->i->>'helpful')::boolean, false));
  h_bad   := (select count(*) from unnest(p_test_idx) i
              where i >= 0 and i < jsonb_array_length(tests)
                and not coalesce((tests->i->>'helpful')::boolean, false));
  if h_total > 0 then
    tests_score := greatest(0, h_good::numeric / h_total - 0.25 * h_bad) * 0.20;
  end if;

  -- Treatments — up to 20%.
  a_total := (select count(*) from jsonb_array_elements(treatments) t
              where coalesce((t->>'appropriate')::boolean, false));
  a_good  := (select count(*) from unnest(p_tx_idx) i
              where i >= 0 and i < jsonb_array_length(treatments)
                and coalesce((treatments->i->>'appropriate')::boolean, false));
  a_bad   := (select count(*) from unnest(p_tx_idx) i
              where i >= 0 and i < jsonb_array_length(treatments)
                and not coalesce((treatments->i->>'appropriate')::boolean, false));
  if a_total > 0 then
    tx_score := greatest(0, a_good::numeric / a_total - 0.25 * a_bad) * 0.20;
  end if;

  score := least(1.0, (case when dx_ok then 0.60 else 0 end) + tests_score + tx_score);

  return jsonb_build_object(
    'score',        score,
    'earned_xp',    round(score * 100),
    'earned_coins', round(score * xp_reward),
    'case',         pay     -- full payload (answers) — revealed only post-attempt
  );
end;
$$;
grant execute on function public.grade_case(text, uuid, int[], int, int[]) to anon, authenticated;

-- 4) Lock the tables: anon may no longer read raw rows (so the answer key can't
--    be scraped). Access is only through the stripped feeds + grade_case above.
--    Admin write policies (from schema.sql) are unchanged.
drop policy if exists "read content" on public.content;
drop policy if exists "read emergencies" on public.emergencies;

-- 5) Refresh PostgREST so the new RPCs are visible immediately.
notify pgrst, 'reload schema';
