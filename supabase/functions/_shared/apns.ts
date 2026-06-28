// Minimal APNs (token-based, HTTP/2) helper for Deno Edge Functions.
// Signs an ES256 JWT with your APNs Auth Key (.p8) and pushes to devices.

function b64urlFromBytes(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function b64urlFromString(s: string): string {
  return b64urlFromBytes(new TextEncoder().encode(s));
}

function pemToPkcs8(pem: string): Uint8Array {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const raw = atob(body);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

// APNs JWTs are valid up to 1h; cache and refresh well within that.
let cachedToken: { jwt: string; at: number } | null = null;

export async function apnsJWT(p8: string, keyId: string, teamId: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && now - cachedToken.at < 50 * 60) return cachedToken.jwt;

  const header = b64urlFromString(JSON.stringify({ alg: "ES256", kid: keyId }));
  const claims = b64urlFromString(JSON.stringify({ iss: teamId, iat: now }));
  const signingInput = `${header}.${claims}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(p8),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  const jwt = `${signingInput}.${b64urlFromBytes(new Uint8Array(sig))}`;
  cachedToken = { jwt, at: now };
  return jwt;
}

export interface PushBody {
  title: string;
  body: string;
  emergencyId: string;
}

/** Sends one push. Returns the APNs HTTP status (200 = delivered to APNs). */
export async function sendPush(
  deviceToken: string,
  jwt: string,
  bundleId: string,
  sandbox: boolean,
  payload: PushBody,
): Promise<number> {
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
      // Ambulance-siren sound (siren.caf is bundled in the iOS app). Time-
      // sensitive so it breaks through Focus / Do Not Disturb.
      aps: {
        alert: { title: payload.title, body: payload.body },
        sound: "siren.caf",
        "interruption-level": "time-sensitive",
      },
      emergencyId: payload.emergencyId,
    }),
  });
  // Drain body so the connection can be reused.
  await res.text();
  return res.status;
}
