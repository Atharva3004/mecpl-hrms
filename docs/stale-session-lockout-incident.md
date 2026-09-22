# P0 — Employees Locked Out by Stale Attendance Sessions

**Date:** 2026-08-31
**Severity:** P0 — affected employees cannot punch in **or** punch out
**Status:** app-side mitigation shipped; **backend fix required**
**Found by:** device log capture on a live Admin account

---

## 1. What we found

A device log of `GET /api/attendance/today`, captured 2026-08-31:

```json
{
  "status": true,
  "data": {
    "active_session": {
      "session_id": 111,
      "started_at": "2026-07-17T12:25:05+05:30",
      "ping_count": 0,
      "last_ping": null
    },
    "punches": [],
    "total_seconds": 0
  }
}
```

**Session 111 has been `active` since 17 July 2026 — six weeks.** It was never
closed, and it has never received a single ping.

This is not a display bug. `punches: []` is correct: the employee has been
unable to punch in at all.

---

## 2. Why this locks the employee out completely

The two actions block each other:

| Action | What happens | Why |
|---|---|---|
| **Punch in** | `409 SESSION_ALREADY_OPEN` | The server still has session 111 open |
| **Punch out** | *"No active session to close."* | The app correctly refuses to treat a 17 July session as today's, so it has nothing local to close |

The app's cross-day guard is behaving as designed — a session from July must
not show someone as clocked in today. But with the server still holding that
session open, the employee has no way out from the app. **Neither button can
succeed, and the messaging pointed them at the one action that cannot work.**

### Blast radius

This is not one account. **Any employee whose session was ever left open past
IST midnight is in the same state**, silently, from that day onward. There is
currently nothing in the system that closes them.

Please run this first — every row is a locked-out employee:

```sql
SELECT id, employee_id, branch_id, date, started_at, ping_count
FROM attendance_sessions
WHERE status = 'active'
  AND date < CURDATE()
ORDER BY started_at;
```

---

## 3. Backend — what to do

### 3.1 🔴 Immediate — unblock the affected employees

Force-close every session left open on a previous day:

```sql
-- Inspect first (query in §2), and TAKE A BACKUP before writing.
UPDATE attendance_sessions
SET status           = 'force_closed',
    ended_at         = COALESCE(ended_at, started_at),
    duration_seconds = 0
WHERE status = 'active'
  AND date < CURDATE();
```

Notes on the values above — adjust to whatever your reporting expects, but
please be deliberate about it:

- `ended_at = started_at` and `duration_seconds = 0` records **no worked
  time**, which is honest: we have no evidence the employee was working, and
  `ping_count = 0` on session 111 says nothing was tracked.
- The alternative — closing at end of shift — would credit hours nobody can
  substantiate. Please **do not** compute a duration from `started_at` to
  `now()`; on session 111 that would post a six-week shift into attendance.
- Use `force_closed`, not `closed`, so these are distinguishable from genuine
  punch-outs in any audit later.

### 3.2 🔴 Root cause — nothing ever closes an open session

Your schema defines `status = 'force_closed'` (guide §2.3) but **nothing in
the system ever sets it.** A session only closes when the employee punches
out. Miss that once and the account is locked out permanently.

Please add a scheduled job, run daily after IST midnight:

```php
// app/Console/Commands/ForceCloseStaleSessions.php
$stale = AttendanceSessionModel::where('status', 'active')
    ->where('date', '<', Carbon::now('Asia/Kolkata')->toDateString())
    ->get();

foreach ($stale as $session) {
    $session->update([
        'status'           => 'force_closed',
        'ended_at'         => $session->ended_at ?? $session->started_at,
        'duration_seconds' => 0,
    ]);
    Log::warning("Force-closed stale attendance session {$session->id} "
                 . "for employee {$session->employee_id}");
}
```

```php
// app/Console/Kernel.php
$schedule->command('attendance:force-close-stale')
         ->dailyAt('00:30')          // IST — see the timezone note below
         ->withoutOverlapping();
```

**Please log each force-close.** These represent missing punch-outs and HR
will need to see them; silently closing them hides a real attendance problem.

Two things to confirm while you're in there:

1. The job must use the **IST** day boundary, consistent with the
   `ALREADY_PUNCHED_TODAY` check. You confirmed `config/app.php` is
   `Asia/Kolkata`, so `Carbon::now()` is already IST — just don't reintroduce
   a raw SQL `CURDATE()`/`NOW()` here, since those follow the **MySQL session
   timezone**, not PHP's.
2. Decide whether a force-closed session should raise a regularisation
   request for the employee, or just a report for HR. Right now the time is
   simply lost.

