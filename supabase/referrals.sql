-- Referral program: invite 10 friends who sign up → the inviter earns 1 free
-- month of Pro. Attribution is by an invite CODE the new friend applies when
-- they create their account (see redeem_referral). The actual Pro grant is
-- done by the grant-referral-reward Edge Function via RevenueCat — SQL only
-- tracks who referred whom and whether the reward has been claimed.
--
-- Safe to run now: paste into the Supabase SQL editor and run.

-- Friends counted toward the reward, and the reward length.
-- (The count threshold is also enforced in the grant Edge Function.)
create table if not exists public.referral_codes (
  user_id uuid primary key references auth.users(id) on delete cascade,
  code    text unique not null,
  created_at timestamptz not null default now()
);

create table if not exists public.referrals (
  referrer_id uuid not null references auth.users(id) on delete cascade,
  referred_id uuid not null references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (referred_id)               -- a user can only be referred once, ever
);
create index if not exists referrals_by_referrer on public.referrals (referrer_id);

create table if not exists public.referral_rewards (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  granted_at timestamptz not null default now()
);

alter table public.referral_codes   enable row level security;
alter table public.referrals         enable row level security;
alter table public.referral_rewards  enable row level security;
-- No client-facing policies: all access goes through the security-definer
-- RPCs below (and the service-role Edge Function), never direct table reads.

-- A short, unambiguous invite code (no 0/O/1/I). Regenerated on the rare
-- collision.
create or replace function public.gen_referral_code()
returns text language plpgsql as $$
declare
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  out text;
  i int;
begin
  loop
    out := '';
    for i in 1..7 loop
      out := out || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.referral_codes where code = out);
  end loop;
  return out;
end;
$$;

-- The caller's own invite code (created on first call), their confirmed-friend
-- count, and whether they've already claimed the reward. Drives the invite card.
create or replace function public.referral_stats()
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_code text;
  v_count int;
  v_granted boolean;
begin
  if v_uid is null then return jsonb_build_object('error', 'auth required'); end if;
  select code into v_code from public.referral_codes where user_id = v_uid;
  if v_code is null then
    v_code := public.gen_referral_code();
    insert into public.referral_codes (user_id, code) values (v_uid, v_code)
      on conflict (user_id) do update set code = excluded.code
      returning code into v_code;
  end if;
  select count(*) into v_count from public.referrals where referrer_id = v_uid;
  select exists(select 1 from public.referral_rewards where user_id = v_uid) into v_granted;
  return jsonb_build_object('code', v_code, 'count', v_count, 'reward_granted', v_granted);
end;
$$;

-- Called by a NEW user (the referred friend) with the inviter's code. Records
-- the attribution once; a user can't refer themselves or be referred twice.
create or replace function public.redeem_referral(p_code text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_referrer uuid;
begin
  if v_uid is null then return jsonb_build_object('error', 'auth required'); end if;
  select user_id into v_referrer from public.referral_codes where code = upper(btrim(p_code));
  if v_referrer is null then return jsonb_build_object('error', 'invalid code'); end if;
  if v_referrer = v_uid then return jsonb_build_object('error', 'cannot refer yourself'); end if;
  if exists (select 1 from public.referrals where referred_id = v_uid) then
    return jsonb_build_object('error', 'already referred');
  end if;
  insert into public.referrals (referrer_id, referred_id) values (v_referrer, v_uid);
  return jsonb_build_object('ok', true);
end;
$$;

revoke execute on function public.referral_stats()        from anon;
revoke execute on function public.redeem_referral(text)   from anon;
grant  execute on function public.referral_stats()        to authenticated;
grant  execute on function public.redeem_referral(text)   to authenticated;
