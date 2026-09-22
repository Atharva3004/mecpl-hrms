# Backend — Action Required

**Date:** 2026-09-01
**From:** Mobile (Flutter) team

Open items only. Anything already fixed has been removed from this list.

| # | Item | Priority |
|---|---|---|
| 1 | `started_at` overwritten → 5-hour shift recorded as 20 minutes | 🔴 **P0 — payroll** |
| 2 | Force-close job stamps `started_at = now()` | 🔴 **P0 — runs tonight 00:15** |
| 3 | Return `battery_pct` on pings and punches | 🟢 ~10 min |
| 4 | Confirm the punch-in date filter shipped | ❓ answer needed |
| 5 | Confirm the `today()` date filter shipped | ❓ answer needed |
| 6 | `live()` N+1 — one query per active session | 🟡 |
| 7 | `ALREADY_PUNCHED_TODAY` vs `force_closed` — confirm intent | 🟡 |
| 8 | Restore the guide's deleted Known Issues entries | 🟡 |

---

## 1. 🔴 `started_at` is being overwritten — worked hours are wrong

### Evidence

`GET /attendance/today`, employee 1822, 1 Sep — punches are correct:

```json
"punches":[
  {"session_id":142,"type":"in", "punched_at":"2026-09-01T12:51:24+05:30"},
  {"session_id":142,"type":"out","punched_at":"2026-09-01T18:08:01+05:30"}
],
"total_seconds":1218
```

`GET /attendance/history?date=2026-09-01`, same session — the session row
contradicts its own punches:

```
session 142  status closed
  started_at        2026-09-01T18:08:01+05:30    ← the PUNCH-OUT time
  ended_at          2026-09-01T18:08:01+05:30
  duration_seconds  1218
```

| | |
|---|---|
| Punch-in | 12:51:24 |
| Punch-out | 18:08:01 |
| **Actual worked time** | **5 h 16 m 37 s = 18,997 s** |
| **Recorded** | **1,218 s = 20 m 18 s** |

`total_seconds` is what both endpoints return, so hours reports and payroll
inherit this figure.

### Where to look

`punchOut()` updates only `punch_out_id`, `ended_at`, `duration_seconds` and
`status` — it never touches `started_at`. So this is newer code or a different
writer. Check whether `attendance:sync` or `attendance:process` (every minute /
every 15 minutes) write to `attendance_sessions`.

**Clue:** 1,218 s before 18:08:01 is **17:47:43**, within one second of that
session's last location ping (17:47:42). `started_at` may be being set from the
most recent ping instead of the punch-in.

### Audit — please send us the row count

```sql
SELECT s.id, s.employee_id, s.date,
       s.started_at, p.punched_at AS real_punch_in,
       s.duration_seconds
FROM attendance_sessions s
JOIN attendance_punches p ON p.id = s.punch_in_id
WHERE ABS(TIMESTAMPDIFF(SECOND, s.started_at, p.punched_at)) > 60
ORDER BY s.date DESC;
```

It tells us how far back the under-recording goes and whether past payroll runs
were affected.

### Repair

Punch rows survived, so sessions can be rebuilt from them. **Back up
`attendance_sessions` first** — this rewrites historical attendance.

```sql
UPDATE attendance_sessions s
JOIN attendance_punches pin  ON pin.id  = s.punch_in_id
JOIN attendance_punches pout ON pout.id = s.punch_out_id
SET s.started_at       = pin.punched_at,
    s.ended_at         = pout.punched_at,
    s.duration_seconds = TIMESTAMPDIFF(SECOND, pin.punched_at, pout.punched_at)
WHERE s.status = 'closed'
  AND s.punch_in_id IS NOT NULL
  AND s.punch_out_id IS NOT NULL;
```

**Fix the write first**, or the next punch-out re-corrupts the row.

---

## 2. 🔴 Force-close job writes `ended_at` before `started_at`

```
session 134  status force_closed
  started_at        2026-09-01T00:15:03+05:30
  ended_at          2026-08-31T17:54:33+05:30    ← BEFORE started_at
  duration_seconds  0
```

Session 134 was opened on **31 Aug** (first ping 16:27 that day). `started_at`
now reads **1 Sep 00:15:03** — the scheduled run time of the force-close
command. So the job is doing something like:

```php
$session->update([
    'status'     => 'force_closed',
    'started_at' => now(),        // ← must not be touched
    'ended_at'   => $lastActivity,
]);
```

`duration_seconds = 0` is correct. `started_at` is the employee's real
punch-in time and the only record of when the shift began — leave it alone:

```php
$session->update([
    'status'           => 'force_closed',
    'ended_at'         => $session->ended_at ?? $session->started_at,
    'duration_seconds' => 0,
]);
```

Repair rows already touched:

