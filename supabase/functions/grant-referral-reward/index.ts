// Edge Function: grant the referral reward — 1 free month of Pro — once a user
// has referred REFERRAL_THRESHOLD friends who signed up.
//
// The signed-in referrer's app calls this to claim their reward. We verify the
// friend count server-side (never trusting the client), grant a RevenueCat
// PROMOTIONAL entitlement for one month to their RevenueCat app_user_id (which
// the app sets to the Supabase user id via Purchases.logIn), then record the
// claim so it can't be granted twice.
//
// Required secret (set with `supabase secrets set`):
//   REVENUECAT_SECRET_KEY  – a RevenueCat SECRET API key (starts with "sk_"),
//                            from RevenueCat ▸ Project ▸ API keys. NEVER ships
//                            in the app.
// Optional override:
//   REVENUECAT_ENTITLEMENT – default "pro" (must match RevenueCatConfig.entitlementID)
// (SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are injected.)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const REFERRAL_THRESHOLD = 10;
const ENTITLEMENT = Deno.env.get("REVENUECAT_ENTITLEMENT") ?? "pro";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!);
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: userData } = await anon.auth.getUser(token);
  const uid = userData?.user?.id;
  if (!uid) return json({ error: "Please sign in first." }, 401);

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  // Already claimed? Idempotent success.
  const { data: existing } = await admin
    .from("referral_rewards").select("user_id").eq("user_id", uid).maybeSingle();
  if (existing) return json({ granted: true, already: true });

  // Verify the friend count server-side.
  const { count, error: countErr } = await admin
    .from("referrals").select("*", { count: "exact", head: true }).eq("referrer_id", uid);
  if (countErr) {
    console.error("count referrals failed", countErr);
    return json({ error: "Couldn't check your referrals. Please try again." }, 500);
  }
  if ((count ?? 0) < REFERRAL_THRESHOLD) {
    return json({ error: `You need ${REFERRAL_THRESHOLD} friends to claim this. You have ${count ?? 0}.` }, 400);
  }

  // Grant 1 month of the Pro entitlement via RevenueCat.
  const secret = Deno.env.get("REVENUECAT_SECRET_KEY");
  if (!secret) {
    console.error("REVENUECAT_SECRET_KEY not set");
    return json({ error: "Rewards aren't configured yet. Please contact support." }, 500);
  }
  const rcURL = `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(uid)}/entitlements/${encodeURIComponent(ENTITLEMENT)}/promotional`;
  const rc = await fetch(rcURL, {
    method: "POST",
    headers: { "Authorization": `Bearer ${secret}`, "Content-Type": "application/json" },
    body: JSON.stringify({ duration: "monthly" }),
  });
  if (!rc.ok) {
    console.error("RevenueCat grant failed", rc.status, await rc.text());
    return json({ error: "Couldn't grant your free month right now. Please try again." }, 502);
  }

  // Record the claim so it can't be granted again.
  const { error: insErr } = await admin.from("referral_rewards").insert({ user_id: uid });
  if (insErr) console.error("record reward failed (grant already applied)", insErr);

  return json({ granted: true });
});
