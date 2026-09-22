# Laravel Backend + Mobile Implementation Guide — Email Deep Links (App Links)

Standalone reference for the Laravel developer **and** the mobile/Flutter developer. Goal: when a user taps a button in an HRMS email (e.g. "Review & Approve" on a leave-request email), the link opens the MECPL HRMS mobile app directly — not the web browser. Same link still works on desktop / phones without the app installed (opens in the browser as a fallback).

This is the same mechanism WhatsApp / Gmail / Twitter / Slack use. It's called **Android App Links** on Android and **Universal Links** on iOS.

---

## Table of contents

1. [Scope](#1-scope)
2. [Architecture](#2-architecture)
3. [Prerequisites](#3-prerequisites)
4. [Division of work — who does what](#4-division-of-work--who-does-what)
5. [Step A — Mobile owner: extract SHA256 fingerprints](#5-step-a--mobile-owner-extract-sha256-fingerprints)
6. [Step B — Backend: host `assetlinks.json`](#6-step-b--backend-host-assetlinksjson)
7. [Step C — Backend: standardise URL structure](#7-step-c--backend-standardise-url-structure)
8. [Step D — Backend: update email templates](#8-step-d--backend-update-email-templates)
9. [Step E — Backend: keep web fallback working](#9-step-e--backend-keep-web-fallback-working)
10. [Step F — Mobile: Flutter changes](#10-step-f--mobile-flutter-changes)
11. [Testing checklist](#11-testing-checklist)
12. [iOS Universal Links (later)](#12-ios-universal-links-later)
13. [Common pitfalls](#13-common-pitfalls)
14. [Security notes](#14-security-notes)
15. [Appendix — Authentication on the deep-linked URL](#15-appendix--authentication-on-the-deep-linked-url)

---

## 1. Scope

**What we're delivering:**

When the user receives an email like:

> **New Leave Request For Approval**
> A new leave request has been submitted by MONISH BALAKRISHANAN SELVASEKAR…
> [Review & Approve]

…and they tap **Review & Approve** on their phone:

- If MECPL HRMS app is installed → the app opens directly to the leave-approval screen for that specific leave.
- If not installed → the existing web page opens in the browser, as it does today.

**What this is NOT:**

- Not push notifications — that's FCM, covered in `laravel-fcm-push-notifications.md`.
- Not a separate "deep link" URL format — same `https://hrms.mecpl.in/...` URL works everywhere.
- Not analytics / install attribution — that needs a third-party (Branch.io); out of scope here.

---

## 2. Architecture

```
   ┌──────────────┐  1. user clicks button   ┌──────────────┐
   │  Email app   │─────────────────────────▶│  Android OS  │
   │  on phone    │                          │              │
   └──────────────┘                          └──────┬───────┘
                                                    │ 2. URL host = hrms.mecpl.in
                                                    │    Has any installed app verified
                                                    │    this domain?
                                                    │
                                ┌───────────────────┴───────────────────┐
                                │ YES (verified at install time)        │ NO
                                ▼                                       ▼
                       ┌──────────────────┐                     ┌──────────────────┐
                       │  MECPL HRMS app  │                     │  Default browser │
                       │  opens to deep-  │                     │  loads the web   │
                       │  linked screen   │                     │  page (existing  │
                       └──────────────────┘                     │  fallback flow)  │
                                                                └──────────────────┘
```

**Verification (one-time, happens silently at app install):**

```
   ┌──────────────┐  fetches at app install  ┌────────────────────────────┐
   │  Android OS  │─────────────────────────▶│ hrms.mecpl.in              │
   │              │                          │ /.well-known/assetlinks.json│
   │              │                          └────────────┬───────────────┘
   │              │                                       │
   │              │  compares SHA256 fingerprint          │
   │              │  in assetlinks.json with the app's    │
   │              │  installed signing certificate        │
   │              │                                       │
   │              │  ✓ match → app is verified owner      │
   │              │  ✗ mismatch → falls back to browser   │
   └──────────────┘                                       │
```

The assetlinks.json file is the only piece of "trust" — it lets Google's verifier confirm that the MECPL Android app legitimately speaks for `hrms.mecpl.in`. Without it, Android shows a "Open with:" chooser at best, or just opens the browser at worst.

---

## 3. Prerequisites

- HTTPS on `hrms.mecpl.in` (must be valid TLS, no self-signed). App Links **does not work over HTTP** — Android rejects it.
- Backend can serve a static JSON file at a `.well-known/` path.
- Mobile app has a release keystore (`android/app/key.jks` — already exists).
- Laravel 10/11+ (the patterns below assume this).

---

## 4. Division of work — who does what

| Step | Who | What |
|---|---|---|
| A | You (mobile owner) | Extract SHA256 fingerprints from `key.jks` + debug keystore |
| B | Backend dev | Host `assetlinks.json` at the well-known URL |
| C | Backend dev | Standardise URL structure for the things we want to deep-link |
| D | Backend dev | Update email templates to use the standardised URLs |
| E | Backend dev | Keep the existing web pages working as fallback |
| F | Mobile dev (Flutter) | Add `app_links` package, intent filter, route parsing |

Steps A → E must finish before F. F is ~30 min of Flutter work.

---

## 5. Step A — Mobile owner: extract SHA256 fingerprints

You need **two** fingerprints — one from the release keystore (for production users), one from the debug keystore (for testing during development). Both go in the same `assetlinks.json` file.

### Release fingerprint

In PowerShell from the project root:

```powershell
keytool -list -v -keystore android/app/key.jks -alias <your-alias>
```

The alias is in `android/key.properties` (look for `keyAlias=...`). It'll prompt for the keystore password (also in `key.properties` as `storePassword`).

Copy the **SHA256** line. It looks like:

```
SHA256: 14:6D:E9:83:C5:73:06:50:D8:EE:B9:95:2F:34:FC:64:16:A0:83:42:1A:E3:6F:71:18:18:30:74:DB:00:5E:36
```

### Debug fingerprint

```powershell
keytool -list -v -keystore $env:USERPROFILE\.android\debug.keystore -alias androiddebugkey -storepass android -keypass android
```

Same — grab the SHA256 line.

### Give both to the backend dev

Send them:

```
Release SHA256: 14:6D:E9:83:...
Debug SHA256:   A1:B2:C3:D4:...
Package name:   com.mecpl.hrms
```

---

## 6. Step B — Backend: host `assetlinks.json`

### The file

Create `assetlinks.json` with both fingerprints:

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.mecpl.hrms",
      "sha256_cert_fingerprints": [
        "14:6D:E9:83:C5:73:06:50:D8:EE:B9:95:2F:34:FC:64:16:A0:83:42:1A:E3:6F:71:18:18:30:74:DB:00:5E:36",
        "A1:B2:C3:D4:E5:F6:...:replace-with-debug-fingerprint"
      ]
    }
  }
]
```

Replace the placeholder fingerprints with the real ones from Step A.

### Where to host it

It must be reachable at **exactly** this URL:

```
https://hrms.mecpl.in/.well-known/assetlinks.json
```

Requirements:
- ✅ HTTPS (TLS valid, not self-signed)
- ✅ Status `200 OK`
- ✅ Content-Type `application/json`
- ✅ **No redirects** (a `301` to `www.hrms.mecpl.in` will break verification)
- ✅ Publicly accessible — no auth, no Cloudflare bot challenge, no firewall blocks for Google's verifier
- ✅ Same domain as the URLs you want to deep-link (no CNAME aliases)

### Laravel route to serve it

The simplest way — register a route that returns the JSON:

```php
// routes/web.php

Route::get('/.well-known/assetlinks.json', function () {
    return response()->json([
        [
            'relation' => ['delegate_permission/common.handle_all_urls'],
            'target' => [
                'namespace' => 'android_app',
                'package_name' => 'com.mecpl.hrms',
                'sha256_cert_fingerprints' => [
                    config('app.android_release_fingerprint'),
                    config('app.android_debug_fingerprint'),
                ],
            ],
        ],
    ]);
});
```

In `config/app.php`:

```php
'android_release_fingerprint' => env('ANDROID_RELEASE_FINGERPRINT'),
'android_debug_fingerprint' => env('ANDROID_DEBUG_FINGERPRINT'),
```

In `.env`:

```env
ANDROID_RELEASE_FINGERPRINT="14:6D:E9:83:..."
ANDROID_DEBUG_FINGERPRINT="A1:B2:C3:D4:..."
```

> **Alternative:** drop a static file at `public/.well-known/assetlinks.json`. Either works. Laravel route is preferred because it's easier to update fingerprints without touching the filesystem.

### Verify it works

After deploying:

```bash
curl -i https://hrms.mecpl.in/.well-known/assetlinks.json
```

Must show:
```
HTTP/2 200
content-type: application/json

[{"relation":["delegate_permission/common.handle_all_urls"], ...
```

If it redirects (301/302), the verifier fails silently. Fix the redirect.

Test it through Google's official tool:

```
https://developers.google.com/digital-asset-links/tools/generator
```

Paste `hrms.mecpl.in` + the package name + a fingerprint → it generates the expected JSON and fetches your file to check it matches.

---

## 7. Step C — Backend: standardise URL structure

Right now your emails probably have links like `https://hrms.mecpl.in/leave-application/view/123?token=...`. For App Links to be predictable, agree on a **path scheme** for each entity that needs deep-linking. Suggested:

| Entity | URL pattern | Example |
|---|---|---|
| Leave application detail | `/leave/{id}` | `https://hrms.mecpl.in/leave/12345` |
| Leave approval action | `/leave/{id}/approve` | `https://hrms.mecpl.in/leave/12345/approve` |
| Regularization request | `/regularization/{id}` | `https://hrms.mecpl.in/regularization/789` |
| Announcement | `/announcement/{id}` | `https://hrms.mecpl.in/announcement/45` |
| All notifications | `/notifications` | `https://hrms.mecpl.in/notifications` |
| User profile | `/profile` | `https://hrms.mecpl.in/profile` |

**Why this matters:** the mobile app declares which paths it handles in its `AndroidManifest.xml`. If backend keeps inventing new URL shapes, the app can't keep up. Lock the schema first.

**Avoid:**
- Query params for resource identity (`?id=123`) — paths are cleaner.
- Multiple domains (`app.hrms.mecpl.in` vs `hrms.mecpl.in`) — pick one.
- Trailing slashes inconsistency — pick `/leave/123` or `/leave/123/`, not both.

---

## 8. Step D — Backend: update email templates

Wherever you generate email content, change the button URLs to the new standardised paths.

### Example — Laravel mail template

Before (Blade `emails/leave-approval.blade.php`):

```blade
<a href="{{ url('/leave-application/view/' . $leave->id . '?token=' . $approvalToken) }}">
    Review & Approve
</a>
```

After:

```blade
<a href="{{ config('app.url') }}/leave/{{ $leave->id }}">
    Review & Approve
</a>
```

The button is now a plain HTTPS link. App will catch it; browser handles it for users without the app.

> **About the approval token:** if your old URL embedded a one-time approval token in the query string (so a manager could approve without logging in), see the appendix — App Links interacts with that, and we need to decide whether to keep the token in the URL or require login in the app.

### Email-client gotcha — link tracking / "safe links"

Some setups wrap outgoing email URLs with tracking redirects:

- Mailchimp/SendGrid: `https://click.mailchimp.com/?u=...&url=https://hrms.mecpl.in/leave/123`
- Microsoft Outlook ATP: `https://eur01.safelinks.protection.outlook.com/?url=https://hrms.mecpl.in/leave/123`

These wrapped URLs do **not** match `hrms.mecpl.in` → Android opens them in the browser → the wrapper finally redirects to your URL → still in the browser. The app is never invoked.

Fixes:
- **Mailchimp/SendGrid**: disable click tracking on the specific button (most providers allow per-link opt-out).
- **Outlook safe links**: less controllable — admins can whitelist your domain in their tenant. Workaround: also send a push notification (FCM) for the same event; mobile users will tap that instead.

---

## 9. Step E — Backend: keep web fallback working

The same URL must continue to serve a usable web page for users who:

- Don't have the app installed
- Are on a desktop computer
- Are on iOS (until we ship the iOS version)
- Have email click-tracking wrappers that defeat App Links

So `https://hrms.mecpl.in/leave/123` should:

- If user is logged into the web → show the leave detail / approval UI (as today).
- If user is not logged in → redirect to web login, then back to the leave page after login.

You don't need to add anything new — just make sure your existing web routes accept the new path shapes. Add a route alias if needed:

```php
// routes/web.php

Route::get('/leave/{id}', [LeaveController::class, 'show'])->name('leave.show');
Route::get('/leave/{id}/approve', [LeaveController::class, 'approve'])->name('leave.approve');
// ...etc
```

---

## 10. Step F — Mobile: Flutter changes

Done by the mobile dev after Steps A–E are complete. Briefly, for awareness:

1. Add `app_links` package to `pubspec.yaml`.
2. Add an `<intent-filter>` block to `AndroidManifest.xml`:

   ```xml
   <intent-filter android:autoVerify="true">
       <action android:name="android.intent.action.VIEW" />
       <category android:name="android.intent.category.DEFAULT" />
       <category android:name="android.intent.category.BROWSABLE" />
       <data android:scheme="https"
             android:host="hrms.mecpl.in" />
   </intent-filter>
   ```

   `autoVerify="true"` is what tells Android to fetch `assetlinks.json` and verify the fingerprints at install time.

3. Listen for incoming links and parse them:
   - `/leave/{id}` → navigate to leave detail screen with that id.
   - `/regularization/{id}` → navigate to regularization screen.
   - etc.

4. Reuse the existing `NotificationService._handleRoute` pattern — same pending-route persistence works for App Links too (so links tapped while logged out resume after login).

This is **~30 min of Flutter work** once the backend pieces are in place.

---

## 11. Testing checklist

### Backend / web side

- [ ] `curl -i https://hrms.mecpl.in/.well-known/assetlinks.json` returns `200 OK` + `application/json` + the expected JSON.
- [ ] No redirects between request and 200 response.
- [ ] Google's [Digital Asset Links tester](https://developers.google.com/digital-asset-links/tools/generator) confirms a match.
- [ ] All deep-link URLs (`/leave/123`, `/regularization/45`, etc.) work in a browser as a fallback.

### Mobile side (mobile dev runs these)

- [ ] Install the release build → check verification status:
  ```bash
  adb shell pm get-app-links com.mecpl.hrms
  ```
  Should show `hrms.mecpl.in: verified`. If it says `none` or `legacy_failure`, assetlinks.json isn't being read correctly.

- [ ] Simulate a link tap:
  ```bash
  adb shell am start -W -a android.intent.action.VIEW -d "https://hrms.mecpl.in/leave/123"
  ```
  Should open the app, not the browser.

- [ ] Email a real leave-approval email to your own phone. Tap the button. App should open to the leave screen.

- [ ] Repeat the above with the app **logged out** — login screen should appear, then after login, deep-link target screen should appear (we already built this pending-route handling for FCM).

- [ ] Repeat with the app **fully killed** (swiped from recents) — same expected behavior.

- [ ] Test on a phone where the app is NOT installed — browser opens, web page loads.

---

## 12. iOS Universal Links (later)

Exact same idea, slightly different filenames:

- File: `apple-app-site-association` (no extension)
- Path: `https://hrms.mecpl.in/.well-known/apple-app-site-association`
- Content (JSON, no `.json` extension):

  ```json
  {
    "applinks": {
      "details": [{
        "appIDs": ["TEAMID.com.mecpl.hrms"],
        "components": [
          { "/": "/leave/*" },
          { "/": "/regularization/*" },
          { "/": "/announcement/*" },
          { "/": "/notifications" }
        ]
      }]
    }
  }
  ```

- `TEAMID` is your Apple Developer team ID (visible in Apple Developer portal).
- Xcode: add **Associated Domains** capability with `applinks:hrms.mecpl.in`.
- Same Flutter `app_links` package handles incoming URLs on iOS too.

**Don't do this until you have an Apple Developer account ($99/yr).** Same dependency as the FCM iOS setup.

---

## 13. Common pitfalls

### Pitfall 1 — Redirect on `.well-known/assetlinks.json`

If your server redirects (e.g. `www.hrms.mecpl.in` → `hrms.mecpl.in`, or HTTP → HTTPS), and the assetlinks.json fetch hits the redirect, **Android silently disables verification**. The user gets the chooser ("Open with:") or just the browser.

Fix: serve assetlinks.json at the canonical domain only, with a direct 200 response.

### Pitfall 2 — Wrong content-type

If your Laravel route returns JSON but with `text/html` content-type, Google's verifier may still accept it but some Android versions reject it. Stick with `application/json` (Laravel's `response()->json()` does this automatically).

### Pitfall 3 — Both fingerprints not listed

You need:
- **Release fingerprint** — for production users with the signed APK from Play Store.
- **Debug fingerprint** — for testing during development (otherwise the app on your dev phone won't deep-link, and you'll waste hours wondering why).

After you ship to Play Store, **Play App Signing rotates the signing key** — you'll then need to add a **third fingerprint** (the Play-signed one) too. Source: Play Console → Setup → App signing → Get the SHA256 from there.

### Pitfall 4 — Verification doesn't auto-retry

If `assetlinks.json` is broken when the user installs the app, Android caches the failure. Even if you fix it later, the app won't re-verify until:
- User clears the app's data, or
- User reinstalls the app, or
- You manually trigger: `adb shell pm verify-app-links --re-verify com.mecpl.hrms`

So: **fix and verify assetlinks.json BEFORE telling real users to install the app**.

### Pitfall 5 — Email client kills the app launch

Some email apps (Outlook Android) preview-fetch URLs in the background. This can:
- Open your app in the background → user is confused.
- Trigger your approval action if the URL itself acts on the resource (this is why approval should require an in-app tap, never a GET request).

The fix is on your end (don't make GET requests perform actions) — see [Appendix](#15-appendix--authentication-on-the-deep-linked-url).

---

## 14. Security notes

- **`assetlinks.json` is public.** It must be world-readable, no auth. The fingerprints in it are not secrets (they're already in your APK).
- **Deep-link URLs are not authenticated by Android.** Anyone can craft a URL like `https://hrms.mecpl.in/leave/12345/approve` and send it to a user. The fact that the URL opens the app does **not** mean the user has permission to approve that leave. Your backend / app must check auth + authorization when the action is actually performed.
- **Don't put secrets in deep-link URLs.** Tokens in query strings end up in browser history, server logs, and email-tracker URL parameters.
- **GET requests must be safe.** Never let `GET /leave/123/approve` actually approve a leave — anyone (or a link-preview crawler) could trigger it by accident.

---

## 15. Appendix — Authentication on the deep-linked URL

Today's flow (probable, based on the email screenshot):

```
Email → button → web URL with one-time approval token in query string
                 → backend verifies token → shows approval page → manager clicks Approve
```

After App Links, the URL ends up in the mobile app instead. The mobile app doesn't know about the one-time token; it only knows the user's normal session token (Sanctum bearer).

Two options:

### Option 1 (recommended) — Drop the one-time token entirely

- The mobile app uses the normal logged-in session.
- App opens the leave detail screen → user reads it → user taps in-app Approve button → app sends `POST /leaves/update-status` with the bearer token, like any other action.
- Web fallback: web page redirects to web login if user isn't logged in, then shows the page.
- Pro: simpler, more secure (no token-in-URL leakage).
- Con: forces the manager to be logged in.

### Option 2 — Keep the one-time token in the URL

- App parses the token from the query string and uses it to make the approval API call.
- Pro: works even if the user isn't logged in.
- Con: tokens leak via email forwarding, browser history, link-preview bots; also URL-tracking wrappers might break them.

**Strong recommendation: Option 1.** All managers should already have the app installed and stay logged in; the token-in-URL flow is a holdover from when there was no app.

---

## Summary — what to give the backend dev

When you're ready, send them this entire document. The action items, in order:

1. Get fingerprints from you (Step A — you do this).
2. Host `assetlinks.json` (Step B).
3. Standardise URL structure (Step C).
4. Update email templates to use the new URLs (Step D).
5. Verify web fallback still works for non-app users (Step E).

Then ping the mobile dev (me) and I'll do Step F in ~30 min.
