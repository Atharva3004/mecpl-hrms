# Backend Fixes — From Source Review

**Date:** 2026-08-31
**Reviewed:** `Kernel.php`, `api.php`, `AttendancePunchController.php`,
`AttendanceViewController.php`, `BranchModel.php`, `AttendanceSessionModel.php`,
`AttendancePunchModel.php`, `AttendanceLocationPingModel.php`
**Context:** an employee was locked out of attendance for six weeks
(session 111, `active` since 2026-07-17). Root cause is now identified in code.

---

## 0. Summary

Thanks for sending the source — this replaces guesswork with specifics. Most
of what you reported as fixed **is genuinely fixed in the code** (§5). What
follows is what is still broken, with drop-in patches.

| # | Item | File | Priority |
|---|---|---|---|
| **1** | `SESSION_ALREADY_OPEN` check has no date filter — **this is the lockout** | `AttendancePunchController.php` | 🔴 P0 |
| **2** | Nothing ever closes a stale session | `Kernel.php` (+ new command) | 🔴 P0 |
| **3** | `today()` returns an active session from any date | `AttendanceViewController.php` | 🔴 P0 |
| **4** | Force-close the sessions already stuck | SQL | 🔴 P0 |
| **5** | `punchOut()` can write a multi-week `duration_seconds` | `AttendancePunchController.php` | 🟠 P1 |
| **6** | `live()` returns the entire branch row (approver IDs, address) | `AttendanceViewController.php` | 🟠 P1 |
| **7** | `live()` runs one query per session (N+1) | `AttendanceViewController.php` | 🟡 P2 |
| **8** | `ALREADY_PUNCHED_TODAY` ignores `force_closed` — policy decision needed | `AttendancePunchController.php` | 🟡 P2 |

Fixes 1–4 together end the lockout and stop it recurring. They are
independent of everything else and can ship on their own.

---

## 1. 🔴 The lockout — `SESSION_ALREADY_OPEN` has no date filter

**File:** `AttendancePunchController::punchIn()`

### Current code

```php
$existing = AttendanceSessionModel::where('employee_id', $employee->id)
    ->where('status', 'active')
    ->lockForUpdate()
    ->first();
if ($existing) {
    return ['error' => 'SESSION_ALREADY_OPEN', 'session' => $existing];
}
```

**Any `active` session, from any date, blocks punch-in — permanently.**

Note the check immediately below it *does* scope to today:

```php
$todayIST = \Carbon\Carbon::now('Asia/Kolkata')->toDateString();
$completedSession = AttendanceSessionModel::where('employee_id', $employee->id)
    ->where('status', 'closed')
    ->whereDate('date', $todayIST)      // ← scoped here
    ->lockForUpdate()
    ->first();
```

The day-scoping was applied to one check and not the other. That single
omission is the whole incident: session 111 was opened on 17 July, never
closed, and returned `SESSION_ALREADY_OPEN` on every punch-in attempt for six
weeks. The employee could not punch out either — the app correctly refuses to
treat a July session as today's, so there was nothing to close.

### Fix — self-healing, so it survives a failed cron

Close stale sessions in place and let the punch proceed:

```php
use Illuminate\Support\Facades\Log;

// ... inside the DB::transaction closure, replacing the block above ...

$todayIST = \Carbon\Carbon::now('Asia/Kolkata')->toDateString();

$openSessions = AttendanceSessionModel::where('employee_id', $employee->id)
    ->where('status', 'active')
    ->lockForUpdate()
    ->get();

foreach ($openSessions as $open) {
    // A session opened today is a genuine conflict — the employee really is
    // still punched in.
    if (optional($open->date)->toDateString() === $todayIST) {
        return ['error' => 'SESSION_ALREADY_OPEN', 'session' => $open];
    }

    // Anything older is an orphan: the employee never punched out and no job
    // has cleaned it up. Close it and allow today's punch to proceed rather
    // than locking the account out forever.
    $open->update([
        'status'           => 'force_closed',
        'ended_at'         => $open->ended_at ?? $open->started_at,
        'duration_seconds' => 0,
    ]);

    Log::warning('Force-closed stale attendance session on punch-in', [
        'session_id'  => $open->id,
        'employee_id' => $employee->id,
        'started_at'  => $open->started_at,
    ]);
}
```

