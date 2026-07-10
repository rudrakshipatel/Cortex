# Setup for Challenge links & the referral reward

The app code for both features is done. These are the **out-of-app** steps
needed to make them fully work in production.

## 1. Challenge-a-friend case links

Shared links look like `https://www.cortexcases.com/case/{id}`. When tapped:
- If Cortex is installed → opens that case (via the `cortex://case/{id}` scheme, already registered in the app).
- If not installed → the web page forwards to the App Store / Play Store.

**To deploy:**
1. Host [`redirect.html`](redirect.html) so it serves every `/case/*` **and** `/invite/*` path on `www.cortexcases.com` (see the comment block at the top of that file for host-specific config).
2. Edit the two store URLs near the top of `redirect.html` (`APP_STORE_URL`, `PLAY_STORE_URL`) to your real listings.

Only **server-published** cases produce a case-specific link (built-in/seed cases can't be shared — they have no stable id). A case with no server id falls back to a plain "download Cortex" link.

## 2. Referral reward — invite 10 friends → 1 free month of Pro

**Supabase:**
1. Run [`../supabase/referrals.sql`](../supabase/referrals.sql) in the SQL editor (creates the invite-code / referral / reward tables + `referral_stats`, `redeem_referral` RPCs).
2. Deploy the grant function: `supabase functions deploy grant-referral-reward`.
3. Set the RevenueCat **secret** key (starts with `sk_`, from RevenueCat ▸ Project ▸ API keys):
   `supabase secrets set REVENUECAT_SECRET_KEY=sk_xxx`

**RevenueCat:**
- The reward is granted as a **promotional entitlement** on the `pro` entitlement, duration `monthly`. No dashboard change needed beyond having the `pro` entitlement (you already do).
- The app now calls `Purchases.logIn(supabaseUserId)` so the grant reaches the right account. Verify in RevenueCat that customers appear keyed by their Supabase user id after signing in.

**How the flow works:**
- New users enter a friend's code during onboarding (or arrive via an invite link) → `redeem_referral` attributes them once.
- The inviter sees their code + `X / 10` progress on the Leagues tab. At 10, a **Claim your free month** button calls `grant-referral-reward`, which server-verifies the count and grants the month.

## 3. AI daily limit (from the previous change)

- Run [`../supabase/ai_daily_limit.sql`](../supabase/ai_daily_limit.sql) and redeploy `ask-ai`: `supabase functions deploy ask-ai`. Caps the AI tutor at 25 questions/user/UTC-day, enforced before any paid provider call.
