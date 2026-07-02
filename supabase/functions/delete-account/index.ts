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
  try {
    if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

    const url = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // Identify the caller from their JWT.
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const anon = createClient(url, anonKey);
    const { data: userData, error: userErr } = await anon.auth.getUser(token);
    const uid = userData?.user?.id;
    if (userErr || !uid) return json({ error: "Please sign in first." }, 401);

    // Service-role client for the data cleanup (bypasses RLS).
    const admin = createClient(url, serviceKey);

    // Best-effort removal of gameplay rows keyed to this user. Errors here are
    // non-fatal (a table might not exist on every project) — the auth-user
    // delete below cascades the rest.
    const cleanups: [string, string][] = [
      ["leaderboard", "player_id"],
      ["league_members", "player_id"],
      ["case_attempts", "user_id"],
      ["profiles", "user_id"],
    ];
    for (const [table, col] of cleanups) {
      try { await admin.from(table).delete().eq(col, uid); } catch (_) { /* ignore */ }
    }

    // Delete the auth user itself via the GoTrue admin REST endpoint. This is
    // the reliable path (and cascades profiles/admins via their FKs).
    const res = await fetch(`${url}/auth/v1/admin/users/${uid}`, {
      method: "DELETE",
      headers: { "Authorization": `Bearer ${serviceKey}`, "apikey": serviceKey },
    });
    if (!res.ok) {
      const detail = await res.text();
      console.error("deleteUser failed", res.status, detail);
      return json({ error: `Couldn't delete the account (status ${res.status}).` }, 500);
    }

    return json({ deleted: true });
  } catch (e) {
    console.error("delete-account crashed", e);
    return json({ error: (e as Error)?.message ?? "Account deletion failed." }, 500);
  }
});
