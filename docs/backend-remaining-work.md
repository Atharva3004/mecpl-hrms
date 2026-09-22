# Backend — Remaining Work

**Date:** 2026-09-01
**From:** Mobile (Flutter) team
**Supersedes:** the open items in `backend-fixes-from-code-review.md`
**Source:** review of your `AttendancePunchController`, `AttendanceViewController`,
models and `Kernel.php`, plus live device testing on 31 Aug – 1 Sep.

---

## 0. Summary

> **Verified against the live API on 1 Sep, 18:30 IST**, using a real employee
> session. Status below reflects what the server actually returns, not what
> was reported. Two of my earlier findings were wrong and are retracted.

| # | Item | Status |
|---|---|---|
| **1** | `SESSION_ALREADY_OPEN` date filter | ❓ can't verify externally — see §12 |
| **2** | Force-close stale sessions | ✅ **shipped** — but writing invalid rows, see §12.2 |
| **3** | `today()` any-date active session | ❓ likely fixed — no stale session left to expose it |
| **4** | Force-close the already-stuck sessions | ✅ **done** — session 134 is now `force_closed` |
| **5** | Branch geofence data | ✅ **RETRACTED — my error, data was correct** |
| **6** | `punchOut()` multi-week duration | ⚠️ superseded by a worse bug — see §12.1 |
| **7** | Normalise `captured_at` timezone | ✅ **fixed** — `captured_at` now stores IST |
| **8** | `live()` leaks the whole branch row | ✅ **fixed** — verified, returns id + branch_name only |
| **9** | `live()` N+1 | ❓ not externally visible |
| **10** | `ALREADY_PUNCHED_TODAY` vs `force_closed` | ❓ confirm intent |
| **11** | Restore guide's Known Issues section | ❓ |

**Good progress — most of this is genuinely done.** But verification turned up
a **new P0 data-integrity bug** that is worse than anything on the original
list: session start times are being overwritten, so worked hours are recorded
as ~20 minutes instead of 5 hours. **See §12.**

---

## 1. 🔴 The lockout — `SESSION_ALREADY_OPEN` has no date filter

**File:** `AttendancePunchController::punchIn()`

```php
$existing = AttendanceSessionModel::where('employee_id', $employee->id)
    ->where('status', 'active')
    ->lockForUpdate()
    ->first();
if ($existing) {
    return ['error' => 'SESSION_ALREADY_OPEN', 'session' => $existing];
}
```

Any `active` session from **any date** blocks punch-in, permanently. Note the
check immediately below it *is* scoped to today:

```php
$todayIST = \Carbon\Carbon::now('Asia/Kolkata')->toDateString();
$completedSession = AttendanceSessionModel::where('employee_id', $employee->id)
    ->where('status', 'closed')
    ->whereDate('date', $todayIST)      // ← scoped here, not above
```

The day-scoping was applied to one check and not the other. Session 111 was
opened 17 July, never closed, and returned 409 on every punch-in for six
weeks. The employee could not punch out either — the app correctly refuses to
treat a July session as today's, so there was nothing to close.

### Fix — self-healing, so it survives a failed cron

