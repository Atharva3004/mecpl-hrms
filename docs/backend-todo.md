# Backend — What's Left To Do

**Date:** 2026-09-01
**From:** Mobile (Flutter) team
**Status:** verified against the live API, not taken on trust

This replaces every earlier list. If you read one file, read this one.

---

## Summary

| # | Item | Priority | Effort |
|---|---|---|---|
| **1** | `started_at` overwritten → 5-hour shift recorded as 20 minutes | 🔴 **P0 — payroll** | ~1 h |
| **2** | Force-close job stamps `started_at = now()` | 🔴 **P0 — runs tonight** | ~15 min |
| **3** | Return `battery_pct` on pings and punches | 🟢 small | ~10 min |
| **4** | Confirm the punch-in date filter shipped | ❓ confirm | — |
| **5** | Confirm `today()` date filter shipped | ❓ confirm | — |
| **6** | `live()` N+1 — one query per active session | 🟡 P2 | ~15 min |
| **7** | `ALREADY_PUNCHED_TODAY` vs `force_closed` — confirm intent | 🟡 P2 | decision |
| **8** | Restore the guide's deleted Known Issues section | 🟡 P2 | ~10 min |

**Items 1 and 2 are the only urgent ones.** Item 2 corrupts more rows every
night it stays in.

### Already done — verified, not just reported

`live()` branch leak fixed · `captured_at` stores IST (no 5h30m drift) ·
stale-session cleanup ran (session 134 force-closed) · `/me/geofence` correct ·
punch payloads carry `session_id`, coordinates, `accuracy_m`, `address`,
`selfie_url`.

And a retraction: **my earlier claim that branch geofence coordinates were
wrong was my mistake.** FACTORY KAMSHET's coordinates are correct and the
28 km reading was accurate — the employee was simply punching from Pune.
Apologies for the noise.

---

## 1. 🔴 P0 — `started_at` is being overwritten (payroll impact)

### Evidence

`GET /attendance/today`, employee 1822, 1 Sep — **punches are correct**:

```json
"punches":[
  {"session_id":142,"type":"in", "punched_at":"2026-09-01T12:51:24+05:30"},
  {"session_id":142,"type":"out","punched_at":"2026-09-01T18:08:01+05:30"}
],
"total_seconds":1218
```

`GET /attendance/history?date=2026-09-01`, **the same session** — the session
row contradicts its own punches:

```
session 142  status closed
  started_at        2026-09-01T18:08:01+05:30    ← this is the PUNCH-OUT time
  ended_at          2026-09-01T18:08:01+05:30
  duration_seconds  1218
```

| | |
|---|---|
| Punch-in | 12:51:24 |
| Punch-out | 18:08:01 |
| **Actual worked time** | **5 h 16 m 37 s = 18,997 s** |
| **Recorded** | **1,218 s = 20 m 18 s** |

**A five-hour shift is credited as 20 minutes**, and that number is what both
endpoints return as `total_seconds` — so hours reports and payroll inherit it.

### Where to look

The `punchOut()` I reviewed only updates `punch_out_id`, `ended_at`,
`duration_seconds` and `status` — it never touches `started_at`. So this is
newer code or a different writer. Worth checking whether `attendance:sync` or
`attendance:process` (running every minute and every 15 minutes) write to
`attendance_sessions`.

**A clue:** 1,218 s before 18:08:01 is **17:47:43**, within one second of that
session's **last location ping** (17:47:42). `started_at` may be getting set
from the most recent ping rather than the punch-in.

### Audit

```sql
-- Sessions whose start disagrees with their own punch-in row
SELECT s.id, s.employee_id, s.date,
       s.started_at, p.punched_at AS real_punch_in,
       s.duration_seconds
FROM attendance_sessions s
JOIN attendance_punches p ON p.id = s.punch_in_id
WHERE ABS(TIMESTAMPDIFF(SECOND, s.started_at, p.punched_at)) > 60
ORDER BY s.date DESC;
```

**Please send the row count.** It tells us how far back the under-recording
goes and whether past payroll runs were affected.

### Repair

The punch rows survived, so sessions can be rebuilt from them. **Back up
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

**Fix the write first** — otherwise the next punch-out re-corrupts the row.

---

## 2. 🔴 P0 — Force-close job writes `ended_at` before `started_at`

The job shipped and does close stale sessions, but the row it leaves is
invalid:

```
session 134  status force_closed
  started_at        2026-09-01T00:15:03+05:30
  ended_at          2026-08-31T17:54:33+05:30    ← BEFORE started_at
  duration_seconds  0
```

Session 134 was really opened on **31 Aug** (its first ping is 16:27 that day).
`started_at` now reads **1 Sep 00:15:03** — the scheduled run time of the
force-close command itself. So the job appears to be doing:

```php
$session->update([
    'status'     => 'force_closed',
    'started_at' => now(),        // ← must not be touched
    'ended_at'   => $lastActivity,
]);
```

`duration_seconds = 0` is correct and intended. **`started_at` is the
employee's real punch-in time and the only record of when the shift began:**

```php
$session->update([
    'status'           => 'force_closed',
    'ended_at'         => $session->ended_at ?? $session->started_at,
    'duration_seconds' => 0,
]);
```

Repair the rows already touched:

```sql
UPDATE attendance_sessions s
JOIN attendance_punches p ON p.id = s.punch_in_id
SET s.started_at = p.punched_at
WHERE s.status = 'force_closed'
  AND s.punch_in_id IS NOT NULL
  AND s.started_at > p.punched_at;
```

**This runs again tonight at 00:15.** Every night it stays in, more sessions
lose their real start time.

### A guard that would have caught both

