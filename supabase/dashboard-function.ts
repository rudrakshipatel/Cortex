// ============================================================================
// SELF-CONTAINED version of send-emergency for the Supabase DASHBOARD editor.
// Dashboard → Edge Functions → Deploy a new function → name it "send-emergency"
// → paste this whole file → Deploy.
//
// (The /functions/send-emergency + /functions/_shared files are the same thing
//  split up, for the CLI. Use either approach, not both.)
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ---- APNs helpers ----------------------------------------------------------
function b64urlFromBytes(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function b64urlFromString(s: string): string {
  return b64urlFromBytes(new TextEncoder().encode(s));
}
function pemToPkcs8(pem: string): Uint8Array {
  const body = pem.replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  const raw = atob(body);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}
let cachedToken: { jwt: string; at: number } | null = null;
async function apnsJWT(p8: string, keyId: string, teamId: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && now - cachedToken.at < 50 * 60) return cachedToken.jwt;
  const header = b64urlFromString(JSON.stringify({ alg: "ES256", kid: keyId }));
  const claims = b64urlFromString(JSON.stringify({ iss: teamId, iat: now }));
  const signingInput = `${header}.${claims}`;
  const key = await crypto.subtle.importKey(
    "pkcs8", pemToPkcs8(p8), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(signingInput));
  const jwt = `${signingInput}.${b64urlFromBytes(new Uint8Array(sig))}`;
  cachedToken = { jwt, at: now };
  return jwt;
}
async function sendPush(deviceToken: string, jwt: string, bundleId: string,
                       sandbox: boolean, emergencyId: string): Promise<number> {
  const host = sandbox ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
  const res = await fetch(`${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      aps: {
        alert: {
          title: "🚨 Emergency — you're on call",
          body: "There's an emergency and you're the only doctor available on site. Tap to respond.",
        },
        sound: "default",
      },
      emergencyId,
    }),
  });
  await res.text();
  return res.status;
}

// Local wall-clock in a given IANA timezone: { date: "YYYY-MM-DD", minutes }.
function localNow(tz: string): { date: string; minutes: number } {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-CA", {
      timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit",
      hour: "2-digit", minute: "2-digit", hourCycle: "h23",
    }).formatToParts(new Date()).map((p) => [p.type, p.value]),
  );
  return {
    date: `${parts.year}-${parts.month}-${parts.day}`,
    minutes: (+parts.hour) * 60 + (+parts.minute),
  };
}

// ---- Function --------------------------------------------------------------
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
    for (const e of emergencies) {
      if (done.has(`${e.id}|${tz}`)) continue;
      const target = (e.local_hour as number) * 60 + (e.local_minute as number);
      // Fire once the local time on the target date has reached the target.
      if (e.send_date === now.date && now.minutes >= target) {
        const tokens = withTz.filter((d) => d.timezone === tz).map((d) => d.apns_token as string);
        for (const t of tokens) {
          if (await sendPush(t, jwt, bundleId, sandbox, e.id as string) === 200) delivered++;
        }
        await supabase.from("emergency_sends").insert({ emergency_id: e.id, timezone: tz });
      }
    }
  }
  return json({ zones: zones.length, delivered });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}
