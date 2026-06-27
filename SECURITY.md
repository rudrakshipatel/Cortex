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

## If a real secret is ever committed by accident
1. **Rotate it immediately** (the leaked value must be considered compromised):
   - Supabase `service_role` / `anon`: Supabase ▸ Settings ▸ API ▸ roll keys.
   - Apple `.p8`: revoke the key in the Apple Developer portal, create a new one.
   - RevenueCat: regenerate the API key.
2. Remove it from history (`git filter-repo`) and force-push.