### 3.3 🟠 Include `started_at` in the 409 response

Guide §3.2's `SESSION_ALREADY_OPEN` body carries only `session_id`:

```json
{ "status": false, "error_code": "SESSION_ALREADY_OPEN",
  "message": "You already have an open session.", "session_id": 142 }
```

The app now has to make a **second** call to `/attendance/today` purely to
learn *when* that session started, because that is what decides whether the
user can self-recover or needs an admin. Please add it:

```json
{ "status": false, "error_code": "SESSION_ALREADY_OPEN",
  "message": "You already have an open session.",
  "session_id": 142,
  "started_at": "2026-08-31T09:30:15+05:30" }
```

Additive and backwards-compatible — we read it when present and fall back to
the extra call when it isn't.

### 3.4 🟠 Consider rejecting the punch-in block for stale sessions

Optional, and your call: when punch-in hits an active session whose `date`
is **before today**, the server could force-close it and allow the punch to
proceed, rather than returning 409. That removes the lockout at the source
even if the nightly job fails. If you prefer to keep 409, §3.2 must be
reliable — it becomes the only thing preventing recurrence.

### 3.5 Still outstanding from Round 2

Unchanged and still blocking our end-to-end testing:

- [ ] **Deploy confirmation** — is the round-1/round-2 work live on `hrms.mecpl.in`?
- [ ] `pings_last_24h` count + any 409/422/429 on `/attendance/location-ping`
- [ ] Branch geofence audit (which branches have lat/lng/radius populated)

`ping_count: 0` on session 111 is consistent with pings never having worked —
but that session predates our background-permission fix, so it proves
nothing either way. **We still need the ping count.**

---

## 4. Flutter — what we did (shipped)

### 4.1 Distinguish a recoverable session from an orphaned one

`punchInWithLocation` now resolves what a 409 actually means before writing a
message, in `_resolveOpenSessionConflict()`:

| Open session started… | Behaviour |
|---|---|
| **Today** | **Auto-recovered.** The device just lost its local copy — reinstall, cleared data, new phone. We adopt the session so punch-out works: *"You are already punched in for today (since 09:30 AM). Your session has been restored — punch out when you finish."* |
| **An earlier day / unknown** | **Named and escalated.** *"You have an attendance session still open from 17/7/2026 (ID 111). It must be closed by an administrator before you can punch in again."* |

The old message — *"You already have an open session. Punch out first."* —
was impossible advice in the second case and is what left people stuck with
no idea why.

Note this **does not** auto-close a stale session. Punching out a six-week-old
session would write a bogus duration into attendance; that correction belongs
on the server where it can be audited.

### 4.2 Diagnostic logging on the punch and ping paths

Neither path logged anything — a failed punch left no trace beyond an error
string on screen, which is why this took a live device capture to find. Both
now log status and body:

- `🟪 [PUNCH]` — endpoint, fields, HTTP status, full response body
- `🟨 [PING]` — session id, HTTP status, body on any non-200

### 4.3 Already shipped earlier, relevant here

- `active_session.started_at` was being read as `opened_at` — a key that does
  not exist in your contract. It parsed to null, the cross-day guard read null
  as "stale", and **live sessions were being wiped from memory and disk on
  every refresh.** Fixed, plus the guard now requires positive evidence before
  doing anything destructive.
- `test/api_contract_test.dart` pins field names against your guide's own
  examples so a rename fails a test instead of reaching production.

---

## 5. Verification, once the backend fix is deployed

1. Run the §2 query — expect **zero** rows.
2. On a previously locked-out account: punch in → succeeds, returns a new
   `session_id`.
3. Check `🟨 [PING]` appears within seconds of punch-in (our punch-in ping).
4. Admin → Today's Timing → Intermediate Tracking ON → the trail renders.
5. Reinstall the app mid-shift and punch in → expect the **auto-recovery**
   message, and punch-out must work.
6. Leave a session open overnight → next morning the nightly job has
   force-closed it, and punch-in works normally.

---

## 6. Summary

| Owner | Action | Priority |
|---|---|---|
| Backend | Force-close stale sessions (§3.1) | 🔴 now |
| Backend | Nightly force-close job (§3.2) | 🔴 now |
| Backend | Add `started_at` to the 409 body (§3.3) | 🟠 |
| Backend | Deploy confirmation + ping count + branch audit (§3.5) | 🔴 still open |
| Flutter | 409 recovery + clear messaging (§4.1) | ✅ done |
| Flutter | Punch/ping logging (§4.2) | ✅ done |

**The app can only ever report this problem accurately — it cannot fix it.
Until stale sessions are closed server-side, affected employees stay locked
out.**
