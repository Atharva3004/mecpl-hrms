# Laravel Backend — Extend In-App Notifications to Regularization & Onboarding

Standalone reference for the Laravel developer.

**Current state:** The `/api/notifications` endpoint and the `notifications` table you built already work for leave events (types `application`, `approval`, `rejection`). The bell-icon list in the mobile app shows these correctly.

**Goal:** Persist two more notification types so the admin broadcasts for **regularization** and **onboarding submissions** also appear in the bell-icon list — not just the phone's notification panel.

**Prerequisites:** `laravel-fcm-push-notifications.md`, `laravel-leave-notifications.md`, `laravel-admin-pending-approvals.md` all done. The push notifications for these events already fire — this doc just adds an in-app record alongside the push.

---

## 1. Scope

For each of the following events, in addition to the FCM push you already send, **insert one notification row per admin recipient** into the `notifications` table.

| Event | New `type` value | Recipients |
|---|---|---|
| Employee submits attendance regularization | `regularization_submitted` | Every admin (`role = 'ADMIN'`) |
| New onboarding submitted | `onboarding_submitted` | Every admin (`role = 'ADMIN'`) |

The existing leave types stay exactly as they are:
- `application` — new leave request
- `approval` — leave approved
- `rejection` — leave rejected

Do **not** touch those. This doc adds two more types, nothing else.

> **Note about leave admin-broadcast (event 4):** when a leave is submitted, your code currently inserts one row of type `application` (for the approver) and sends FCM pushes to admins on top. Those admin pushes don't have a DB row right now. That's intentional and stays — the existing `application` row is enough for the in-app list since it's already visible to any admin who opens their notifications. The two events in this doc are different because they have **no leave_application** anchor at all.

---

## 2. Database — keep existing schema, just allow nullable

Your `notifications` table currently has a `leave_application_id` foreign key (per the response shape in `flutter-notification-api.md`). For the new types, that column should be `NULL` since there's no leave involved.

### Verify the column is nullable

```sql
SHOW COLUMNS FROM notifications LIKE 'leave_application_id';
```

If `Null = NO`, make it nullable:

```php
php artisan make:migration make_leave_application_id_nullable_on_notifications
```

```php
return new class extends Migration {
    public function up(): void {
        Schema::table('notifications', function (Blueprint $table) {
            $table->unsignedBigInteger('leave_application_id')->nullable()->change();
        });
    }
    public function down(): void {
        // No-op — leaving as nullable is safe.
    }
};
```

If it's already nullable, skip this migration.

### Optional — add reference columns for the new types

Not required for v1. The mobile app's tap-handling for `regularization_submitted` / `onboarding_submitted` opens the **approvals list screen** — no specific record needed. If you want to deep-link to a specific regularization/onboarding record later, add nullable foreign keys:

```php
$table->unsignedBigInteger('regularization_id')->nullable();
$table->unsignedBigInteger('onboarding_id')->nullable();
```

Skip unless you have time. The mobile app doesn't need them yet.

---

## 3. Code — extend the existing `notifyAdmins()` helper

You already have this helper from `laravel-admin-pending-approvals.md`:

```php
protected function notifyAdmins(string $title, string $body, array $data): void
{
    $admins = EmployeeModel::where('role', 'ADMIN')
        ->whereNotNull('fcm_token')
        ->get();
    foreach ($admins as $admin) {
        app(FcmService::class)->sendToUser($admin, $title, $body, $data);
    }
}
```

Extend it to **also write a notifications row** for each admin. The notifications row should be created **regardless of whether the admin has an FCM token** (web-only admins should still see the list when they next open the app on a phone, or via web UI if you build one). So we split the admin queries:

