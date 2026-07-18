# Case links (`cortexcases.com/case/<id>`)

"Challenge Friends" shares a link like:

```
https://www.cortexcases.com/case/3f2504e0-4f89-11d3-9a0c-0305e82c3301
```

**Installed →** iOS hands the URL to the Cortex app, which opens that exact case.
**Not installed →** the browser loads the page below, which redirects to the App Store.

Both behaviours come from one link — there is no app-detection hack, and nothing
to change in the app when the site changes.

## What the site must serve

### 1. `/.well-known/apple-app-site-association`

Copy `.well-known/apple-app-site-association` to the site root so it resolves at:

```
https://www.cortexcases.com/.well-known/apple-app-site-association
https://cortexcases.com/.well-known/apple-app-site-association
```

Requirements iOS enforces — get any of these wrong and the link silently opens
in Safari instead of the app:

- Served over **HTTPS** with a valid certificate.
- `Content-Type: application/json`.
- **No** `.json` file extension.
- **No** redirect (must be `200`, not `301`/`302`).
- Reachable by anonymous request (no auth, no Cloudflare challenge page).

Verify:

```sh
curl -sSI https://www.cortexcases.com/.well-known/apple-app-site-association
curl -sS  https://www.cortexcases.com/.well-known/apple-app-site-association | python3 -m json.tool
```

### 2. `/case/*` → `case.html`

Route every `/case/<anything>` URL to `case.html` (it ignores the id — the app
reads it, the page only needs to offer the App Store).

Netlify (`_redirects`):

```
/case/*  /case.html  200
```

Vercel (`vercel.json`):

```json
{ "rewrites": [{ "source": "/case/(.*)", "destination": "/case.html" }] }
```

Nginx:

```nginx
location /case/ { try_files $uri /case.html; }
```

## After deploying

1. Apple caches the association file through its CDN. A **fresh install** picks
   it up immediately; an existing install can take up to ~24h, or reinstall to
   force it.
2. Test on a real device (Universal Links do **not** work in the Simulator):
   paste the link into Messages/Notes and long-press → it should offer
   "Open in Cortex".
3. Check Apple's own view of the file:
   `https://app-site-association.cdn-apple.com/a/v1/www.cortexcases.com`

## App side (already done)

- `Cortex/Cortex.entitlements` — `applinks:cortexcases.com` + `www.` variant.
- `Shared/Models/DeepLink.swift` — builds and parses the links.
- `Cortex/CortexApp.swift` — `onOpenURL` + `onContinueUserActivity`.
- `Cortex/Views/Main/MainTabView.swift` — resolves the id and opens the case.

The App ID in the association file is `V45665P4Z5.com.docriddles.cortex`
(Team ID + bundle id). If either ever changes, update the file to match.

**Also required in the Apple Developer portal:** the App ID must have the
**Associated Domains** capability enabled, and the provisioning profile must be
regenerated afterwards — otherwise the entitlement fails at build/install time.
