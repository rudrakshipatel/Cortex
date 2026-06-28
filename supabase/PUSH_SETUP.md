# Emergency push setup (deliver when the app is killed / phone off)

In-app emergency cards + the local siren notification work when the app is
**open**. To deliver a notification when the app is **killed, backgrounded, or
the phone was off** — and to anyone who hasn't opened the app — you need the
**APNs push**, sent by the `send-emergency` Edge Function on a 1-minute cron.

Everything in the code is ready. These three steps are all that's left. They
need your Apple Developer account + the Supabase CLI — they can't be done from
the app.

---

## 1. Create an APNs Auth Key (.p8) — Apple Developer
1. https://developer.apple.com → **Certificates, Identifiers & Profiles → Keys → ＋**
2. Name it `Cortex APNs`, tick **Apple Push Notifications service (APNs)** → Continue → Register.
3. **Download** `AuthKey_XXXXXXXXXX.p8` (one-time download!). Note the **Key ID** (10 chars).
   Your **Team ID** is `V45665P4Z5`.

## 2. Give the secrets to Supabase (Supabase CLI)
If you don't have the CLI yet:
```bash
brew install supabase/tap/supabase
supabase login
supabase link --project-ref lrzvmzkrtwawpiqxrkik
```
Then set the secrets:
```bash
supabase secrets set \
  APNS_KEY_P8="$(cat ~/Downloads/AuthKey_XXXXXXXXXX.p8)" \
  APNS_KEY_ID=XXXXXXXXXX \
  APNS_TEAM_ID=V45665P4Z5 \
  APNS_BUNDLE_ID=com.docriddles.cortex \
  APNS_SANDBOX=true
```
> ⚠️ **`APNS_SANDBOX=true`** for any build you run from Xcode (development push
> environment). Set it to `false` only for TestFlight / App Store builds.

## 3. Deploy the function
```bash
supabase functions deploy send-emergency
```
(`cron.sql` already calls it every minute, so once it's deployed + secrets are
set, the loop is live.)

---

## Test it (on a REAL device — the simulator can't get a push token)
1. **Rebuild & reinstall** the Cortex player onto the device *after* adding the
   Push Notifications capability, and **open it once** so it registers its token:
   ```sql
   select apns_token is not null as has_token, timezone from public.devices;
   ```
   Expect a row with `has_token = true`.
2. **Kill the app** (or lock the phone).
3. Broadcast an emergency (admin app, or a SQL insert).
4. Within ~1 minute the **siren push** arrives with the app closed. Tap → opens the case.

## If a push doesn't arrive
Check **Supabase → Edge Functions → send-emergency → Logs**. Common causes:
- `APNS_SANDBOX` wrong for the build type (dev build needs `true`).
- No row in `public.devices` (the app never registered — rebuild with the Push
  capability, open once, allow notifications).
- `BadDeviceToken` in the logs = sandbox/production mismatch (flip `APNS_SANDBOX`).