```php
use App\Models\EmployeeModel;
use App\Models\Notification; // or whatever your model is named
use App\Services\FcmService;

/**
 * Notify every admin about a pending-approval event:
 *   - Inserts a row into the notifications table for the in-app list.
 *   - Sends an FCM push for the phone's notification panel (only to admins
 *     with a registered fcm_token).
 *
 * @param  string $type  Notification `type` value — used by the mobile app
 *                       to choose an icon and tap target. Must be one of
 *                       'application', 'approval', 'rejection',
 *                       'regularization_submitted', 'onboarding_submitted'.
 *                       Adding a new type? Tell the mobile dev so they can
 *                       extend the icon/route map.
 * @param  string $title FCM notification title (shown in the panel).
 * @param  string $body  FCM notification body + `message` column in the DB.
 * @param  array  $data  FCM data payload — drives deep-link routing on tap.
 */
protected function notifyAdmins(
    string $type,
    string $title,
    string $body,
    array $data
): void {
    $admins = EmployeeModel::where('role', 'ADMIN')->get();

    foreach ($admins as $admin) {
        // 1) Persist in-app notification row so the bell-icon list picks it up.
        Notification::create([
            'user_id'              => $admin->id,
            'type'                 => $type,
            'message'              => $body,
            'is_read'              => false,
            'email_sent'           => false,        // adjust if you also email these
            'leave_application_id' => null,         // null for regularization/onboarding
            // Optionally fill regularization_id / onboarding_id if you added them.
        ]);

        // 2) Send FCM push only if they have a token registered.
        if (!empty($admin->fcm_token)) {
            app(FcmService::class)->sendToUser($admin, $title, $body, $data);
        }
    }
}
```

> **Note:** the `$type` parameter is **new**. The existing `notifyAdmins()` call sites in your leave/regularization/onboarding controllers will fail compilation until you update them. See Section 4.

---

## 4. Update existing call sites

You currently call `notifyAdmins($title, $body, $data)`. Now you must pass `$type` as the first argument.

### 4a — In the leave-submission controller

```php
// Before
$this->notifyAdmins(
    'New leave request',
    "{$employee->name} applied for {$leave->days} day(s) leave from {$leave->from_date}",
    ['route' => 'leave_approvals', 'leave_id' => (string) $leave->id]
);

// After
$this->notifyAdmins(
    'application',  // ← reuse the existing leave type (DB already has rows of this type)
    'New leave request',
    "{$employee->name} applied for {$leave->days} day(s) leave from {$leave->from_date}",
    ['route' => 'leave_approvals', 'leave_id' => (string) $leave->id]
);
```