```php
use Illuminate\Support\Facades\Log;

// inside the DB::transaction closure, replacing the block above
$todayIST = \Carbon\Carbon::now('Asia/Kolkata')->toDateString();

$openSessions = AttendanceSessionModel::where('employee_id', $employee->id)
    ->where('status', 'active')
    ->lockForUpdate()
    ->get();

foreach ($openSessions as $open) {
    // Opened today = a genuine conflict; the employee really is punched in.
    if (optional($open->date)->toDateString() === $todayIST) {
        return ['error' => 'SESSION_ALREADY_OPEN', 'session' => $open];
    }

    // Older = an orphan. Close it and let today's punch proceed rather than
    // locking the account out forever.
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

**On the values:** `duration_seconds = 0` and `ended_at = started_at` record
**no worked time**. That is deliberate — there is no evidence the employee was
working, and session 111 had `ping_count = 0`. Please do **not** compute
`now() - started_at`; on session 111 that posts a six-week shift.

Use `force_closed`, not `closed`, so these stay distinguishable in an audit —
and see item 10.

---

## 2. 🔴 Nothing ever closes a stale session

**File:** `Kernel.php`

`force_closed` appears in the status enum and **nowhere else in the
codebase**. Your scheduler has eight entries — biometric sync, attendance
processing, monthly summary/resync, leave accrual, ping purge, probation
reminders — plus this:

```php
// Punch-out reminder — FCM at 19:00 IST to employees punched in over 9 hours
$schedule->call(function () {
    $nineHoursAgo = now()->subHours(9);
    AttendanceSessionModel::where('status', 'active')
        ->where('started_at', '<', $nineHoursAgo)  // ... sends FCM ...
})->dailyAt('19:00')->timezone('Asia/Kolkata');
```

So the system already **knows** long-running sessions happen — it nudges the
employee and never closes anything. Ignore the notification, change phone, or
uninstall, and the session is open forever.

### Fix

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

            // These are MISSING PUNCH-OUTS. Log every one — closing them
            // silently hides a real attendance problem from HR.
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

Register in `Kernel.php::schedule()`:

```php
/**
 * Force-close attendance sessions left open past IST midnight.
 * Without this an employee who forgets to punch out is locked out of
 * attendance permanently (punch-in 409s, punch-out has nothing to close).
 */
$schedule->command('attendance:force-close-stale')
    ->dailyAt('00:15')
    ->timezone('Asia/Kolkata')
    ->withoutOverlapping()
    ->runInBackground()
    ->appendOutputTo(storage_path('logs/attendance-force-close.log'));
```

`commands()` already does `$this->load(__DIR__.'/Commands')`, so no other
wiring is needed.

**Please decide:** should a force-closed session raise a regularisation
request for the employee, or just appear in an HR report? Right now the
worked time is simply lost.

---

## 3. 🔴 `today()` returns an active session from any date

**File:** `AttendanceViewController::today()`

```php
$today  = now()->toDateString();

$active = AttendanceSessionModel::where('employee_id', $employee->id)
    ->where('status', 'active')
    ->first();                       // ← no date filter
```

Inconsistent within the same method: `$punches` uses
`whereDate('punched_at', $today)` and `$sessionsToday` uses
`whereDate('date', $today)`. Only `$active` is unscoped — which is how our app
was handed a July session as "today's".

```php
$active = AttendanceSessionModel::where('employee_id', $employee->id)
    ->where('status', 'active')
    ->where(function ($q) use ($today) {
        // Mirrors the fallback already used in history().
        $q->whereDate('date', $today)
          ->orWhereDate('started_at', $today);
    })
    ->first();
```

---

## 4. 🔴 Close the sessions already stuck

```sql
-- Inspect first. Every row is a locked-out employee.
SELECT id, employee_id, branch_id, date, started_at, ping_count
FROM attendance_sessions
WHERE status = 'active' AND date < CURDATE()
ORDER BY started_at;
```

```sql
-- TAKE A BACKUP FIRST. No LIMIT, and this rewrites historical attendance.
UPDATE attendance_sessions
SET status           = 'force_closed',
    ended_at         = COALESCE(ended_at, started_at),
    duration_seconds = 0
WHERE status = 'active' AND date < CURDATE();
```

> `CURDATE()` uses the **MySQL session timezone**, not PHP's. Confirm they
> match, or run it through `php artisan tinker` so Carbon governs the boundary.

**Please send the row count from the SELECT** — it tells us how many people
have been silently locked out, and for how long.

---

## 5. ✅ RETRACTED — branch geofence data is correct

**This item was wrong and I withdraw it.** Verified against the live API on
1 Sep:

```json
GET /me/geofence
{"branch_id":9,"branch_name":"FACTORY KAMSHET",
 "latitude":18.753837,"longitude":73.583616,
 "radius_m":100,"geofence_attendance":"Yes"}
