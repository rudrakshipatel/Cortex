# Cortex backend (Supabase + APNs)

Broadcasts published questions and scheduled **emergency** cases to **all** users.

```
iOS app (no SDK, URLSession) ──► Supabase (Postgres + Auth)
                                      │
                          send-emergency Edge Function ──APNs(.p8)──► every device
```

The iOS app talks to Supabase over plain REST (no extra Swift packages). Until
you fill in `Cortex/Backend/SupabaseConfig.swift`, the app runs fully
offline/local and none of this is used.

---

## What only you can do (accounts & credentials)

These need your own accounts and **cannot** be done from code:

1. **Apple Developer Program** membership (for push).
2. In Xcode → target **Cortex** → **Signing & Capabilities** → **+ Capability → Push Notifications**.
   (Also add **Background Modes → Remote notifications** if you want silent delivery.)
3. **APNs Auth Key**: Apple Developer → Keys → create a key with *Apple Push
   Notifications service (APNs)* enabled. Download the `AuthKey_XXXXXXXXXX.p8`
   and note the **Key ID** and your **Team ID**.

---

## 1. Create the Supabase project

1. Create a project at supabase.com.
2. SQL Editor → run **`schema.sql`**.
3. Settings → API → copy the **Project URL** and **anon** key into
   `Cortex/Backend/SupabaseConfig.swift`, then rebuild the app.

## 2. Create the admin user

1. Authentication → Users → **Add user** (your email + password). This is what
   you'll type into the app's **Cloud sync** screen.
2. Copy that user's **UID**, then in SQL Editor:
   ```sql
   insert into public.admins (id) values ('<YOUR-USER-UID>');
   ```
   Only this user can publish content / broadcast emergencies (enforced by RLS).

## 3. Deploy the push function

Install the Supabase CLI, then:

```bash
supabase link --project-ref <PROJECT_REF>

# APNs secrets (the function reads these)
supabase secrets set APNS_KEY_P8="$(cat AuthKey_XXXXXXXXXX.p8)"
supabase secrets set APNS_KEY_ID=XXXXXXXXXX
supabase secrets set APNS_TEAM_ID=YYYYYYYYYY
supabase secrets set APNS_BUNDLE_ID=com.docriddles.cortex
supabase secrets set APNS_SANDBOX=true     # true for dev builds, false for TestFlight/App Store

supabase functions deploy send-emergency
```

## 4. Schedule the sender

Edit **`cron.sql`** (fill in `<PROJECT_REF>` and your **service_role** key from
Settings → API) and run it in the SQL Editor. It calls `send-emergency` every
minute; the function delivers any emergency whose `send_at` time has passed and
marks it `sent`.

---

## How it works in the app

- **Every launch**: the app registers its APNs token into `devices` and pulls
  any new rows from `content` (so published questions appear for everyone).
- **Admin → Cloud sync**: sign in with the admin user.
- **Admin → Bulk import → "Publish to all users"**: sends the pasted JSON to
  `content`.
- **Admin → Emergency case → "Broadcast to all users"**: stores the case in
  `emergencies` with your send time. At that time the function pushes
  *"🚨 Emergency — you're on call…"* to every device; tapping it opens the case
  (fetched by id from `emergencies`).

### Notes
- Remote push needs a **real device** (the iOS Simulator can't receive APNs in
  most setups). Test on hardware.
- `APNS_SANDBOX=true` for development/debug builds; switch to `false` for
  TestFlight/App Store builds.
- The `anon` key is safe to ship. **Never** put the `service_role` key in the
  app — it lives only in Supabase secrets / the cron job.