> **For event 4 (leave admin broadcast):** you're now creating a notification row for every admin in addition to the approver's row (which your existing leave-submission code already inserts). This means a leave application will create N+1 notification rows (N admins + 1 approver). That's fine — admins will see "new leave request" in their personal list. If an admin happens to also be the approver, they'll get 2 rows (the helper doesn't dedupe). Acceptable per the product rule.

### 4b — In the regularization-submission controller

```php
$this->notifyAdmins(
    'regularization_submitted',
    'New regularization request',
    "{$employee->name} requested attendance correction for {$regularization->date}",
    ['route' => 'regularization_approvals', 'regularization_id' => (string) $regularization->id]
);
```

### 4c — In the onboarding-submission controller

```php
$this->notifyAdmins(
    'onboarding_submitted',
    'New onboarding approval',
    "{$submittedBy->name} submitted a new employee onboarding pending approval",
    ['route' => 'onboarding_approvals', 'onboarding_id' => (string) $onboarding->id]
);
```

---

## 5. Update `/api/notifications` response — optional eager-load relations

Your current response includes the nested `leave_application` relation. For the new types it'd be useful to also eager-load `regularization` and `onboarding` relations (when present) so the mobile app can show richer detail without extra API calls.

This is **nice-to-have, not required**. The mobile app doesn't use these yet. If you want to add it:

```php
// In NotificationController@index
$notifications = Notification::where('user_id', auth()->id())
    ->with(['leaveApplication', 'regularization', 'onboarding'])
    ->orderByDesc('created_at')
    ->paginate($perPage);
```

Each relation should return `null` when the corresponding ID is null — the model accessors handle that automatically.

Skip if you don't have relation columns yet.

---

## 6. Type reference — what's stored in the `type` column

After this change, the `notifications.type` column can hold any of these values. The mobile app understands all of them.

| `type` value | Meaning | Tap-opens (mobile) |
|---|---|---|
| `application` | New leave request (to approver) | LeaveApprovalScreen |
| `approval` | Leave approved (to employee) | LeaveHistoryScreen |
| `rejection` | Leave rejected (to employee) | LeaveHistoryScreen |
| `regularization_submitted` | New attendance regularization request | RegularizationApprovalScreen |
| `onboarding_submitted` | New onboarding submitted | EmployeeOnboardingApprovalScreen |

Any other value → mobile shows a generic icon and opens a detail dialog instead of navigating. So unknown types fail gracefully.

---

## 7. Verification

After the changes deploy:

### Test 1 — Regularization in-app list

1. Admin logs in fresh on phone → backgrounds app.
2. From web, an employee submits a regularization request.
3. ✅ Phone's notification panel shows the push (existing behavior).
4. Admin opens the app → taps the bell icon → ✅ a new row appears at the top with title showing "New regularization request" (or the same body text from the push).
5. The row has a coloured left border + dot indicating it's unread.
6. Tap the row → ✅ opens **RegularizationApprovalScreen**, and the row turns "read" (border + dot disappear).

### Test 2 — Onboarding in-app list

Same flow but submitting an onboarding instead of a regularization. Should appear in the list with type `onboarding_submitted`.

### Test 3 — Existing leave events still work

1. Submit a leave application from another account.
2. Admin's bell list should now show a new row with type `application` (broadcast — new behavior) AND the approver also sees one (existing behavior).
3. Approver approves → employee sees `approval` row (existing behavior).
4. Manager rejects → employee sees `rejection` row (existing behavior).

Tap each — they should all route to their existing screens.

### Reporting template

```
Test 1 (regularization in-app list): PASS / FAIL — row appears: YES / NO
Test 2 (onboarding in-app list):     PASS / FAIL — row appears: YES / NO
Test 3 (leave events still work):    PASS / FAIL

Sample query to verify (run after each test):
SELECT id, user_id, type, message, is_read, created_at
FROM notifications
WHERE user_id = <ADMIN_USER_ID>
ORDER BY id DESC LIMIT 5;
```

---

## 8. Common pitfalls

1. **Forgot to update existing call sites** — the new `notifyAdmins()` requires `$type` as the first arg. All three call sites must be updated. Compilation will catch the leave one, but PHP is loose — test all three.

2. **Type string typos** — must match exactly: `regularization_submitted`, `onboarding_submitted` (snake_case, no spaces). The mobile app does an exact string match.

3. **Notifications row not created** — if you only call `FcmService::sendToUser` and skip the `Notification::create` call, the push will arrive but nothing shows in the in-app list.

4. **N+1 admin rows** — submitting one leave/regularization/onboarding creates one row per admin. With 5 admins, one event = 5 rows in the table. That's intended. If you have hundreds of admins, consider a different design (a single "broadcast" row + a recipient pivot table) — but for MECPL HRMS scale it's fine.

5. **`Notification` model name** — adjust to whatever your model is actually called (`Notification`, `NotificationModel`, or namespaced differently). The example uses `App\Models\Notification` but yours may differ.

---

## 9. Quick checklist

- [ ] Make `notifications.leave_application_id` nullable (if not already).
- [ ] Update `notifyAdmins()` helper to take `$type` as first arg and insert a `Notification::create([...])` row alongside the FCM push.
- [ ] Update leave-submission call site to pass `'application'`.
- [ ] Update regularization-submission call site to pass `'regularization_submitted'`.
- [ ] Update onboarding-submission call site to pass `'onboarding_submitted'`.
- [ ] Test all 3 events end-to-end (Section 7).
- [ ] Send back the filled-in reporting template.
