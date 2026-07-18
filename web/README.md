# Case links (`cortexcases.com/case/<id>`)

"Challenge Friends" shares a Universal Link / App Link:

```
https://www.cortexcases.com/case/<server-case-id>
```

**Installed →** the OS hands the URL straight to the app, which opens that case.
**Not installed →** the browser loads the site's `/case/*` page, which redirects
to the App Store or Google Play depending on the device.

## The web side lives in the `cortex-site` repo, not here

Everything the browser needs is served from the marketing site:

| File | Purpose |
| --- | --- |
| `.well-known/apple-app-site-association` | Lets iOS open the app. Must be `application/json`, no file extension, HTTPS, **no redirect**. |
| `.well-known/assetlinks.json` | Lets Android open the app. Needs the app's SHA-256 signing fingerprint from Play Console. |
| `js/deeplink.js` | The "not installed" path — redirects to the right store. |
| `vercel.json` | Rewrites `/case/*` → the page, and pins the two files' `Content-Type`. |

Verify they're live:

```sh
curl -sSI https://www.cortexcases.com/.well-known/apple-app-site-association   # 200, application/json, no redirect
curl -sS  https://www.cortexcases.com/.well-known/assetlinks.json | python3 -m json.tool
```

Apple also caches the file through its own CDN — check what it sees:
`https://app-site-association.cdn-apple.com/a/v1/www.cortexcases.com`

## App side (in this repo)

- `Cortex/Cortex.entitlements` — `applinks:cortexcases.com` + the `www.` host.
- `Shared/Models/DeepLink.swift` — builds and parses the links.
- `Cortex/CortexApp.swift` — `onOpenURL` + `onContinueUserActivity`.
- `Cortex/Views/Main/MainTabView.swift` — resolves the id and opens the case.

The App ID in the association file is `V45665P4Z5.com.docriddles.cortex`
(Team ID + bundle id). If either changes, update the file to match.

**Also required in the Apple Developer portal:** the App ID needs the
**Associated Domains** capability enabled, and the provisioning profile
regenerated afterwards — otherwise the entitlement fails at install time.

Android already declares the App Link in `AndroidManifest.xml`
(`autoVerify="true"` for `www.cortexcases.com/case` and `/invite`); it only
needs `assetlinks.json` to be live and correct.