```sql
SELECT id, employee_id, date, started_at, ended_at, status
FROM attendance_sessions
WHERE ended_at IS NOT NULL AND ended_at < started_at;
```

That must never return a row. Worth a daily check with an alert, or a
constraint on MySQL 8.0.16+:

```sql
ALTER TABLE attendance_sessions
  ADD CONSTRAINT chk_session_times
  CHECK (ended_at IS NULL OR ended_at >= started_at);
```

And one for the duration itself, since that is what makes this a payroll bug:

```sql
SELECT id, started_at, ended_at, duration_seconds,
       TIMESTAMPDIFF(SECOND, started_at, ended_at) AS expected
FROM attendance_sessions
WHERE status = 'closed'
  AND ABS(duration_seconds - TIMESTAMPDIFF(SECOND, started_at, ended_at)) > 60;
```

---

## 3. 🟢 Return `battery_pct` (you already store it)

We want the device's battery level on the map and timeline beside each point,
the way Snapchat's map shows it. It explains gaps in a trail — a flat phone
and a switched-off phone look identical otherwise.

**The data is already there.** We send it on every ping and every punch; you
store both. It is simply never returned.

### Pings — one line, twice

`attendance_location_pings.battery_pct` is populated (your own table dump
showed 72, 73, 75). Neither read endpoint returns it:

```
history  ping keys: [latitude, longitude, captured_at, inside_geofence, accuracy_m, selfie_url]
timeline ping keys: [latitude, longitude, captured_at, inside_geofence, accuracy_m, selfie_url]
```

In `AttendanceViewController`, both `history()` and `timeline()`:

```php
'pings' => $s->pings->map(fn ($p) => [
    // ... existing fields ...
    'battery_pct' => $p->battery_pct,        // ← add
]),
```

Your guide §3.7 already documents `battery_pct` in the history ping example,
so this is the response catching up with the contract. Worth adding to
`live()`'s `last_ping` too — the admin dashboard gets it free.

### Punches — one line, from `device_info`

`attendance_punches` has no battery column, but since 1 Sep we send it inside
the `device_info` JSON on punch-in and punch-out, alongside model, OS, app
version and `device_id`. The column is cast to `array`:

```php
// today() and history() punch maps
'battery_pct' => data_get($p->device_info, 'battery_pct'),   // ← add
```

Without this the punch-in is the one point on the trail with no reading.

Returning the whole `device_info` object works too — we parse the nested value
either way. Returning just `battery_pct` keeps the payload smaller and avoids
handing the employee's own client a block of device metadata it has no use for.

**Our side is done** — both shapes are parsed and the badge renders the moment
the field appears. No app release needed.

---

## 4–5. ❓ Please confirm these shipped

Neither is verifiable from outside without deliberately corrupting data.

**4. Punch-in date filter** — the actual lockout fix. Without it, an employee
who forgets to punch out stays locked out until the nightly job runs:

```php
// AttendancePunchController::punchIn()
$existing = AttendanceSessionModel::where('employee_id', $employee->id)
    ->where('status', 'active')
    ->lockForUpdate()
    ->first();                    // ← any date at all
```

**5. `today()` date filter** — same omission, `AttendanceViewController::today()`:

```php
$active = AttendanceSessionModel::where('employee_id', $employee->id)
    ->where('status', 'active')
    ->first();                    // ← no date filter
```

Both fixes are in `backend-remaining-work.md` §1 and §3 if you still need them.

---

## 6. 🟡 `live()` N+1

```php
$data = $sessions->map(function ($s) {
    $lastPing = AttendanceLocationPingModel::where('session_id', $s->id)
        ->latest('captured_at')->first();      // one query per session
```

100 active sessions = 101 queries, on a screen the dashboard polls.

```php
// AttendanceSessionModel
public function latestPing(): HasOne
{
    return $this->hasOne(AttendanceLocationPingModel::class, 'session_id')
                ->latestOfMany('captured_at');
}
```

Then add `'latestPing'` to the `with([...])` and use `$s->latestPing`.

---

## 7. 🟡 `ALREADY_PUNCHED_TODAY` ignores `force_closed`

```php
->where('status', 'closed')          // force_closed not included
->whereDate('date', $todayIST)
```

This is **required** for the punch-in fix — after a stale session is
force-closed the employee must be able to punch in. But it also means a
session force-closed *today* would let them start a second cycle, which the
"one cycle per day" rule otherwise forbids.

Fine as-is. Flagging so it is a decision rather than an accident.

---

## 8. 🟡 Restore the guide's Known Issues section

v1.1 replaced "Known Issues & Bugs" with "Notes & Caveats" and dropped all ten
entries. Most were genuinely fixed — but two were **not**, and now have no
record anywhere:

- old §6.7 — no temporal bounds on `client_captured_at` (a tampered client can
  backdate attendance; `before:+5 minutes` / `after:-7 days` would fix it)
- old §6.10 — the `live()` N+1 above

That disclosure was the most useful thing in v1.0 — it is how we found four
real problems without guessing. Please restore them or move them to your
tracker.

---

## What we need back

1. Row count from the §1 audit query — how far the under-recording goes
2. Confirmation that §2's `started_at = now()` is fixed **before tonight's run**
3. Yes/no on items 4 and 5

---

## For context — the client side is healthy

Session 142's pings, with the app swiped out of recents:

```
13:39 · 14:09 · 14:47 · 15:17 · 15:47 · 16:17 · 16:47 · 17:17 · 17:47
```

Six consecutive 30-minute intervals within ±5 s across four hours. No
duplicates, no drift. The 14:47 outlier was a service restart during testing
and the schedule self-corrected. Punch and ping payloads are all arriving
correctly — the problems above are confined to the session row and to fields
that are stored but never returned.
