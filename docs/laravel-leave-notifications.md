# Laravel Backend — Leave Notification Hooks

Standalone reference for the Laravel developer. **Prerequisite:** you've already completed `laravel-fcm-push-notifications.md` (the `FcmService` class exists and the tinker test works). This doc tells you exactly *where* to call it from for the three leave-related events.

> Without these hooks, `FcmService` exists in code but is never invoked from real business actions — which is why notifications aren't arriving on phones when leaves are approved.

---

## The three events

| # | Trigger | Primary recipient | Also CC'd | Mobile screen opened on tap |
|---|---|---|---|---|
| 1 | Employee submits a new leave request | The approver (manager/HR) | **All admins** | LeaveApprovalScreen (pending approvals list) |
| 2 | Approver approves a leave | The employee whose leave it is | **All admins** | LeaveHistoryScreen (employee's own history) |
| 3 | Approver rejects a leave | The employee whose leave it is | **All admins** | LeaveHistoryScreen (employee's own history) |

These three hooks are independent. Add each one inside the controller method that performs the relevant action.

**Admin CC rule:** every admin (`role = 'ADMIN'`) receives a notification for every leave event, even if they are the same person who just clicked Approve/Reject. No de-duplication — overlap is acceptable. The admin's notification text is worded differently (oversight perspective) and tap-opens the approvals list.

---

## Helper — notify all admins (used by all three events)

Add this private method to whatever controller is calling FcmService (or move it to a trait / service if cleaner). It loops every admin user with an FCM token and sends them a CC notification.

```php
use App\Models\EmployeeModel;
use App\Services\FcmService;

/**
 * CC every admin (role = 'ADMIN') on a leave event. Loops all admins with
 * an FCM token registered — no de-duplication, so the admin who clicked
 * the action also receives the notification.
 */
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

> **Adjust the role filter** if your admin role is named differently (`'Admin'`, `'super_admin'`, etc.). Use whatever string matches the actual value in `employees.role`.

---

## Event 1 — New leave request submitted → notify approver

### Where to add the hook

Wherever you save a new leave application. Probably one of:
- `app/Http/Controllers/LeaveController.php` → `store()` or `applyLeave()`
- The controller method behind `POST /leaves/store-leave`

Find the line where the leave row is persisted (`$leave = LeaveApplication::create([...])` or similar). Add the notification call immediately after.

### Code to add

```php
use App\Models\EmployeeModel;
use App\Services\FcmService;

// ... after $leave is saved successfully ...

// Resolve who needs to approve this leave. Adjust this lookup to match
// your business rules — typically the employee's reporting manager, or
// HR for certain leave types. Fallback to null if unresolved (we just
// skip the notification rather than crash).
$approver = EmployeeModel::find($leave->approver_id); // ← replace with your real lookup

if ($approver) {
    app(FcmService::class)->sendToUser(
        $approver,
        'New leave request',
        "{$leave->employee->name} requested {$leave->days} day(s) leave from {$leave->from_date}",
        [
            'route' => 'leave_approvals',
            'leave_id' => (string) $leave->id,
        ]
    );
}

// CC every admin so they have visibility on all submissions.
$this->notifyAdmins(
    'New leave request',
    "{$leave->employee->name} applied for {$leave->days} day(s) leave from {$leave->from_date}",
    [
        'route' => 'leave_approvals',
        'leave_id' => (string) $leave->id,
    ]
);
```

### What the user sees on their phone

- **Approver**: *"New leave request — ABHILASH S requested 2 day(s) leave from 25/05/2026"*
- **Every admin**: *"New leave request — ABHILASH S applied for 2 day(s) leave from 25/05/2026"*
- Tap → opens **LeaveApprovalScreen** (the pending-approvals list).

---

## Event 2 — Leave approved → notify employee

### Where to add the hook

The controller method that handles approval. Probably:
- `app/Http/Controllers/LeaveApprovalController.php` → `updateStatus()`
- Or whatever method is behind `POST /leaves/update-status`

Find the line where status is changed to `approved` and added after the save.

### Code to add

```php
use App\Models\EmployeeModel;
use App\Services\FcmService;

// ... after $leave->status = 'approved' and $leave->save() ...

$employee = $leave->employee; // adjust to your relationship name
$approver = auth()->user();    // whoever clicked Approve

if ($employee) {
    app(FcmService::class)->sendToUser(
        $employee,
        'Leave approved ✅',
        "Your {$leave->days}-day leave from {$leave->from_date} has been approved",
        [
            'route' => 'leave_history',
            'leave_id' => (string) $leave->id,
        ]
    );
}

// CC every admin so they have visibility on every approval decision.
$this->notifyAdmins(
    'Leave approved ✅',
    "{$approver->name} approved {$employee->name}'s {$leave->days}-day leave from {$leave->from_date}",
    [
        'route' => 'leave_approvals',
        'leave_id' => (string) $leave->id,
    ]
);
```

---

## Event 3 — Leave rejected → notify employee

Same controller, almost identical code. Probably in the same `updateStatus()` method but in the "rejected" branch.

### Code to add

```php
use App\Models\EmployeeModel;
use App\Services\FcmService;

// ... after $leave->status = 'rejected' and $leave->save() ...

$employee = $leave->employee;
$approver = auth()->user();

if ($employee) {
    app(FcmService::class)->sendToUser(
        $employee,
        'Leave rejected',
        "Your {$leave->days}-day leave from {$leave->from_date} was rejected"
            . ($leave->rejection_reason ? ". Reason: {$leave->rejection_reason}" : ''),
        [
            'route' => 'leave_history',
            'leave_id' => (string) $leave->id,
        ]
    );
}

// CC every admin so they have visibility on every rejection decision.
$this->notifyAdmins(
    'Leave rejected',
    "{$approver->name} rejected {$employee->name}'s {$leave->days}-day leave from {$leave->from_date}"
        . ($leave->rejection_reason ? " ({$leave->rejection_reason})" : ''),
    [
        'route' => 'leave_approvals',
        'leave_id' => (string) $leave->id,
    ]
);
```

---

## Recommended — combine events 2 & 3 in one block

If your `updateStatus()` already has an `if/else` for approved vs rejected, fold the notification into the same branches:

```php
public function updateStatus(Request $request, $id)
{
    $request->validate([
        'status' => 'required|in:approved,rejected',
        'rejection_reason' => 'nullable|string',
    ]);

    $leave = LeaveApplication::findOrFail($id);
    $leave->status = $request->status;
    if ($request->status === 'rejected') {
        $leave->rejection_reason = $request->rejection_reason;
    }
    $leave->approved_by = auth()->id();
    $leave->save();

    // ─────────────────────────────────────────────────────────
    // FCM notification — fire after save, before returning.
    // Failure is swallowed by FcmService::sendToUser so this
    // can never break the API response.
    // ─────────────────────────────────────────────────────────
    $employee = $leave->employee;
    if ($employee) {
        if ($request->status === 'approved') {
            app(FcmService::class)->sendToUser(
                $employee,
                'Leave approved ✅',
                "Your {$leave->days}-day leave from {$leave->from_date} has been approved",
                ['route' => 'leave_history', 'leave_id' => (string) $leave->id]
            );
        } else {
            app(FcmService::class)->sendToUser(
                $employee,
                'Leave rejected',
                "Your {$leave->days}-day leave from {$leave->from_date} was rejected"
                    . ($leave->rejection_reason ? ". Reason: {$leave->rejection_reason}" : ''),
                ['route' => 'leave_history', 'leave_id' => (string) $leave->id]
            );
        }
    }

    return response()->json(['status' => true, 'message' => 'Leave ' . $request->status]);
}
```

---

## Important — fcm_token must be on the right model

Your codebase uses `EmployeeModel` (not `User`). All three notification calls pass an `EmployeeModel` instance to `FcmService::sendToUser()`. For this to work, **two things** must be true:

1. **`fcm_token` column is on the `employees` table** (or whatever table `EmployeeModel` uses), not on `users`.
   ```php
   php artisan tinker
   \Schema::hasColumn('employees', 'fcm_token');  // must return true
   ```

2. **`EmployeeModel::$fillable` includes `'fcm_token'`.**
   ```bash
   grep -n "fcm_token" app/Models/EmployeeModel.php
   ```
   Must show a match inside the `$fillable` array.

If either is wrong, **the mobile login won't persist the token**, every `sendToUser` call will silently fail because `$employee->fcm_token` is null.

> If the previous tinker test (manually setting the token via `$u->update(['fcm_token' => ...])`) worked, both are likely fine. But verify just in case.

---

## Payload reference — what the mobile app understands

These are the only `data` payloads that route to specific screens. The mobile app's `_routeNow` will silently ignore unknown routes.

| `data` payload | Mobile behavior |
|---|---|
| `['route' => 'leave_approvals']` | Opens LeaveApprovalScreen (pending approvals — for managers) |
| `['route' => 'leave_history']` | Opens LeaveHistoryScreen (employee's own leave history) |
| `['route' => 'notifications']` | Opens the in-app notifications list |
| `['route' => 'tab', 'tab' => 'leave']` | Switches bottom-nav to Leave tab (general fallback) |

Including an extra `leave_id` in the payload is harmless and useful for future deep-linking (we can later route to a specific leave's detail screen). Mobile ignores keys it doesn't recognise.

---

## Final reminders

- **FCM `data` values must be strings.** `(string) $leave->id` — not bare integers. Kreait will throw a validation error otherwise.
- **Always check `$employee` / `$approver` is not null** before calling `sendToUser`. If the recipient lookup returns null, just skip — don't crash the API request.
- **Don't await the response.** `sendToUser` returns true/false but the API request should succeed even if FCM is down. The FcmService class already swallows exceptions internally.
- **Notification channel id** in the FCM payload is `mecpl_default` — already handled inside `FcmService`. Don't override.

---

## Verification

After adding all three hooks, run this end-to-end test:

1. **Employee** logs in fresh on phone A → backgrounds the app.
2. **Manager** logs in fresh on phone B (or web) → backgrounds the app.
3. **Employee** submits a new leave request from phone A's web UI.
4. **Manager** should receive a "New leave request" notification on phone B within 30 seconds. ✅
5. **Manager** approves the leave from web.
6. **Employee** should receive a "Leave approved" notification on phone A within 30 seconds. ✅
7. **Manager** rejects a different leave from web.
8. **Employee** should receive a "Leave rejected" notification on phone A within 30 seconds. ✅

If any of these don't arrive, the issue is in that specific hook — re-check that the `app(FcmService::class)->sendToUser(...)` call is actually being reached in that controller method.

Diagnostic:

```php
\Log::info('[FCM hook] event=leave_submitted', [
    'leave_id' => $leave->id,
    'approver_id' => $approver?->id,
    'approver_token_present' => !empty($approver?->fcm_token),
]);
```

Add this before each `sendToUser` call, hit the action, then `tail -n 50 storage/logs/laravel.log`. If the log line doesn't appear, the controller method isn't being executed. If it appears but `approver_token_present` is false, the recipient has no token in the DB.
