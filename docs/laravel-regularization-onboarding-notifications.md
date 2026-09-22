# Laravel Backend — Regularization & Onboarding Admin Notifications

Standalone reference for the Laravel developer. **Prerequisite:** you've already completed `laravel-fcm-push-notifications.md` (the `FcmService` class exists) and `laravel-leave-notifications.md` (the `notifyAdmins()` helper exists on a controller). This doc extends notifications to two more workflows:

1. **Attendance regularization requests** — pending state notifies admins.
2. **Employee onboarding** — pending state notifies admins.

Only the **pending/new-submission** event is in scope here — the user hasn't asked for "approved/rejected" notifications on these workflows yet (we can add later if needed).

---

## The two events

| # | Trigger | Recipient | Mobile screen opened on tap |
|---|---|---|---|
| 1 | Employee submits an attendance regularization request | The dedicated approver **+ every admin** | RegularizationApprovalScreen |
| 2 | New employee onboarding submitted | The dedicated approver **+ every admin** | EmployeeOnboardingApprovalScreen |

Same admin-CC rule as the leave events: every user with `role = 'ADMIN'` (and a non-null `fcm_token`) gets the notification, no de-duplication.

---

## Reuse the existing `notifyAdmins()` helper

You added this method in `laravel-leave-notifications.md`:

```php
private function notifyAdmins(string $title, string $body, array $data): void
{
    $admins = EmployeeModel::where('role', 'ADMIN')
        ->whereNotNull('fcm_token')
        ->get();

    foreach ($admins as $admin) {
        app(FcmService::class)->sendToUser($admin, $title, $body, $data);
    }
}
```

If it lives on `LeaveApprovalController`, **either**:

- Copy the method into `RegularizationController` and `OnboardingController` (quick — fine for now), OR
- Move it into a trait `app/Http/Controllers/Concerns/NotifiesAdmins.php` and `use NotifiesAdmins;` in each controller (cleaner — recommended once we have 3+ users of it).

For this doc I'll assume the method is available on whichever controller you're editing.

---

## Event 1 — Regularization request submitted → notify approver + admins

### Where to add the hook

The controller method behind `POST /submit_regularization_request` (from `api_constants.dart` — your dev knows the exact controller name). Likely `AttendanceRegularizationController@store` or similar.

Find the line where the regularization row is saved, then add the notification block immediately after.

### Code to add

```php
use App\Models\EmployeeModel;
use App\Services\FcmService;

// ... after $regularization is saved successfully ...

$employee = $regularization->employee; // adjust relationship name

// Resolve the assigned approver (manager / HR). Adjust the lookup to
// match your business rules — there's typically an approver_id column
// or a relationship via the employee's reporting manager.
$approver = EmployeeModel::find($regularization->approver_id);

if ($approver && $approver->fcm_token) {
    app(FcmService::class)->sendToUser(
        $approver,
        'Regularization request',
        "{$employee->name} requested attendance correction for {$regularization->date}",
        [
            'route' => 'regularization_approvals',
            'regularization_id' => (string) $regularization->id,
        ]
    );
}

// CC every admin for visibility.
$this->notifyAdmins(
    'Regularization request',
    "{$employee->name} requested attendance correction for {$regularization->date}",
    [
        'route' => 'regularization_approvals',
        'regularization_id' => (string) $regularization->id,
    ]
);
```

### What the user sees on their phone

- **Approver**: notification with title *"Regularization request"* and body about the employee + date.
- **Every admin**: same notification.
- Tap → opens **RegularizationApprovalScreen** (pending regularizations list).

---

## Event 2 — New onboarding submitted → notify approver + admins

### Where to add the hook

Wherever a new onboarding row is created and submitted for approval. Likely controller methods behind:
- `/employeeOnboardingApproval` (from `api_constants.dart`)
- Or wherever HR / Admin creates a new employee record that requires further approval

If your onboarding has multiple stages (e.g., "submitted by HR" → "approved by Admin"), fire this notification at the stage that needs admin approval.

