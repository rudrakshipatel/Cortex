// Edge Function: deliver any due emergency cases to all registered devices.
//
// Trigger it on a schedule (every minute) via pg_cron — see README. It can also
// be invoked manually. Uses the service-role key to bypass RLS.
//
// Required secrets (set with `supabase secrets set`):
//   APNS_KEY_P8   – contents of your AuthKey_XXXX.p8
//   APNS_KEY_ID   – the 10-char Key ID
//   APNS_TEAM_ID  – your Apple Team ID
//   APNS_BUNDLE_ID– app bundle id (com.docriddles.cortex)
//   APNS_SANDBOX  – "true" for development push, "false"/unset for production
// (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { apnsJWT, sendPush } from "../_shared/apns.ts";

// Local wall-clock in a given IANA timezone: { date: "YYYY-MM-DD", minutes }.
// Returns null for an invalid/unknown timezone string (a device could register
// a garbage value) so one bad row can't throw and abort the whole run.
function localNow(tz: string): { date: string; minutes: number } | null {
  try {
    const parts = Object.fromEntries(
      new Intl.DateTimeFormat("en-CA", {
        timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit",
        hour: "2-digit", minute: "2-digit", hourCycle: "h23",
      }).formatToParts(new Date()).map((p) => [p.type, p.value]),
    );
    return { date: `${parts.year}-${parts.month}-${parts.day}`, minutes: (+parts.hour) * 60 + (+parts.minute) };
  } catch {
    return null; // RangeError: invalid time zone
  }
}

Deno.serve(async () => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: emergencies, error } = await supabase
    .from("emergencies").select("id,send_date,local_hour,local_minute");
  if (error) return json({ error: error.message }, 500);
  if (!emergencies || emergencies.length === 0) return json({ sent: 0, message: "none" });

  const { data: devices } = await supabase.from("devices").select("apns_token,timezone");
  const withTz = (devices ?? []).filter((d) => d.timezone);
  const zones = [...new Set(withTz.map((d) => d.timezone as string))];

  const { data: priorSends } = await supabase.from("emergency_sends").select("emergency_id,timezone");
  const done = new Set((priorSends ?? []).map((s) => `${s.emergency_id}|${s.timezone}`));

  const jwt = await apnsJWT(
    Deno.env.get("APNS_KEY_P8")!, Deno.env.get("APNS_KEY_ID")!, Deno.env.get("APNS_TEAM_ID")!);
  const bundleId = Deno.env.get("APNS_BUNDLE_ID")!;
  const sandbox = (Deno.env.get("APNS_SANDBOX") ?? "false") === "true";

  let delivered = 0;
  for (const tz of zones) {
    const now = localNow(tz);
    if (!now) continue; // skip devices that registered an invalid timezone
    for (const e of emergencies) {
      if (done.has(`${e.id}|${tz}`)) continue;
      const target = (e.local_hour as number) * 60 + (e.local_minute as number);
      if (e.send_date === now.date && now.minutes >= target) {
        const tokens = withTz.filter((d) => d.timezone === tz).map((d) => d.apns_token as string);
        for (const t of tokens) {
          const status = await sendPush(t, jwt, bundleId, sandbox, {
            title: "🚨 Emergency — you're on call",
            body: "There's an emergency and you're the only doctor available on site. Tap to respond.",
            emergencyId: e.id as string,
          });
          if (status === 200) delivered++;
        }
        await supabase.from("emergency_sends").insert({ emergency_id: e.id, timezone: tz });
      }
    }
  }

  return json({ zones: zones.length, delivered });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
