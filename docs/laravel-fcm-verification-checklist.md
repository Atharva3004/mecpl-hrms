# Laravel FCM Push Notifications — Verification Checklist

**For the backend developer.** Read this after you've implemented `laravel-fcm-push-notifications.md`. Run every check in order. Each one rules out a specific failure mode. **Paste the actual output / screenshots back to whoever asked you to verify.**

> Don't skip any check. "It looks right" is not verification — only the output of these commands is.

If any check fails, stop and fix it before continuing. Each later check assumes the earlier ones pass.

---

## Reporting format

For every check below, send back:

```
Check N — <name>
Status: PASS / FAIL
Output:
<paste the exact command output, screenshot, or error message>
```

Do this for **all 10 checks**, even the passing ones. We need to see the output to confirm.

---

## Check 1 — Composer dependency installed

**Run:**
```bash
composer show kreait/laravel-firebase
```

**Expected:** a block of text showing `name`, `descrip.`, `versions`, etc. of the installed package.

**If you get:** `Package kreait/laravel-firebase not found` → run `composer require kreait/laravel-firebase` and retry.

---

## Check 2 — Service account JSON is in place and readable

**Run:**
```bash
ls -la storage/app/firebase/firebase-service-account.json
cat storage/app/firebase/firebase-service-account.json | head -c 100
```

**Expected:**
- First command shows the file exists with `-rw-r-----` or similar permissions, owned by the PHP-FPM user.
- Second command prints the first 100 chars — should start with `{"type":"service_account","project_id":"mecpl-`...

**If file doesn't exist** → place it at this path. Get the JSON from whoever has the keys.
**If permission denied** → `chown www-data:www-data` and `chmod 640` (adjust user as needed).
**If `project_id` doesn't start with `mecpl-`** → wrong service account; you have one for a different project.

---

## Check 3 — `.env` points at the file

**Run:**
```bash
grep FIREBASE_CREDENTIALS .env
```

**Expected:**
```
FIREBASE_CREDENTIALS=storage/app/firebase/firebase-service-account.json
```

**If empty or wrong path** → add/fix the line. Then run `php artisan config:clear`.

---

## Check 4 — Laravel can resolve the Firebase Messaging service

**Run:**
```bash
php artisan tinker
```

In tinker:
```php
app('firebase.messaging')
```

**Expected:**
```
=> Kreait\Firebase\Messaging\Messaging {#xxx}
```

**If it errors** → most common: path in `FIREBASE_CREDENTIALS` is wrong, or `php artisan config:clear` wasn't run after editing `.env`.

Exit tinker with `exit`.

---

## Check 5 — Migration ran (database has the column)

**Run:**
```bash
php artisan migrate:status | grep fcm_token
```

**Expected:** a row showing `Ran` for `add_fcm_token_to_users_table` (or whatever you named the migration).

Then run:
```bash
php artisan tinker
```
```php
\Schema::hasColumn('users', 'fcm_token');
```

**Expected:** `true`.

**If false or migration not in the list** → run `php artisan migrate` on the right environment.

---

## Check 6 — `User` model accepts the field

**Run:**
```bash
grep -n "fcm_token" app/Models/User.php
```

**Expected:** at least one line showing `'fcm_token'` inside the `$fillable` array.

**If no output** → add `'fcm_token'` to `$fillable` on the `User` model.

---

## Check 7 — Login endpoint persists `fcm_token`

This needs a real login from the mobile app. Coordinate with the mobile-side person: ask them to **log out, then log in fresh** on their phone.

Then:

```bash
php artisan tinker
```
```php
$u = App\Models\User::where('emp_code', '<EMP_CODE>')->first();
echo 'Token length: ' . strlen($u->fcm_token ?? '');
echo PHP_EOL;
echo 'Token preview: ' . substr($u->fcm_token ?? '(null)', 0, 25) . '...';
```

Replace `<EMP_CODE>` with the actual employee code of whoever is testing on the phone.

**Expected:**
```
Token length: 152
Token preview: c-VPbMKjQwyaHtn7M2v6tA:AP...
```

(Length is typically 140–170 chars. Anything > 100 is fine.)

**If `Token length: 0`** → login endpoint isn't storing the field. Two likely causes:
1. `fcm_token` isn't in `$fillable` on `User` model (Check 6 missed it).
2. Login controller validates `fcm_token` but doesn't persist it. Check the `update()` call after credential check — must include `'fcm_token' => $request->input('fcm_token')`.

---

## Check 8 — FcmService class exists

**Run:**
```bash
ls -la app/Services/FcmService.php
grep -n "function sendToUser" app/Services/FcmService.php
```

**Expected:**
- File exists.
- Method signature `function sendToUser(...)` shows up.

**If file doesn't exist** → create it per Section 11 of `laravel-fcm-push-notifications.md`.

---

## Check 9 — End-to-end manual send works