### Code to add

```php
use App\Models\EmployeeModel;
use App\Services\FcmService;

// ... after $onboarding (or $newEmployee) is saved with status pending ...

$submittedBy = auth()->user(); // whoever created the onboarding record

// Most onboarding workflows are admin-only — no separate "approver"
// outside the admin pool. If yours has a dedicated reviewer, look them
// up and notify them here. Otherwise, the admin CC below covers it.

// CC every admin (the actual reviewers in this workflow).
$this->notifyAdmins(
    'New onboarding approval',
    "{$submittedBy->name} submitted a new employee onboarding pending approval",
    [
        'route' => 'onboarding_approvals',
        'onboarding_id' => (string) $onboarding->id,
    ]
);
```

### What the user sees on their phone

- **Every admin**: notification *"New onboarding approval — <submitter> submitted a new employee onboarding pending approval"*.
- Tap → opens **EmployeeOnboardingApprovalScreen** (pending onboarding approvals list).

---

## Payload reference — what the mobile app understands

| `data` payload | Mobile behavior |
|---|---|
| `['route' => 'regularization_approvals']` | Opens **RegularizationApprovalScreen** |
| `['route' => 'onboarding_approvals']` | Opens **EmployeeOnboardingApprovalScreen** |
| `['route' => 'leave_approvals']` | Opens LeaveApprovalScreen (from leave-notifications spec) |
| `['route' => 'leave_history']` | Opens LeaveHistoryScreen (from leave-notifications spec) |
| `['route' => 'notifications']` | Opens the in-app notifications list |
| `['route' => 'tab', 'tab' => 'leave']` | Switches bottom-nav to Leave tab (generic fallback) |

The mobile app silently ignores unknown routes — so adding extra keys like `regularization_id` and `onboarding_id` is safe and useful for future deep-linking.

---

## Verification

After adding both hooks:

### Test 1 — Regularization

1. **Admin** logs in fresh on a phone → backgrounds the app.
2. **Employee** submits an attendance regularization request from web or another phone.
3. Admin's phone should buzz with *"Regularization request"* within 30 seconds.
4. Tap → app opens to **RegularizationApprovalScreen**.

### Test 2 — Onboarding

1. **Admin** stays backgrounded on the phone.
2. Trigger a new employee-onboarding submission from web.
3. Admin's phone should buzz with *"New onboarding approval"* within 30 seconds.
4. Tap → app opens to **EmployeeOnboardingApprovalScreen**.

### If a test fails

Same diagnostic pattern as the leave events. Add log lines around the FcmService call:

```php
\Log::info('[FCM hook] event=regularization_submitted', [
    'reg_id' => $regularization->id,
    'admins_count' => EmployeeModel::where('role', 'ADMIN')->whereNotNull('fcm_token')->count(),
]);
```

If `admins_count` is `0` → there are no admin users with FCM tokens registered (admin hasn't logged in on a phone yet, OR `fcm_token` is null on their row).

If `admins_count > 0` but no notification arrives → check `storage/logs/laravel.log` for FCM errors.

---

## Important reminders

1. **`role` column value** — the helper filters by `role = 'ADMIN'`. Confirm this matches what's stored. Your login response shows uppercase `"role": "ADMIN"` so it should be fine, but verify with `SELECT DISTINCT role FROM employees;`.

2. **FCM token must be present** — admin needs to log in on a phone at least once so their `fcm_token` is populated. If an admin only uses the web, they'll never receive push notifications (because there's no device to push to).

3. **`data` values must be strings** — `(string) $regularization->id`, not bare integers. Kreait will throw a validation error otherwise.

4. **Recipient can be null** — wrap the approver-side `sendToUser` in `if ($approver && $approver->fcm_token)` to avoid crashes when the lookup returns null.

5. **Don't await the response** — `sendToUser` returns true/false but the API request should succeed even if FCM is down. The FcmService class already swallows exceptions internally.