**On the values:** `duration_seconds = 0` and `ended_at = started_at` records
**no worked time**. That is deliberate — there is no evidence the employee was
working, and session 111 had `ping_count = 0`. Please do **not** compute
`now() - started_at`; on session 111 that posts a six-week shift into
attendance.

`status = 'force_closed'` (not `'closed'`) keeps these distinguishable from
real punch-outs in any later audit — and it matters for §8 below.

**Verify:** with a stale `active` session in the table, punch-in returns
`201`, the old session becomes `force_closed`, and a warning is logged.

---

## 2. 🔴 Nothing ever closes a stale session

**File:** `Kernel.php`

`force_closed` appears in the `status` enum and **nowhere else in the
codebase**. The scheduler has eight entries — biometric sync, attendance
processing, monthly summary/resync, leave accrual, ping purge, probation
reminders — and this one:

```php
/**
 * Punch-out reminder — sends FCM push at 19:00 IST
 * to employees punched in for over 9 hours
 */
$schedule->call(function () {
    $nineHoursAgo = now()->subHours(9);
    \App\Models\AttendanceSessionModel::where('status', 'active')
        ->where('started_at', '<', $nineHoursAgo)
        // ... sends FCM ...
})->dailyAt('19:00')->timezone('Asia/Kolkata');
```

So the system already **knows** long-running sessions happen — it just nudges
the employee and never closes anything. If they ignore the notification,
uninstall the app, or change phone, the session stays open forever. That is
precisely how session 111 survived six weeks.

### Fix — the missing command

`app/Console/Commands/ForceCloseStaleSessions.php`:

```php
<?php

namespace App\Console\Commands;

use App\Models\AttendanceSessionModel;
use Carbon\Carbon;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;

class ForceCloseStaleSessions extends Command
{
    protected $signature   = 'attendance:force-close-stale';
    protected $description = 'Close attendance sessions left open past the IST day boundary';

    public function handle(): int
    {
        $todayIST = Carbon::now('Asia/Kolkata')->toDateString();

        $stale = AttendanceSessionModel::where('status', 'active')
            ->whereDate('date', '<', $todayIST)
            ->get();

        if ($stale->isEmpty()) {
            $this->info('No stale sessions.');
            return self::SUCCESS;
        }

        foreach ($stale as $session) {
            $session->update([
                'status'           => 'force_closed',
                'ended_at'         => $session->ended_at ?? $session->started_at,
                'duration_seconds' => 0,
            ]);

            // These are MISSING PUNCH-OUTS. Log every one — silently closing
            // them hides a real attendance problem from HR.
            Log::warning('Force-closed stale attendance session', [
                'session_id'  => $session->id,
                'employee_id' => $session->employee_id,
                'branch_id'   => $session->branch_id,
                'date'        => $session->date,
                'started_at'  => $session->started_at,
                'ping_count'  => $session->ping_count,
            ]);
        }

        $this->warn("Force-closed {$stale->count()} stale session(s).");
        return self::SUCCESS;
    }
}
```

Register it in `Kernel.php::schedule()` alongside the existing entries:

```php
/**
 * Force-close attendance sessions left open past IST midnight.
 * Without this, an employee who forgets to punch out is locked out of
 * attendance permanently (punch-in 409s, punch-out has nothing local to close).
 */
$schedule->command('attendance:force-close-stale')
    ->dailyAt('00:15')
    ->timezone('Asia/Kolkata')
    ->withoutOverlapping()
    ->runInBackground()
    ->appendOutputTo(storage_path('logs/attendance-force-close.log'));
```

`00:15` sits after midnight and before `leave:accrue` at `00:05`… actually
after it — pick any early slot; just keep it clear of the `attendance:process`
15-minute cycle. `$this->load(__DIR__.'/Commands')` in `commands()` already
auto-registers the class, so no other wiring is needed.

**Please decide** whether a force-closed session should also raise a
regularisation request for the employee, or just appear in an HR report. Right
now the worked time is simply lost.

---

## 3. 🔴 `today()` returns an active session from any date

**File:** `AttendanceViewController::today()`

```php
$today  = now()->toDateString();

$active = AttendanceSessionModel::where('employee_id', $employee->id)
    ->where('status', 'active')
    ->first();                       // ← no date filter
```

Same omission as §1, and inconsistent within the same method — `$punches`
uses `whereDate('punched_at', $today)` and `$sessionsToday` uses
`whereDate('date', $today)`. Only `$active` is unscoped.

