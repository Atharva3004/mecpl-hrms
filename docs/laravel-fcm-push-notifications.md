# Laravel Backend Implementation Guide — FCM Push Notifications

Standalone reference for the Laravel developer. Everything the backend needs to integrate Firebase Cloud Messaging (FCM) so the MECPL HRMS app can receive push notifications in the Android/iOS notification panel — like WhatsApp / Facebook.

**Target stack**: Laravel 10+ (11 preferred), PHP 8.2+, MySQL 8, Laravel Sanctum.

The Flutter side is **already done**. This document describes only what is missing on the backend.

---

## Table of contents

1. [Scope](#1-scope)
2. [Architecture](#2-architecture)
3. [Prerequisites](#3-prerequisites)
4. [Firebase project — service account](#4-firebase-project--service-account)
5. [Composer dependency](#5-composer-dependency)
6. [Configuration (.env)](#6-configuration-env)
7. [Database migration](#7-database-migration)
8. [Eloquent model change](#8-eloquent-model-change)
9. [Update existing login endpoint](#9-update-existing-login-endpoint)
10. [New endpoint — `POST /update-fcm-token`](#10-new-endpoint--post-update-fcm-token)
11. [FCM sender service class](#11-fcm-sender-service-class)
12. [Where to trigger notifications](#12-where-to-trigger-notifications)
13. [Notification payload reference](#13-notification-payload-reference)
14. [Example requests (curl)](#14-example-requests-curl)
15. [Testing checklist](#15-testing-checklist)
16. [Security notes](#16-security-notes)

---

## 1. Scope

**What the backend must deliver:**

1. Receive and store an `fcm_token` from the mobile app on every login.
2. Receive and update an `fcm_token` whenever it rotates mid-session (new endpoint).
3. Send notifications to a specific user's device via Firebase Cloud Messaging when business events happen (leave approved/rejected, announcement posted, regularization decision, etc.).

**What the backend does NOT need to do:**

- Render the notification on the phone — Firebase + the OS handle that.
- Manage notification channels / icons — already configured in the Android app.
- Worry about the user being offline — FCM queues and retries delivery for up to 28 days.

---

## 2. Architecture

```
┌──────────────┐  1. login + fcm_token  ┌──────────────┐
│  MECPL app   │───────────────────────▶│   Laravel    │
│  (phone)     │                        │   backend    │
└──────────────┘                        └──────┬───────┘
       ▲                                       │
       │ 4. push delivered                     │ 2. business event
       │    (panel notification)               │    (leave approved)
       │                                       ▼
┌──────┴──────────────┐                ┌──────────────┐
│ Google FCM servers  │◀───────────────│  POST to FCM │
│                     │  3. forward    │   v1 API     │
└─────────────────────┘                └──────────────┘
```

**Flow on login:**
1. App calls `POST /check_login_api` with credentials **+ a new `fcm_token` field**.
2. Backend stores `fcm_token` on the user row.
3. Backend returns the auth token as before.

**Flow when sending a notification:**
1. Some business event fires (e.g. leave approved).
2. Backend reads the recipient's `fcm_token` from DB.
3. Backend POSTs to FCM v1 API with the token + payload.
4. FCM relays to the device. The OS shows it in the notification panel.
5. User taps → app opens to a specific screen (deep-link via `data` payload).

---

## 3. Prerequisites

- Existing Laravel HRMS backend at `https://hrms.mecpl.in/api`.
- Existing user authentication (Sanctum bearer tokens).
- Composer 2.x.
- PHP `ext-openssl` and `ext-curl` enabled (for Google service-account JWT signing — usually enabled by default).

---

## 4. Firebase project — service account

The backend authenticates with FCM using a Google **service account**, not the app's `google-services.json`.

**One-time setup (do this once, never commit the file):**

1. Open [Firebase Console](https://console.firebase.google.com) → project **MECPL HRMS**.
2. ⚙ (gear icon) → **Project settings** → **Service accounts** tab.
3. Click **Generate new private key** → confirm → a JSON file downloads.
4. Rename it to `firebase-service-account.json`.
5. Copy it to the backend server at `storage/app/firebase/firebase-service-account.json` (any path is fine — it just needs to be readable by PHP and outside `public/`).
6. **Add it to `.gitignore`:**
   ```gitignore
   /storage/app/firebase/firebase-service-account.json
   ```
   ⚠️ **Never commit this file.** Anyone who has it can send notifications as your project. Treat it like a database password.

The JSON contains the project id (e.g. `mecpl-hrms-xxxxx`) — the FCM library reads it automatically, no need to copy manually.

---

## 5. Composer dependency

Use the maintained Kreait Firebase wrapper — it handles all the OAuth2/JWT plumbing so we don't write it from scratch:

```bash
composer require kreait/laravel-firebase
```

This pulls in `kreait/firebase-php` and registers a Laravel service provider automatically (Laravel 10/11 auto-discovery).

Publish the config (optional but recommended so we can edit defaults):

```bash
php artisan vendor:publish --provider="Kreait\Laravel\Firebase\ServiceProvider" --tag=config
```

This creates `config/firebase.php`.

---

## 6. Configuration (.env)

Add to `.env`:

```env
FIREBASE_CREDENTIALS=storage/app/firebase/firebase-service-account.json
```

The Kreait config reads this variable automatically. Path is **relative to the Laravel project root**.

Verify it loads:

```bash
php artisan tinker
>>> app('firebase.messaging')
=> Kreait\Firebase\Messaging\Messaging {#xxx}
```

If you get an error about credentials, the path is wrong or the JSON is unreadable.

---

## 7. Database migration

Add an `fcm_token` column to wherever you currently store device-level data on login. If you have a `device_name` / `os_version` column already on `users`, add it there. Otherwise, on the session/token table.

**Recommended:** put it on the user row (one device per user — the app already enforces single-session-per-employee per the codebase).

Create the migration:

```bash
php artisan make:migration add_fcm_token_to_users_table
```

Migration file:

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            // FCM device token — used by the backend to send push
            // notifications to this user's phone via Firebase Cloud Messaging.
            // Length: Google guarantees <= 4 KB; 255 is plenty in practice but
            // bump to TEXT if you want to be safe.
            $table->string('fcm_token', 255)->nullable()->after('app_version');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('fcm_token');
        });
    }
};
```

Adjust `after('app_version')` to match your existing schema. Then:

```bash
php artisan migrate
```

---

## 8. Eloquent model change

Add `fcm_token` to the fillable list on `app/Models/User.php`:

```php
protected $fillable = [
    // ...existing fields...
    'device_name',
    'os_version',
    'app_version',
    'fcm_token',
];
```

---

## 9. Update existing login endpoint

The login endpoint (`POST /check_login_api`) already accepts `device_name`, `os_version`, `app_version`. The mobile app now also sends `fcm_token` in the same form-data body. Just persist it.

In your existing `LoginController` (or wherever the login logic lives), after a successful credentials check:

```php
public function login(Request $request)
{
    $credentials = $request->validate([
        'emp_code' => 'required|string',
        'password' => 'required|string',
        'device_name' => 'nullable|string',
        'os_version' => 'nullable|string',
        'app_version' => 'nullable|string',
        'fcm_token'  => 'nullable|string|max:255',  // ← NEW
    ]);

    // ... your existing auth logic ...
    $user = User::where('emp_code', $credentials['emp_code'])->first();

    if (! $user || ! Hash::check($credentials['password'], $user->password)) {
        return response()->json([
            'status' => false,
            'message' => 'Incorrect Employee Code or Password',
        ], 401);
    }

    // Update device metadata + FCM token on every login. The token may have
    // changed since last login (app reinstall, data clear).
    $user->update([
        'device_name' => $request->input('device_name'),
        'os_version'  => $request->input('os_version'),
        'app_version' => $request->input('app_version'),
        'fcm_token'   => $request->input('fcm_token'),  // ← NEW
    ]);

    $token = $user->createToken('mobile')->plainTextToken;

    return response()->json([
        'status' => true,
        'token'  => $token,
        'user'   => $user,
    ]);
}
```

That's it for login — the mobile app sends the field; you store it.

---

## 10. New endpoint — `POST /update-fcm-token`

FCM occasionally rotates device tokens (app reinstall, OS data wipe, manual refresh). The mobile app listens for these rotations and posts the new token back via this endpoint.

### Route

In `routes/api.php`:

```php
use App\Http\Controllers\FcmTokenController;

Route::middleware('auth:sanctum')->group(function () {
    // ... existing authenticated routes ...
    Route::post('/update-fcm-token', [FcmTokenController::class, 'update']);
});
```

### Controller

`app/Http/Controllers/FcmTokenController.php`:

```php
<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;

class FcmTokenController extends Controller
{
    public function update(Request $request): JsonResponse
    {
        $request->validate([
            'fcm_token' => 'required|string|max:255',
        ]);

        $user = $request->user();
        $user->update(['fcm_token' => $request->input('fcm_token')]);

        return response()->json([
            'status'  => true,
            'message' => 'FCM token updated',
        ]);
    }
}
```

### Request format the app sends

```http
POST /api/update-fcm-token HTTP/1.1
Host: hrms.mecpl.in
Authorization: Bearer <user's-sanctum-token>
X-API-Key: 170|PYWnnqnt6XwyJT9LpvdMGXqtaqiB6TIN2oQhfwv0
Accept: application/json
Content-Type: application/x-www-form-urlencoded

fcm_token=cXc6...:APA91b...newRotatedToken
```

Response (200):
```json
{ "status": true, "message": "FCM token updated" }
```

---

## 11. FCM sender service class

Create a small service class so all notification-sending code goes through one place. Easier to test and easier to add logging / retries later.

`app/Services/FcmService.php`:

```php
<?php

namespace App\Services;

use Kreait\Firebase\Contract\Messaging;
use Kreait\Firebase\Messaging\AndroidConfig;
use Kreait\Firebase\Messaging\CloudMessage;
use Kreait\Firebase\Messaging\Notification;
use Kreait\Firebase\Exception\Messaging\NotFound;
use Illuminate\Support\Facades\Log;

class FcmService
{
    public function __construct(private readonly Messaging $messaging) {}

    /**
     * Sends a push notification to a single device.
     *
     * @param  string  $fcmToken    The recipient's stored fcm_token.
     * @param  string  $title       Bold line shown in the notification panel.
     * @param  string  $body        Detail line below the title.
     * @param  array   $data        Custom data — used by the app to deep-link.
     *                              See the "Notification payload reference"
     *                              section for supported routes.
     * @return bool                 True on success, false on any failure
     *                              (logged but never throws to the caller).
     */
    public function sendToDevice(
        string $fcmToken,
        string $title,
        string $body,
        array $data = []
    ): bool {
        try {
            // FCM `data` values must be strings — coerce just in case.
            $data = array_map(fn ($v) => (string) $v, $data);

            $message = CloudMessage::withTarget('token', $fcmToken)
                ->withNotification(Notification::create($title, $body))
                ->withData($data)
                ->withAndroidConfig(AndroidConfig::fromArray([
                    'priority' => 'high',
                    'notification' => [
                        // Must match `_channelId` in the Flutter app's
                        // notification_service.dart and the meta-data in
                        // AndroidManifest.xml.
                        'channel_id' => 'mecpl_default',
                    ],
                ]));

            $this->messaging->send($message);
            return true;

        } catch (NotFound $e) {
            // Token is invalid / unregistered — phone uninstalled the app or
            // wiped data. Clear it from our DB so we stop trying.
            Log::warning("FCM token no longer valid, clearing: {$fcmToken}");
            \App\Models\User::where('fcm_token', $fcmToken)
                ->update(['fcm_token' => null]);
            return false;

        } catch (\Throwable $e) {
            Log::error('FCM send failed', [
                'token' => substr($fcmToken, 0, 12) . '...',
                'error' => $e->getMessage(),
            ]);
            return false;
        }
    }

    /**
     * Convenience — looks up the user's stored token and sends. Returns
     * false if the user has no token (never logged in on a phone, or token
     * was cleared after the device uninstalled).
     */
    public function sendToUser(
        \App\Models\User $user,
        string $title,
        string $body,
        array $data = []
    ): bool {
        if (empty($user->fcm_token)) {
            return false;
        }
        return $this->sendToDevice($user->fcm_token, $title, $body, $data);
    }
}
```

Register it in `app/Providers/AppServiceProvider.php` if you want explicit binding, but Laravel's auto-resolution will work fine because the constructor only depends on `Messaging` (which Kreait already binds).

---

## 12. Where to trigger notifications

Inject `FcmService` wherever business events happen and call `sendToUser()`. Typical hook points for HRMS:

### a) Leave approved / rejected

```php
// LeaveApprovalController@updateStatus
$leaveApplication->update(['status' => $newStatus]);

app(FcmService::class)->sendToUser(
    $leaveApplication->employee,
    title: $newStatus === 'approved' ? 'Leave approved ✅' : 'Leave rejected',
    body: "Your {$leaveApplication->days}-day leave from "
        . "{$leaveApplication->from_date} has been {$newStatus}",
    data: ['route' => 'tab', 'tab' => 'leave'],
);
```

### b) Attendance regularization decision

```php
app(FcmService::class)->sendToUser(
    $request->employee,
    title: 'Regularization ' . $decision,
    body: "Your attendance correction for {$request->date} was {$decision}",
    data: ['route' => 'tab', 'tab' => 'attendance'],
);
```

### c) New announcement / notice

```php
foreach (User::whereNotNull('fcm_token')->cursor() as $user) {
    app(FcmService::class)->sendToUser(
        $user,
        title: $announcement->title,
        body: $announcement->summary,
        data: ['route' => 'notifications'],
    );
}
```

> 📌 For broadcasts to many users, prefer **FCM topics** instead of looping. Subscribe each device to a topic on login (e.g. `all_employees`, `branch_42`) and send one message to the topic. We can add this later — for now, looping is fine for the HRMS user count.

### d) Punch-out reminder (cron-driven)

```php
// app/Console/Kernel.php — schedule()
$schedule->call(function () {
    User::whereHas('activeSession', fn ($q) =>
        $q->where('punched_in_at', '<', now()->subHours(9)))
        ->whereNotNull('fcm_token')
        ->each(fn ($u) => app(FcmService::class)->sendToUser(
            $u,
            title: 'Punch-out reminder',
            body: "You've been punched in for over 9 hours",
            data: ['route' => 'tab', 'tab' => 'attendance'],
        ));
})->dailyAt('19:00');
```

### Should we use queues?

For one-off sends (leave approval), inline calls are fine — FCM responds in <500ms.

For bulk broadcasts (announcement to all employees), dispatch a queued job:

```php
SendAnnouncementJob::dispatch($announcement);
```

so the HTTP request returns immediately and the actual sending happens in `php artisan queue:work`.

---

## 13. Notification payload reference

The Flutter app understands these `data` payloads. Send any of them via the `data` field of the FCM message. Anything not listed here will just open the app to its last screen.

| `data` payload                              | What the app does                  |
|---|---|
| `{ "route": "notifications" }`              | Pushes the in-app NotificationScreen |
| `{ "route": "tab", "tab": "dashboard" }`    | Switches bottom-nav to Dashboard   |
| `{ "route": "tab", "tab": "attendance" }`   | Switches bottom-nav to Attendance  |
| `{ "route": "tab", "tab": "leave" }`        | Switches bottom-nav to Leave       |
| `{ "route": "tab", "tab": "profile" }`      | Switches bottom-nav to Profile     |
| (empty / no `route`)                        | Just opens the app                 |

To add new routes, ask the Flutter dev to extend the `_handleRoute()` switch in `lib/services/notification_service.dart`.

**FCM rule:** `data` values must always be **strings**. The `FcmService` already coerces them, so passing integers from PHP is fine — they get cast.

### Notification body fields

The notification panel renders only:
- **`notification.title`** — bold first line
- **`notification.body`** — second/third line, gets truncated past ~120 chars

Keep the title under 50 chars and the body under 120 for best UX.

### Channel id (Android)

Always set `android.notification.channel_id` to **`mecpl_default`**. If you forget, Android 8+ may use a default channel that doesn't match the app's settings (no sound, no heads-up).

---

## 14. Example requests (curl)

### Login (existing endpoint, new field)

```bash
curl -X POST https://hrms.mecpl.in/api/check_login_api \
  -H "X-API-Key: 170|PYWnnqnt6XwyJT9LpvdMGXqtaqiB6TIN2oQhfwv0" \
  -H "Accept: application/json" \
  -F "emp_code=EMP001" \
  -F "password=secret123" \
  -F "device_name=Pixel 9" \
  -F "os_version=Android 15" \
  -F "app_version=1.0.9+10" \
  -F "fcm_token=cXc6...:APA91b...veryLongString"
```

### Update FCM token (new endpoint)

```bash
curl -X POST https://hrms.mecpl.in/api/update-fcm-token \
  -H "X-API-Key: 170|PYWnnqnt6XwyJT9LpvdMGXqtaqiB6TIN2oQhfwv0" \
  -H "Authorization: Bearer 1|aBcDeF...sanctumToken" \
  -H "Accept: application/json" \
  -F "fcm_token=newRotatedTokenFromTheApp"
```

### Manual test send (server-side, via tinker)

```bash
php artisan tinker
```

```php
>>> $u = App\Models\User::find(1);
>>> app(App\Services\FcmService::class)->sendToUser(
...     $u,
...     'Backend test',
...     'If you see this, server-side FCM works',
...     ['route' => 'notifications']
... );
=> true
```

The phone should buzz within a few seconds. If you get `false` and a "FCM token no longer valid" log line, the user needs to log in again on the phone to re-register.

---

## 15. Testing checklist

Before considering this done, confirm each of these:

- [ ] `composer require kreait/laravel-firebase` succeeded; `php artisan tinker` can resolve `app('firebase.messaging')` without error.
- [ ] `firebase-service-account.json` is at the configured path **and listed in `.gitignore`**.
- [ ] Migration ran; `users.fcm_token` column exists.
- [ ] `User` model has `fcm_token` in `$fillable`.
- [ ] Login endpoint stores `fcm_token` from the request (verify by logging in from the app, then `SELECT emp_code, fcm_token FROM users WHERE emp_code='...';`).
- [ ] `POST /update-fcm-token` returns 200 with bearer auth, 401 without.
- [ ] `FcmService::sendToUser($user, ...)` from tinker results in a notification appearing on the test phone.
- [ ] Tapping the notification opens the right screen (test each `data` route).
- [ ] An invalid token returns false from `sendToDevice` and clears the column (don't crash the request).
- [ ] Bulk announcement loop completes without timing out (or moved to a queued job).

---

## 16. Security notes

- **Service-account JSON is a credential.** Anyone with it can send arbitrary push notifications appearing as MECPL HRMS. Treat it like a database password:
  - Never commit to git.
  - Don't paste into Slack/email — share via your secrets manager (1Password, AWS Secrets Manager, etc.).
  - File permissions on the server: `chmod 600`, owned by the PHP-FPM user only.

- **FCM tokens are not secrets** in the cryptographic sense, but they are personal device identifiers. Don't log them in plain text in shared logs (the example above truncates to 12 chars).

- **Don't trust the `fcm_token` field in the login request blindly.** It's already validated as a string ≤ 255 chars in the controller — keep that validation.

- **Rate-limit `POST /update-fcm-token`** if you're worried about abuse. A reasonable limit is 10 requests/minute per user (it should fire at most a few times a year per device):

  ```php
  Route::middleware(['auth:sanctum', 'throttle:10,1'])->group(...);
  ```

- **Don't broadcast notifications to all users casually.** Even a 5-employee announcement to 1,000 users = 1,000 push messages from Google's perspective. Use FCM topics for org-wide broadcasts once we set them up.

---

## Appendix: Why Kreait and not raw cURL?

You can talk to FCM v1 without a library — but you'd need to:

1. Read the service-account JSON.
2. Create a JWT signed with the private key from the JSON.
3. Exchange that JWT for a Google OAuth2 access token (1-hour TTL — needs caching).
4. POST to `https://fcm.googleapis.com/v1/projects/<project-id>/messages:send` with the access token in the Authorization header.
5. Refresh the access token before it expires.

Kreait does all of that for you and is the de-facto Laravel FCM library. It's worth the dependency.

If you absolutely cannot add a dependency, ask the Flutter team for the raw-cURL version — it's about 60 lines of PHP using `firebase/php-jwt` for the JWT signing.