```

The employee is assigned to **FACTORY KAMSHET** (18.7538, 73.5836) and was
punching from **Baner, Pune** (18.5743, 73.7737). Those really are ~28 km
apart, so `distance_m: 28276` and `inside_geofence: false` are **correct** —
the Haversine is right and so is the data.

I inferred a data error from the distance alone without checking which branch
the employee belonged to. Apologies for the noise. No action needed.

## 6. 🟠 `punchOut()` can write a multi-week duration

**File:** `AttendancePunchController::punchOut()`

```php
$duration = $now->diffInSeconds($session->started_at);
$session->update([
    'ended_at' => $now, 'duration_seconds' => $duration, 'status' => 'closed',
]);
```

The only guard is `status !== 'active'`. There is **no check that the session
belongs to today**. Punching out session 111 would have written roughly
**3.8 million seconds**, and that figure flows into `total_seconds` on
`/attendance/today` and `/attendance/history`. It is also why item 4 must be
done in SQL rather than by punching out.

```php
$todayIST = \Carbon\Carbon::now('Asia/Kolkata')->toDateString();

if (optional($session->date)->toDateString() !== $todayIST) {
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

If you add `SESSION_EXPIRED`, tell us and we will handle it explicitly.

---

## 7. 🟠 Normalise `captured_at` timezone on write

Your guide (§6.4) says:

> `client_captured_at`: send in any format Laravel can parse (UTC with `Z` or
> IST with `+05:30` — both work).

**That is not true today**, and it produced a visible bug. When we sent
`2026-08-31T10:57:00.000Z`, Eloquent wrote the Carbon's own timezone into the
column — storing `10:57` — then read it back in the app timezone, making it
10:57 **IST**. Location pings rendered **5h30m before** the punch-in that
opened their session. Evidence, from your own table:

| id | captured_at | received_at | gap |
|---|---|---|---|
| 162 | 12:23:49 | 17:53:50 | **5:30** |
| 163 | 12:53:54 | 18:23:55 | **5:30** |
| 306 | 16:27:52 | 16:27:52 | 0 ← after our fix |

We now send an explicit `+05:30` offset, so this is worked around client-side.
Please still normalise on write so no future client can hit it:

```php
'captured_at' => Carbon::parse($request->input('captured_at'))
                       ->setTimezone(config('app.timezone')),
```

Same for `client_captured_at` on punches. Then §6.4's claim becomes true.

---

## 8. 🟠 `live()` returns the entire branch row

**File:** `AttendanceViewController::live()`

```php
'employee' => [
    'id' => ..., 'emp_name' => ..., 'emp_code' => ...,   // hand-picked
],
'branch'   => $s->branch,      // ← whole Eloquent model
```

`BranchModel::$fillable` includes `l1`–`l6`, `on_site`, `qa`, `ehs`, `store`,
`qs_billing`, `ec_l1`–`ec_l6` and `address` — so the admin dashboard receives
the entire approval hierarchy and branch address on **every active session**,
up to `limit` (default 100). Your own eager-load already asks for only two
columns (`'branch:id,branch_name'`), so the intent was clearly narrower.

```php
'branch' => [
    'id'          => $s->branch->id ?? null,
    'branch_name' => $s->branch->branch_name ?? '',
],
```

Transparent to us — we read `branch['branch_name']`.

---

## 9. 🟡 `live()` N+1

```php
$data = $sessions->map(function ($s) {
    $lastPing = AttendanceLocationPingModel::where('session_id', $s->id)
        ->latest('captured_at')->first();      // one query per session
```

100 active sessions = 101 queries, on a screen the dashboard polls. Use a
`latestOfMany` relation:

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

## 10. 🟡 `ALREADY_PUNCHED_TODAY` ignores `force_closed`

```php
->where('status', 'closed')          // force_closed not included
->whereDate('date', $todayIST)
```

This is **correct and necessary** for item 1's fix — after a stale session is
force-closed the employee must be able to punch in. But it also means a
session force-closed *today* would let them start a second cycle, which the
"one cycle per day" rule otherwise forbids.

Fine as-is. Flagging so it is a decision rather than an accident — please
confirm.

---

## 11. 🟡 Restore the guide's Known Issues section

v1.1 replaced "Known Issues & Bugs" with "Notes & Caveats" and dropped all ten
entries. Most were genuinely fixed — but two were **not** and now have no
record anywhere:

- old §6.7 — no temporal bounds on `client_captured_at` (a tampered client can
  backdate attendance; `before:+5 minutes` / `after:-7 days` would fix it)
- old §6.10 — the `live()` N+1 above

Please restore them, or move them to your issue tracker.

That disclosure was the most useful thing in v1.0 — it is how we found four
real problems without guessing. Losing it means the next person inherits them
blind.

---

## 11b. Closed — no longer asking

For clarity, these are resolved and off the list:

- ✅ **`pings_last_24h`** — answered by your table dump. Pings arrive fine; we
  have confirmed rows including a full 30-minute cadence on 1 Sep.
- ✅ **`started_at` in the 409 body** — already present in `punchIn()`. We now
  read it inline and skip the extra `/attendance/today` call. Thank you.
- ✅ `hasGeofence()` NULL→0 cast — fixed, verified in source
- ✅ `/today` and `/history` punches carry `session_id`, coordinates,
  `accuracy_m`, `address`, `selfie_url` — verified in source
- ✅ Model `$casts` — all float/integer/boolean, numbers arrive as JSON numbers
- ✅ `lockForUpdate()` genuinely inside the transaction
- ✅ `timeline()` allows the session owner as well as admins
- ✅ `error_code` used consistently; `GEOFENCE_NOT_ENABLED` returned
- ✅ Deploy — confirmed live; we are testing against it

---

## 12. 🔴 NEW — found during verification, 1 Sep

### 12.1 Session `started_at` is being overwritten — work hours are wrong

**This is now the highest-priority item.**

`GET /attendance/today` for employee 1822 today:

```json
"punches":[
  {"session_id":142,"type":"in", "punched_at":"2026-09-01T12:51:24+05:30", ...},
  {"session_id":142,"type":"out","punched_at":"2026-09-01T18:08:01+05:30", ...}
],
"total_seconds":1218
```

`GET /attendance/history?date=2026-09-01`, same session:

```
session 142  status closed
  started_at        2026-09-01T18:08:01+05:30     ← the PUNCH-OUT time
  ended_at          2026-09-01T18:08:01+05:30
  duration_seconds  1218
```

The punch-in was at **12:51:24** and the session's `started_at` reads
**18:08:01** — the punch-out time. So:

- Real worked time: 12:51 → 18:08 = **5 h 16 m (~18,997 s)**
- Recorded: **1,218 s (20 m 18 s)**

**The employee is credited with 20 minutes for a five-hour shift.** This
flows into `total_seconds` on both `/today` and `/history`, so it will reach
payroll and any hours report.

The punch rows themselves are correct — only the session's `started_at` is
wrong, which means the punch data can be used to repair it.

Something is writing `started_at` after session creation. The `punchOut()` I
reviewed only updates `punch_out_id`, `ended_at`, `duration_seconds`,
`status` — so this is either newer code or another job. Worth checking
whether the biometric `attendance:process` / `attendance:sync` commands touch
`attendance_sessions`.

Oddity that may point at the cause: `1218 s` before `18:08:01` is `17:47:43`,
which is within a second of that session's **last ping** (17:47:42).

**Please also audit historical rows:**

```sql
-- Sessions whose start does not match their punch-in
SELECT s.id, s.employee_id, s.started_at, p.punched_at AS real_punch_in,
       s.duration_seconds
FROM attendance_sessions s
JOIN attendance_punches p ON p.id = s.punch_in_id
WHERE ABS(TIMESTAMPDIFF(SECOND, s.started_at, p.punched_at)) > 60;
```

Repair, once the write is found, is straightforward since the punches survive:

```sql
UPDATE attendance_sessions s
JOIN attendance_punches pin  ON pin.id  = s.punch_in_id
JOIN attendance_punches pout ON pout.id = s.punch_out_id
SET s.started_at       = pin.punched_at,
    s.ended_at         = pout.punched_at,
    s.duration_seconds = TIMESTAMPDIFF(SECOND, pin.punched_at, pout.punched_at)
WHERE s.status = 'closed';
```

### 12.2 The force-close job writes `ended_at` before `started_at`

The job shipped and works — session 134 is now `force_closed` — but the row
it produced is invalid:

```
session 134  status force_closed
  started_at  2026-09-01T00:15:03+05:30
  ended_at    2026-08-31T17:54:33+05:30     ← BEFORE started_at
  duration_seconds 0
```

Session 134 was actually opened on **31 Aug** (its first ping is 16:27 that
day). `started_at` now reads **1 Sep 00:15:03**, which looks like the cron's
own run time, while `ended_at` is the last ping.

So the job appears to be stamping `started_at = now()`. `duration_seconds = 0`
is correct and intended; `started_at` should be left untouched.

A quick guard would catch both this and 12.1:

```sql
SELECT id, employee_id, started_at, ended_at, status
FROM attendance_sessions
WHERE ended_at IS NOT NULL AND ended_at < started_at;
```

That should never return a row.

### 12.3 Confirmed fixed (verified, not reported)

- **`live()` branch leak** — now returns
  `"branch":{"id":45,"branch_name":"THE AQUA RETREAT"}`. No `l1`…`ec_l6`, no
  `address`. Item 8 closed.
- **`captured_at` timezone** — today's pings store IST correctly
  (`13:39:10+05:30` etc.), no 5h30m drift. Item 7 closed.
- **Stale session cleanup** — session 134 force-closed. Item 4 closed.

### 12.4 Our pings are working correctly

For the record, from the same query — session 142's pings:

```
13:39:10  14:09:10  14:47:38  15:17:43  15:47:42
16:17:42  16:47:42  17:17:43  17:47:42
```

Six consecutive intervals of 30 m ±5 s, across four hours, with the app
swiped out of recents. The 14:47 outlier was a service restart during
testing, and the schedule self-corrected immediately afterwards. No
duplicates, no drift.

---

## 13. Verification

- [ ] §4 SELECT returns zero rows after the UPDATE
- [ ] Insert a test session dated yesterday, `status='active'` → punch-in
      returns **201**, the old session becomes `force_closed`, warning logged
- [ ] `/attendance/today` no longer returns a previous-day `active_session`
- [ ] `php artisan attendance:force-close-stale` runs clean and logs each closure
- [ ] Session left open overnight → force-closed by morning, punch-in works
- [ ] A punch at the employee's actual office reports `inside_geofence: true`
      and a distance in metres, not tens of kilometres
- [ ] `/attendance/live` no longer contains `l1`…`ec_l6` or `address`
- [ ] No session has an implausible `duration_seconds`
- [ ] A ping sent with `...Z` and one sent with `+05:30` store the same instant

---

## 14. What we changed on our side

No action needed — for context:

- Punches are persisted locally **only after** the server accepts them, and
  the card clears when `/attendance/today` reports no punches. The app no
  longer shows attendance the database doesn't have.
- `captured_at` / `client_captured_at` now carry an explicit `+05:30` offset.
- 409 `SESSION_ALREADY_OPEN`: a session from today is adopted so punch-out
  works; an older one is reported by date and ID as needing an administrator,
  instead of the impossible "punch out first".
- Background pings rebuilt on a real foreground service — verified surviving
  swipe-from-recents at an exact 30-minute cadence, and auto-restarting after
  the OS kills it.
- A second phone logging in mid-shift now adopts the open session and
  continues the trail.
- Punch and ping calls log status and response body; field names are pinned by
  tests against your guide.