This is what handed our app a July session as today's `active_session`. Our
client now rejects it, but the endpoint should not be reporting it.

### Fix

```php
$active = AttendanceSessionModel::where('employee_id', $employee->id)
    ->where('status', 'active')
    ->where(function ($q) use ($today) {
        // Mirrors the fallback already used in history(), for rows where
        // `date` is null or drifted.
        $q->whereDate('date', $today)
          ->orWhereDate('started_at', $today);
    })
    ->first();
```

---

## 4. 🔴 Close the sessions already stuck

§1 and §2 stop new ones. These are already in the table:

```sql
-- Inspect first. Every row is a locked-out employee.
SELECT id, employee_id, branch_id, date, started_at, ping_count
FROM attendance_sessions
WHERE status = 'active'
  AND date < CURDATE()
ORDER BY started_at;
```

```sql
-- TAKE A BACKUP FIRST. No LIMIT, and this rewrites historical attendance.
UPDATE attendance_sessions
SET status           = 'force_closed',
    ended_at         = COALESCE(ended_at, started_at),
    duration_seconds = 0
WHERE status = 'active'
  AND date < CURDATE();
```

> `CURDATE()` uses the **MySQL session timezone**, not PHP's. Your app is
> `Asia/Kolkata`; confirm the DB session matches, or run this through
> `php artisan tinker` so Carbon governs the boundary.

**Please send us the row count from the SELECT** — it tells us how many people
have been silently locked out and for how long.

---

## 5. 🟠 `punchOut()` can write a multi-week duration

**File:** `AttendancePunchController::punchOut()`

```php
$duration = $now->diffInSeconds($session->started_at);

$session->update([
    'ended_at'         => $now,
    'duration_seconds' => $duration,
    'status'           => 'closed',
]);
```

The only guard is `status !== 'active'`. There is **no check that the session
belongs to today**. Punching out session 111 would have written roughly
**3.8 million seconds** into `duration_seconds`, and that figure flows into
`total_seconds` on `/attendance/today` and `/attendance/history`.

This is also why §4 must be done in SQL rather than by punching out.

### Fix

```php
$todayIST = \Carbon\Carbon::now('Asia/Kolkata')->toDateString();

if (optional($session->date)->toDateString() !== $todayIST) {
    // Orphan from an earlier day — close it without inventing worked time.
    $session->update([
        'status'           => 'force_closed',
        'ended_at'         => $session->ended_at ?? $session->started_at,
        'duration_seconds' => 0,
    ]);

    return response()->json([
        'status'     => false,
        'error_code' => 'SESSION_EXPIRED',
        'message'    => 'That session was from an earlier day and has been closed. '
                        . 'Please punch in again.',
        'data'       => ['session_id' => $session->id],
    ], 409);
}
```

If you add `SESSION_EXPIRED`, tell us and we will handle it explicitly —
today it would fall through to our generic error path.

---

## 6. 🟠 `live()` returns the entire branch row

**File:** `AttendanceViewController::live()`

```php
'employee'   => [
    'id'       => $s->employee->id ?? null,
    'emp_name' => $s->employee->emp_name ?? 'Unknown',
    'emp_code' => $s->employee->companyDetails->emp_code ?? '',
],
'branch'     => $s->branch,      // ← whole Eloquent model
```

Every other field is hand-picked; this one serialises the full `branches` row.
`BranchModel::$fillable` includes `l1`–`l6`, `on_site`, `qa`, `ehs`, `store`,
`qs_billing`, `ec_l1`–`ec_l6` and `address` — so the admin dashboard receives
the entire approval hierarchy and branch address on **every active session**,
multiplied by up to `limit` (default 100).

Note the eager-load already asks for only two columns
(`'branch:id,branch_name'`), so the intent was clearly to send just those.

### Fix

```php
'branch' => [
    'id'          => $s->branch->id ?? null,
    'branch_name' => $s->branch->branch_name ?? '',
],
```

Our client reads `branch['branch_name']`, so this is transparent to us.

---

## 7. 🟡 `live()` N+1

```php
$data = $sessions->map(function ($s) {
    $lastPing = AttendanceLocationPingModel::where('session_id', $s->id)
        ->latest('captured_at')
        ->first();          // ← one query per session
```

100 active sessions = 101 queries on a screen the admin dashboard polls. Fix
with a single grouped query before the map, or a `latestOfMany` relation:

```php
// AttendanceSessionModel
public function latestPing(): HasOne
{
    return $this->hasOne(AttendanceLocationPingModel::class, 'session_id')
                ->latestOfMany('captured_at');
}
```

then add `'latestPing'` to the `with([...])` and use `$s->latestPing`.

---

## 8. 🟡 `ALREADY_PUNCHED_TODAY` ignores `force_closed`

```php
$completedSession = AttendanceSessionModel::where('employee_id', $employee->id)
    ->where('status', 'closed')          // ← force_closed not included
    ->whereDate('date', $todayIST)
```

This is **correct and desirable** for §1's fix — after a stale session is
force-closed, the employee must be able to punch in. But it also means a
session force-closed *today* (by an admin, or by a future same-day cleanup)
would let them start a second cycle, which the "one cycle per day" rule
otherwise forbids.

Fine as-is today. Flagging it so the behaviour is a decision rather than an
accident — please confirm it is intended.

---

## 9. Confirmed working (verified in source, not just claimed)

Credit where due — these are genuinely done:

- `BranchModel::hasGeofence()` uses `$this->geofence_radius_m > 0` — the
  NULL→0 cast bug is fixed
- `today()` and `history()` punches really do select `session_id`,
  `latitude`, `longitude`, `accuracy_m`, `address`, `selfie_url`
- All four models carry correct `$casts` (float / integer / boolean), so
  numbers arrive as JSON numbers
- `lockForUpdate()` is genuinely inside the `DB::transaction` closure
- Timezone is consistently `now()` (app tz `Asia/Kolkata`); `ALREADY_PUNCHED_TODAY`
  uses an explicit IST Carbon
- `resolveGeofence()` returns `[true, null]` for an unconfigured branch,
  matching the documented "no fence = inside" rule
- `timeline()` allows the session owner as well as admins
- `error_code` is used consistently, and `GEOFENCE_NOT_ENABLED` is returned
- The 409 body already includes `started_at` — we now read it inline instead
  of making a second call. Thank you, that was useful.

---

## 10. Still outstanding from earlier rounds

- [ ] **Deploy confirmation** — is any of this live on `hrms.mecpl.in`?
      Round 2 listed "Deploy to production" as pending and we have had no
      confirmation since.
- [ ] `SELECT COUNT(*) FROM attendance_location_pings WHERE captured_at > NOW() - INTERVAL 1 DAY;`
      — **asked four times.** It is the one number that tells us whether pings
      reach you at all. Session 111 had `ping_count = 0`, but it predates our
      background-permission fix, so it settles nothing.
- [ ] Branch geofence audit — which branches have `latitude`, `longitude`,
      `geofence_radius_m` populated. Unconfigured branches cannot show a fence
      no matter what the app does.
- [ ] The guide's **Known Issues** section was deleted in v1.1. Two items in
      it (`client_captured_at` temporal bounds, `live()` N+1) were never
      fixed and now have no record anywhere. Please restore them or track
      them in your issue tracker.

---

## 11. Verification

- [ ] §4 SELECT returns zero rows after the UPDATE
- [ ] Insert a test session dated yesterday with `status='active'` → punch-in
      returns **201**, old session becomes `force_closed`, warning logged
- [ ] `/attendance/today` no longer returns a previous-day `active_session`
- [ ] `php artisan attendance:force-close-stale` runs clean and logs each closure
- [ ] Leave a session open overnight → next morning it is `force_closed` and
      punch-in works normally
- [ ] `/attendance/live` response no longer contains `l1`…`ec_l6` or `address`
- [ ] No session anywhere has an implausible `duration_seconds`

---

## 12. What we changed on the app side

For your awareness — no action needed:

- A punch is now persisted locally **only after** the server accepts it.
  Previously the record was written before upload, so a rejected punch left a
  punch-in time on the card forever while the database had nothing. That is
  how this incident looked like a working punch-in to the user.
- On 409 `SESSION_ALREADY_OPEN` we read your `started_at` inline: a session
  from today is adopted so punch-out works; an older one is reported by date
  and ID with "must be closed by an administrator", instead of the impossible
  "punch out first".
- Punch and ping calls now log status and response body — this incident took a
  live device capture to find because neither path logged anything.
- Field names are pinned by tests against your guide, so a rename fails a test
  rather than reaching production.