```sql
UPDATE attendance_sessions s
JOIN attendance_punches p ON p.id = s.punch_in_id
SET s.started_at = p.punched_at
WHERE s.status = 'force_closed'
  AND s.punch_in_id IS NOT NULL
  AND s.started_at > p.punched_at;
```

**This runs again tonight at 00:15.** Every night it stays in, more sessions
lose their start time.

### Guards worth adding

```sql
-- must never return a row
SELECT id, employee_id, date, started_at, ended_at, status
FROM attendance_sessions
WHERE ended_at IS NOT NULL AND ended_at < started_at;
```

```sql
-- duration should match the timestamps it came from
SELECT id, started_at, ended_at, duration_seconds,
       TIMESTAMPDIFF(SECOND, started_at, ended_at) AS expected
FROM attendance_sessions
WHERE status = 'closed'
  AND ABS(duration_seconds - TIMESTAMPDIFF(SECOND, started_at, ended_at)) > 60;
```

On MySQL 8.0.16+ the first can be a constraint:

```sql
ALTER TABLE attendance_sessions
  ADD CONSTRAINT chk_session_times
  CHECK (ended_at IS NULL OR ended_at >= started_at);
```

---

## 3. 🟢 Return `battery_pct` — you already store it

We want the battery level shown on the map and timeline beside each point, so
a gap in a trail can be explained (a flat phone and a switched-off phone look
identical otherwise).

We send it on every ping and every punch; you store both. It is never
returned.

### Pings

Neither read endpoint includes it:

```
history  ping keys: [latitude, longitude, captured_at, inside_geofence, accuracy_m, selfie_url]
timeline ping keys: [latitude, longitude, captured_at, inside_geofence, accuracy_m, selfie_url]
```

`AttendanceViewController`, in **both** `history()` and `timeline()`:

```php
'pings' => $s->pings->map(fn ($p) => [
    // ... existing fields ...
    'battery_pct' => $p->battery_pct,        // ← add
]),
```

Your guide §3.7 already documents `battery_pct` in the history ping example.
Worth adding to `live()`'s `last_ping` too.

### Punches

`attendance_punches` has no battery column — we send it inside the
`device_info` JSON on punch-in / punch-out. The column is cast to `array`:

```php
// today() and history() punch maps
'battery_pct' => data_get($p->device_info, 'battery_pct'),   // ← add
```

Without this the punch-in is the only point on the trail with no reading.

Returning the whole `device_info` object also works — we parse the nested
value either way. Returning just `battery_pct` keeps the payload smaller.

No app release needed; the badge renders as soon as the field appears.

---

## 4–5. ❓ Please confirm these shipped

Not verifiable from outside without deliberately corrupting data.

**4. Punch-in date filter.** Without it, an employee who forgets to punch out
stays locked out until the nightly job runs:

```php
// AttendancePunchController::punchIn()
$existing = AttendanceSessionModel::where('employee_id', $employee->id)
    ->where('status', 'active')
    ->lockForUpdate()
    ->first();                    // ← matches any date
```

**5. `today()` date filter** — same omission:

```php
// AttendanceViewController::today()
$active = AttendanceSessionModel::where('employee_id', $employee->id)
    ->where('status', 'active')
    ->first();                    // ← no date filter
```

Fixes for both are in `backend-remaining-work.md` §1 and §3 if still needed.

---

## 6. 🟡 `live()` N+1

```php
$data = $sessions->map(function ($s) {
    $lastPing = AttendanceLocationPingModel::where('session_id', $s->id)
        ->latest('captured_at')->first();      // one query per session
```

100 active sessions = 101 queries, on a polled dashboard.

```php
// AttendanceSessionModel
public function latestPing(): HasOne
{
    return $this->hasOne(AttendanceLocationPingModel::class, 'session_id')
                ->latestOfMany('captured_at');
}
```

Then add `'latestPing'` to `with([...])` and use `$s->latestPing`.

---

## 7. 🟡 `ALREADY_PUNCHED_TODAY` ignores `force_closed`

```php
->where('status', 'closed')          // force_closed not included
->whereDate('date', $todayIST)
```

Required for the punch-in fix — after a stale session is force-closed the
employee must be able to punch in. But it also lets a session force-closed
*today* start a second cycle, which "one cycle per day" otherwise forbids.

Confirm this is intended.

---

## 8. 🟡 Restore two deleted Known Issues entries

Guide v1.1 dropped the Known Issues section. Two entries in it were never
fixed and now have no record anywhere:

- **`client_captured_at` has no temporal bounds** — a tampered client can
  backdate attendance. `before:+5 minutes` / `after:-7 days` would fix it.
- **`live()` N+1** — item 6 above.

---

## What we need back

1. Row count from the §1 audit query
2. Confirmation §2 is fixed **before tonight's 00:15 run**
3. Yes / no on items 4 and 5
