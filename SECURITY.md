# Security & secrets

This repo is **public**. The rules below keep it safe.

## Safe to commit (public by design — these ship inside the app binary anyway)
- **Supabase `anon` key** and project URL (`Shared/Backend/SupabaseConfig.swift`).
  Security is enforced by Row Level Security (RLS) policies, not by hiding this key.
- **RevenueCat public SDK key** (`appl_…` in `Cortex/RevenueCatConfig.swift`).
- **Apple Team ID** and **bundle identifiers** (in `project.pbxproj`, `Cortex.storekit`).

## NEVER commit (kept out via `.gitignore`, or templated with placeholders)
- **Supabase `service_role` key** — bypasses all RLS. `supabase/cron.sql` uses a
  `<SERVICE_ROLE_KEY>` placeholder; paste the real key only in the Supabase SQL
  editor / dashboard secrets, never into a file.
- **Apple Sign in `.p8` private key** (`AuthKey_*.p8`) — `*.p8` is gitignored.
- **APNs / Supabase function secrets** — supplied at runtime via
  `Deno.env.get(...)` and `supabase secrets set …`, never hardcoded.
- **Apple OAuth helper inputs** — `scripts/apple_client_secret.py` reads
  `APPLE_TEAM_ID`, `APPLE_SERVICES_ID`, `APPLE_KEY_ID`, `APPLE_P8_PATH` from the
  environment. Keep them in an untracked `scripts/.env`.
- **`.env`, `*.p12`, `*.mobileprovision`, `*secret*.txt`** — all gitignored.

## Application hardening (current posture)

Reviewed against the OWASP Mobile/API risks. Findings and the mitigations in place:

- **Injection (SQL):** Not present. The client never sends raw SQL — all writes
  go through typed, parameterized `SECURITY DEFINER` RPCs (`submit_score`,
  `get_leaderboard`, `register_device`) with `search_path = public`. No dynamic
  SQL (`EXECUTE`/`format`/`||`) anywhere. Edge functions use the parameterized
  supabase-js client.
- **XSS:** Not applicable. Native SwiftUI app — no `WKWebView`, no HTML
  rendering. The only web surface is the system-controlled Apple/Google OAuth
  sheet (`ASWebAuthenticationSession`).
- **Secure local storage:** All bearer tokens (admin + player access/refresh)
  are stored in the **Keychain** (`AfterFirstUnlockThisDeviceOnly` — encrypted,
  not synced, excluded from backups), never in UserDefaults. See
  `Shared/Backend/Keychain.swift`.
- **Admin PIN:** Salted **PBKDF2-SHA256 (150k iterations)**, hash + salt in the
  Keychain, constant-time comparison, and an escalating lockout after 5 failed
  attempts. See `CortexAdmin/Admin/AdminGate.swift`.
- **Question/answer protection:** The case answer key (`diagnoses[].correct`,
  `tests[].helpful`, `treatments[].appropriate`, and the outcome/mentor text) is
  never sent to the device. The `content` / `emergencies` tables are not readable
  by anon; clients fetch questions through `get_cases` / `get_emergencies`, which
  return the payload with the answers **stripped out**, and attempts are scored by
  `grade_case` on the server. Only admins can write (alter) questions.
  Grading **requires an authenticated player** (Google/Apple sign-in) — anonymous
  callers get `auth required`, so answers can't be scraped without an identity —
  and every attempt is logged to `case_attempts` and **rate-limited** to 120
  graded cases per user per hour, which defeats bulk harvesting. The app prompts
  the player to sign in at the outcome screen if they aren't already. See
  `supabase/server_grading.sql`. (Built-in sample cases ship with the app and are
  graded locally; only admin-uploaded content is server-protected.)
- **Per-account data isolation:** Each player's game state lives in `profiles`
  with RLS `using (user_id = auth.uid())`, so a signed-in account can read/write
  **only its own** row. Accounts are fully isolated and progress is bound to the
  account, not the device. See `supabase/profiles.sql`.
- **Leaderboard integrity:** `submit_score` clamps XP to `[0, 100_000_000]` and
  only ever moves a stored score **up**, so a known UUID can't be griefed down.
  Note: it's an anonymous, client-reported leaderboard — for true anti-cheat,
  move scoring server-side and require authenticated users.
- **Untrusted input → timezone:** `register_device` stores a timezone only if
  Postgres recognises it as a real IANA zone (else NULL); `send-emergency`
  also skips invalid zones, so one bad row can't crash the sender.
- **Transport:** All Supabase traffic is HTTPS (App Transport Security applies);
  no plaintext endpoints.

**Still depends on you:** every table's **RLS policies** must stay correctly
applied. After editing `schema.sql` / `leaderboard.sql` / `server_grading.sql`,
re-run them in the SQL editor and redeploy the `send-emergency` function for the
DB-side hardening to take effect. **`server_grading.sql` is required** — until
it's applied, the app cannot load server content (it no longer reads the tables
directly, only the stripped RPCs). Static review doesn't replace periodic
dependency scanning and dynamic/penetration testing.

## If a real secret is ever committed by accident
1. **Rotate it immediately** (the leaked value must be considered compromised):
   - Supabase `service_role` / `anon`: Supabase ▸ Settings ▸ API ▸ roll keys.
   - Apple `.p8`: revoke the key in the Apple Developer portal, create a new one.
   - RevenueCat: regenerate the API key.
2. Remove it from history (`git filter-repo`) and force-push.