This is the **single most important check.** Before doing this:
- Ask the phone user to **log in fresh** on the phone (so Check 7's token is current).
- Ask them to **press the home button** to background the app (do NOT kill it).

Then on the server:

```bash
php artisan tinker
```
```php
$u = App\Models\User::where('emp_code', '<EMP_CODE>')->first();
$result = app(App\Services\FcmService::class)->sendToUser(
    $u,
    'Verification check 9',
    'If you see this, FcmService works',
    ['route' => 'notifications']
);
var_dump($result);
```

**Expected:**
1. Tinker prints `bool(true)`.
2. **Phone receives a notification within 30 seconds** with title "Verification check 9".
3. Tapping the notification opens the MECPL HRMS app on the Notifications screen.

| Result | Diagnosis |
|---|---|
| `bool(true)` + phone shows notification | ✅ Service works end-to-end. Skip to Check 10. |
| `bool(true)` but **no notification on phone** | Token in DB is stale or wrong. Redo Check 7 with a fresh login on the phone. |
| `bool(false)` | FcmService caught an exception. Continue to "If Check 9 fails" below. |

### If Check 9 fails

Read the log:
```bash
tail -n 80 storage/logs/laravel.log
```

Look for the most recent `FCM send failed` entry. Common errors and fixes:

| Log message contains | Cause | Fix |
|---|---|---|
| `Failed to read credentials` | Wrong path in `.env` or file not readable | Re-do Checks 2 & 3 |
| `403 Forbidden` from FCM | Service account lacks the Firebase Cloud Messaging API permission | Enable it in Google Cloud Console → APIs & Services |
| `404 Not Found` from FCM | Service account JSON is for a different Firebase project than the one the app talks to | Re-download the correct one from MECPL HRMS Firebase project → Service Accounts |
| `messaging/registration-token-not-registered` | Token has been invalidated (user uninstalled, data cleared, or rotated). The FcmService already clears it from DB. | Ask phone user to log in fresh, retry Check 9 |
| `Invalid registration token` | Token mangled during storage (truncated column?) | Verify the `fcm_token` column is `VARCHAR(255)` minimum |
| Anything else | Paste the full log lines back when reporting Check 9 status |

---

## Check 10 — Leave-approval event actually fires the notification

This is the real-world test. The previous checks confirm the plumbing works. This one confirms the plumbing is **connected to the business event**.

### 10a — Find the hook in code

**Run:**
```bash
grep -rn "FcmService" app/Http/Controllers
```

**Expected:** at least one match in the controller that handles leave-status updates (typically `LeaveApprovalController.php` or `LeaveController.php`).

**If zero matches** → you never called `FcmService::sendToUser()` from anywhere except tinker. The leave-approval flow won't send anything. **Add the call** per Section 12a of `laravel-fcm-push-notifications.md`:

```php
// After the leave status update succeeds:
app(\App\Services\FcmService::class)->sendToUser(
    $leaveApplication->employee,
    title: $newStatus === 'approved' ? 'Leave approved ✅' : 'Leave rejected',
    body: "Your {$leaveApplication->days}-day leave from {$leaveApplication->from_date} has been {$newStatus}",
    data: ['route' => 'tab', 'tab' => 'leave'],
);
```

### 10b — Real-world fire test

Coordinate with the phone user:
1. Phone user logs in fresh on the phone, then backgrounds the app.
2. **You** (or anyone with manager permissions on the web) **approve one of that user's leave applications** through the normal web UI.
3. Phone user reports whether the notification arrived.

**Expected:** within 30 seconds of clicking Approve on web, the phone shows a notification like "Leave approved ✅ — Your 2-day leave was approved". Tapping it opens the app on the Leave tab.

**If nothing arrives** even though Check 9 passed: the hook in 10a isn't actually running. Possible reasons:
- The approval action uses a different controller / method than where you added the call.
- The status update is happening but the line after it is being skipped (e.g. inside a `try` block that's swallowing exceptions).
- The recipient lookup is wrong (`$leaveApplication->employee` might be null — `dd($leaveApplication->employee)` to confirm).

Repeat the same exercise for other events you wired:
- Regularization decision
- Announcement broadcast
- Anything else listed in Section 12 of the spec

---

## Final reporting format — copy/paste this back

When all 10 checks are done, send back this filled-in template:

```
=== FCM Verification Report ===

Check 1  (composer):              PASS / FAIL
Check 2  (service-account JSON):  PASS / FAIL
Check 3  (.env):                  PASS / FAIL
Check 4  (Messaging resolves):    PASS / FAIL
Check 5  (migration):             PASS / FAIL
Check 6  (User $fillable):        PASS / FAIL
Check 7  (token in DB):           PASS / FAIL — Token length: ___
Check 8  (FcmService class):      PASS / FAIL
Check 9  (manual send works):     PASS / FAIL — Phone got notification: YES / NO
Check 10a (FcmService called in controllers):  PASS / FAIL — files: ___
Check 10b (real leave approval triggers push): PASS / FAIL

=== Notes ===

<any failures, error messages, or things you had to debug>
```

---

## Reference

- Implementation spec: `laravel-fcm-push-notifications.md`
- Firebase Console: https://console.firebase.google.com (project: MECPL HRMS)
- App package name: `com.mecpl.hrms`
- Notification channel id on the mobile side: `mecpl_default` (must match `android.notification.channel_id` in every FCM payload — see Section 11 of the implementation spec)

If anything is still unclear, paste your failure output + the full `storage/logs/laravel.log` tail and we'll diagnose.
