# Laravel Backend — Admin Notifications for All Pending Approvals

Standalone reference for the Laravel developer. **Goal:** every time something gets submitted that needs admin/manager approval, **all admins receive a push notification** so they can act on it. This covers three workflows in MECPL HRMS:

1. **Leave applications** — when an employee submits a new leave request.
2. **Attendance regularization** — when an employee submits an attendance correction request.
3. **Employee onboarding** — when a new onboarding is submitted.

**Prerequisite:** you've already implemented `laravel-fcm-push-notifications.md` — the `FcmService` class exists and the manual tinker test reaches a phone. This doc only tells you *where* and *how* to invoke it.

---

## Table of contents

1. [Scope](#1-scope)
2. [The shared `notifyAdmins()` helper](#2-the-shared-notifyadmins-helper)
3. [Event 1 — Leave application submitted](#3-event-1--leave-application-submitted)
4. [Event 2 — Regularization request submitted](#4-event-2--regularization-request-submitted)
5. [Event 3 — Onboarding submitted](#5-event-3--onboarding-submitted)
6. [Payload reference](#6-payload-reference--what-the-mobile-app-understands)
7. [Verification — test each event end-to-end](#7-verification--test-each-event-end-to-end)
8. [Troubleshooting](#8-troubleshooting)
9. [Important reminders](#9-important-reminders)

---

## 1. Scope

**Rule:** every user with `role = 'ADMIN'` (and a non-null `fcm_token`) receives a notification for every pending-approval event. No de-duplication — if the admin is also the submitter or approver, they still get the notification. The user has approved this behavior.

**This doc only covers "pending" / new-submission events** (where admin sees there's something new to act on). Notifications for "approved" and "rejected" outcomes on leave are already documented in `laravel-leave-notifications.md` — keep those hooks in place.

| # | Event | Admin's notification text | Tap opens |
|---|---|---|---|
| 1 | Leave submitted | "New leave request — [Employee] applied for [N] day(s) leave from [date]" | LeaveApprovalScreen |
| 2 | Regularization submitted | "Regularization request — [Employee] requested attendance correction for [date]" | RegularizationApprovalScreen |
| 3 | Onboarding submitted | "New onboarding approval — [Submitter] submitted a new employee onboarding pending approval" | EmployeeOnboardingApprovalScreen |

---

## 2. The shared `notifyAdmins()` helper

All three events use the same helper. Put this **once** in a place all three controllers can reach. Two options:

### Option A (recommended) — Trait

`app/Http/Controllers/Concerns/NotifiesAdmins.php`:

```php
<?php

namespace App\Http\Controllers\Concerns;

use App\Models\EmployeeModel;
use App\Services\FcmService;

trait NotifiesAdmins
{
    /**
     * Push-notify every admin about a pending-approval event.
     *
     * - Filters by `role = 'ADMIN'` (adjust if your role column uses a
     *   different string — check with `SELECT DISTINCT role FROM employees`).
     * - Skips admins without an FCM token (haven't logged in on a phone).
     * - No de-duplication: an admin who is also the submitter/approver
     *   still receives the notification (per product decision).
     */
    protected function notifyAdmins(string $title, string $body, array $data): void
    {
        $admins = EmployeeModel::where('role', 'ADMIN')
            ->whereNotNull('fcm_token')
            ->get();

        foreach ($admins as $admin) {
            app(FcmService::class)->sendToUser($admin, $title, $body, $data);
        }
    }
}
```

Then in each controller (`LeaveController`, `RegularizationController`, `OnboardingController`):

```php
use App\Http\Controllers\Concerns\NotifiesAdmins;

class LeaveController extends Controller
{
    use NotifiesAdmins;
    // ... rest of the controller
}
```

### Option B (quick) — Private method per controller

If you're in a hurry, just paste the body of `notifyAdmins()` as a `private function notifyAdmins(...)` inside each of the three controllers. Functionally identical; Option A is just cleaner.

---

## 3. Event 1 — Leave application submitted

**Endpoint:** `POST /leaves/store-leave`
**Controller (likely):** `LeaveController@store` or `LeaveApplicationController@store`

### Where to add the hook

Find the line where the leave row is saved (`$leave = LeaveApplication::create([...])` or similar). The notification block goes immediately after the save succeeds.

### Code to add

```php
use App\Models\EmployeeModel;
use App\Services\FcmService;

// ... after $leave is saved successfully ...

$employee = $leave->employee;
$approver = EmployeeModel::find($leave->approver_id); // adjust lookup

// Primary: the assigned approver (existing hook from laravel-leave-notifications.md).
if ($approver && $approver->fcm_token) {
    app(FcmService::class)->sendToUser(
        $approver,
        'Leave pending your approval',
        "{$employee->name} requested {$leave->days} day(s) leave from {$leave->from_date}",
        ['route' => 'leave_approvals', 'leave_id' => (string) $leave->id]
    );
}

// CC every admin.
$this->notifyAdmins(
    'New leave request',
    "{$employee->name} applied for {$leave->days} day(s) leave from {$leave->from_date}",
    ['route' => 'leave_approvals', 'leave_id' => (string) $leave->id]
);
```

---

## 4. Event 2 — Regularization request submitted

**Endpoint:** `POST /submit_regularization_request`
**Controller (likely):** `RegularizationController@store` or `AttendanceRegularizationController@store`

### Where to add the hook

After the regularization row is saved (`$regularization = AttendanceRegularization::create([...])` or similar).

### Code to add

```php
use App\Models\EmployeeModel;
use App\Services\FcmService;

// ... after $regularization is saved successfully ...

$employee = $regularization->employee;
$approver = EmployeeModel::find($regularization->approver_id); // adjust lookup

// Primary: the assigned approver.
if ($approver && $approver->fcm_token) {
    app(FcmService::class)->sendToUser(
        $approver,
        'Regularization pending your approval',
        "{$employee->name} requested attendance correction for {$regularization->date}",
        ['route' => 'regularization_approvals', 'regularization_id' => (string) $regularization->id]
    );
}

// CC every admin.
$this->notifyAdmins(
    'New regularization request',
    "{$employee->name} requested attendance correction for {$regularization->date}",
    ['route' => 'regularization_approvals', 'regularization_id' => (string) $regularization->id]
);
```

---

## 5. Event 3 — Onboarding submitted

**Endpoint:** `POST /employeeOnboardingApproval` (per `api_constants.dart`)
**Controller (likely):** `OnboardingController@store` or `EmployeeOnboardingController@submit`

### Where to add the hook

After the new onboarding row is saved with status `pending` (or equivalent).

Onboarding is typically admin-reviewed only — there isn't usually a separate "approver" outside the admin pool. So in this case the admin CC IS the primary notification. If you do have a dedicated reviewer outside admins, notify them first, then CC admins.

### Code to add

```php
use App\Models\EmployeeModel;
use App\Services\FcmService;

// ... after $onboarding (or $newEmployee) is saved with status pending ...

$submittedBy = auth()->user();

$this->notifyAdmins(
    'New onboarding approval',
    "{$submittedBy->name} submitted a new employee onboarding pending approval",
    ['route' => 'onboarding_approvals', 'onboarding_id' => (string) $onboarding->id]
);
```

---

## 6. Payload reference — what the mobile app understands

These `data` payloads are recognised by the Flutter app. Anything else is silently ignored (app still opens normally, just doesn't deep-link).

| `data['route']` | Mobile screen that opens |
|---|---|
| `leave_approvals` | LeaveApprovalScreen — pending leave requests list |
| `regularization_approvals` | RegularizationApprovalScreen — pending regularizations |
| `onboarding_approvals` | EmployeeOnboardingApprovalScreen — pending onboardings |
| `leave_history` | LeaveHistoryScreen — employee's own leaves |
| `notifications` | In-app notifications list |
| `tab` + `tab: <name>` | Bottom-nav switch — `dashboard` / `attendance` / `leave` / `profile` |

Including extra keys like `leave_id`, `regularization_id`, `onboarding_id` is **safe and recommended** — the app ignores them today but we'll use them later for deep-linking to specific records.

**FCM payload rule:** all `data` values must be strings. Always cast IDs: `(string) $leave->id` — not bare integers. Kreait throws a validation error otherwise.

---

## 7. Verification — test each event end-to-end

Coordinate with whoever has admin login + a test phone. For each event:

### Test 1 — Leave submitted

1. Admin user logs in fresh on their phone → backgrounds the app.
2. Some other employee (or admin themselves, from web) submits a new leave application.
3. Admin's phone should buzz within 30 seconds with notification: **"New leave request — [Employee] applied for [N] day(s) leave from [date]"**.
4. Tap → app opens to **LeaveApprovalScreen**.

### Test 2 — Regularization submitted

1. Admin remains backgrounded on their phone.
2. Submit a new attendance regularization from web.
3. Admin's phone should buzz with **"New regularization request — [Employee] requested attendance correction for [date]"**.
4. Tap → app opens to **RegularizationApprovalScreen**.

### Test 3 — Onboarding submitted

1. Admin remains backgrounded.
2. Submit a new employee onboarding from web.
3. Admin's phone should buzz with **"New onboarding approval — [Submitter] submitted a new employee onboarding pending approval"**.
4. Tap → app opens to **EmployeeOnboardingApprovalScreen**.

### Reporting template

Reply with this filled in:

```
Test 1 (leave submitted → admin):           PASS / FAIL
Test 2 (regularization submitted → admin):  PASS / FAIL
Test 3 (onboarding submitted → admin):      PASS / FAIL

Notes (any errors or unexpected behavior):
```

---

## 8. Troubleshooting

If a test fails, work through these in order:

### 8a — Confirm any admin has an FCM token

```sql
SELECT id, name, role, LENGTH(fcm_token) AS token_len
FROM employees
WHERE role = 'ADMIN';
```

If `token_len` is `NULL` or `0` for everyone → no admin has logged in on a phone yet. The notification has nowhere to go. Have an admin log in on a phone first.

### 8b — Confirm the hook is firing

Add a log line right before each `notifyAdmins()` call:

```php
\Log::info('[FCM hook] event=leave_submitted', [
    'leave_id' => $leave->id,
    'admin_count' => EmployeeModel::where('role', 'ADMIN')
        ->whereNotNull('fcm_token')->count(),
]);
$this->notifyAdmins(...);
```

Trigger the action, then `tail -n 50 storage/logs/laravel.log`:

- **Log line missing entirely** → the controller method isn't being reached. Wrong endpoint, wrong controller, or you're editing the wrong file.
- **Log line present, `admin_count: 0`** → no admins have FCM tokens. See 8a.
- **Log line present, `admin_count > 0`, but no notification** → FcmService is failing. Check logs for `FCM send failed` entries.

### 8c — Confirm the role string matches

The helper filters `where('role', 'ADMIN')`. Verify what's actually in your DB:

```sql
SELECT DISTINCT role FROM employees;
```

If admins are stored as `'Admin'` (mixed case) or `'super_admin'` or `'admin'` (lowercase), edit the helper accordingly. The user's login response showed `"role": "ADMIN"` so this should be fine — but worth verifying.

### 8d — Inspect FcmService logs

If `[FCM hook]` log shows `admin_count > 0` but phones don't receive, look for FcmService internal errors:

```bash
tail -n 100 storage/logs/laravel.log | grep -i fcm
```

Common errors:
- `messaging/registration-token-not-registered` → admin's token is stale; they need to log out + log back in on the phone.
- `403 Forbidden` from FCM → service-account JSON lacks the Cloud Messaging API permission.
- `Failed to read credentials` → `FIREBASE_CREDENTIALS` env var path is wrong.

---

## 9. Important reminders

1. **`role` value matches.** Use whatever string is actually in the DB (run `SELECT DISTINCT role`). Default in this doc is `'ADMIN'` (uppercase).
2. **Admin must have logged in on a phone at least once** — otherwise `fcm_token` is NULL and they receive nothing. Web-only admins won't get push notifications, by design.
3. **No de-duplication** — admin who is also the submitter/approver still gets the notification. This is intentional and approved by the user.
4. **FCM data values must be strings** — always cast IDs.
5. **Wrap optional recipients in null-checks** — `if ($approver && $approver->fcm_token)` to avoid crashes when the lookup returns null.
6. **Don't break the API response if FCM fails** — `FcmService::sendToUser` already swallows exceptions internally, so calling it shouldn't crash the request. But don't add new `try/catch` around it that masks other bugs.
7. **Existing leave-approval / leave-rejected hooks remain in place** — this doc only adds the *pending* notification on submit. Don't remove the approved/rejected hooks added previously per `laravel-leave-notifications.md`.

---

## Quick task list for the dev

- [ ] Add the `NotifiesAdmins` trait (Section 2, Option A) or paste the private method into three controllers (Option B).
- [ ] Hook into Leave submission controller (Section 3).
- [ ] Hook into Regularization submission controller (Section 4).
- [ ] Hook into Onboarding submission controller (Section 5).
- [ ] Run Tests 1, 2, 3 from Section 7 and send results.

That's it. Once all three tests pass, admins will receive a push for every pending approval across all three workflows.
