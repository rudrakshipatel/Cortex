// Edge Function: delete the signed-in user's account and personal data.
//
// Required for App Store guideline 5.1.1(v): any app with account creation must
// let users delete their account from inside the app. The client calls this with
// the player's JWT; we verify it, wipe their rows, then delete the auth user
// (which cascades anything keyed to auth.users, e.g. profiles).
//
// (SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are injected
// automatically — no extra secrets needed.)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  // Identify the caller from their JWT.
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const anon = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!);
  const { data: userData } = await anon.auth.getUser(token);
  const uid = userData?.user?.id;
  if (!uid) return json({ error: "Please sign in first." }, 401);

  // Service-role client to remove their data + the auth user.
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Best-effort cleanup of gameplay rows keyed to this user (not all cascade).
  await admin.from("leaderboard").delete().eq("player_id", uid);
  await admin.from("league_members").delete().eq("player_id", uid);
  await admin.from("case_attempts").delete().eq("user_id", uid);
  await admin.from("profiles").delete().eq("user_id", uid);

  // Finally delete the auth user itself.
  const { error } = await admin.auth.admin.deleteUser(uid);
  if (error) {
    console.error("deleteUser failed:", error);
    return json({ error: "Couldn't delete the account. Please try again." }, 500);
  }
  return json({ deleted: true });
});
