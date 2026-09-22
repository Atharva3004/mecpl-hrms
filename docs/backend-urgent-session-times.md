# 🔴 URGENT — Session times are wrong, worked hours are being under-recorded

**Date:** 2026-09-01
**From:** Mobile (Flutter) team
**Found:** verifying your fixes against the live API with a real employee session
**Impact:** **payroll** — a 5-hour shift is recorded as 20 minutes

---

## 0. Two bugs, both about `attendance_sessions` timestamps

| # | Bug | Impact |
|---|---|---|
| **1** | `started_at` overwritten with a later time | Worked hours badly under-recorded → **payroll** |
| **2** | Force-close job stamps `started_at = now()` | `ended_at` lands *before* `started_at` |

Bug 2 runs nightly at 00:15, so it corrupts more rows every night it stays in.

**Good news first:** the rest of your work checks out. Verified working —
the `live()` branch leak is fixed, `captured_at` now stores IST correctly with
no 5h30m drift, and the stale-session cleanup ran (session 134 is
`force_closed`). Also, my earlier claim that branch geofence coordinates were
wrong was **my mistake** — FACTORY KAMSHET's coordinates are correct and the
28 km reading was accurate. Apologies for that one.

---

## 1. 🔴 `started_at` is being overwritten

### Evidence

`GET /attendance/today`, employee 1822, 1 Sep — **punches are correct**:

```json
"punches":[
  {"session_id":142,"type":"in", "punched_at":"2026-09-01T12:51:24+05:30"},
  {"session_id":142,"type":"out","punched_at":"2026-09-01T18:08:01+05:30"}
],
"total_seconds":1218
```

`GET /attendance/history?date=2026-09-01`, **same session** — the session row
disagrees with its own punches:

```
session 142  status closed
  started_at        2026-09-01T18:08:01+05:30    ← this is the PUNCH-OUT time
  ended_at          2026-09-01T18:08:01+05:30
  duration_seconds  1218
```

### The arithmetic

| | |
|---|---|
| Punch-in | 12:51:24 |
| Punch-out | 18:08:01 |
| **Actual worked time** | **5 h 16 m 37 s = 18,997 s** |
| **Recorded `duration_seconds`** | **1,218 s = 20 m 18 s** |

The employee is credited with **20 minutes for a five-hour shift**, and that
number is what `/attendance/today` and `/attendance/history` return as
`total_seconds`. Anything downstream — hours reports, payroll — inherits it.

### Where to look

`punchOut()` as I reviewed it only updates `punch_out_id`, `ended_at`,
`duration_seconds` and `status` — it does not touch `started_at`. So this is
either newer code or a different writer. Worth checking whether
`attendance:sync` / `attendance:process` (the biometric jobs, which run every
minute and every 15 minutes) write to `attendance_sessions`.

**One clue that may pin it down:** 1,218 s before 18:08:01 is **17:47:43**,
which is within one second of that session's **last location ping**
(17:47:42). So `started_at` may be getting set from the most recent ping
rather than from the punch-in.

### Please audit

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

Please send us the row count — it tells us how far back the under-recording
goes and whether past payroll runs were affected.

### Repair

The punch rows survived, so the sessions can be rebuilt from them. **Back up
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

Fix the write first — otherwise the next punch-out re-corrupts the row.

---

## 2. 🔴 Force-close job writes `ended_at` before `started_at`

The job shipped and does close stale sessions — but the row it leaves behind
is invalid:

```
session 134  status force_closed
  started_at        2026-09-01T00:15:03+05:30
  ended_at          2026-08-31T17:54:33+05:30    ← BEFORE started_at
  duration_seconds  0
```

Session 134 was really opened on **31 Aug** — its first ping is 16:27 that
day. `started_at` now reads **1 Sep 00:15:03**, which is the scheduled run
time of the force-close command itself.

So the job appears to be doing something like:

```php
$session->update([
    'status'     => 'force_closed',
    'started_at' => now(),        // ← should not be touched
    'ended_at'   => $lastActivity,
]);
```

`duration_seconds = 0` is correct and intended. **`started_at` must be left
alone** — it is the employee's real punch-in time and the only record of when
the shift began:

```php
$session->update([
    'status'           => 'force_closed',
    'ended_at'         => $session->ended_at ?? $session->started_at,
    'duration_seconds' => 0,
]);
```

Then repair the rows it has already touched:

```sql
UPDATE attendance_sessions s
JOIN attendance_punches p ON p.id = s.punch_in_id
SET s.started_at = p.punched_at
WHERE s.status = 'force_closed'
  AND s.punch_in_id IS NOT NULL
  AND s.started_at > p.punched_at;
```

**This runs again tonight at 00:15.** Every night it stays in, more sessions
get their start time replaced.

---

## 3. A guard worth adding permanently

Both bugs would have been caught immediately by one invariant:

```sql
SELECT id, employee_id, date, started_at, ended_at, status
FROM attendance_sessions
WHERE ended_at IS NOT NULL AND ended_at < started_at;
```

**That must never return a row.** Worth adding as a daily check with an alert,
or as a DB constraint if your MySQL version supports it:

```sql
ALTER TABLE attendance_sessions
  ADD CONSTRAINT chk_session_times
  CHECK (ended_at IS NULL OR ended_at >= started_at);
```

(MySQL 8.0.16+ enforces `CHECK`; earlier versions parse and ignore it, so use
the scheduled query instead.)

A second one worth having, since it is what makes this a payroll bug rather
than a cosmetic one:

```sql
-- duration should match the timestamps it was derived from
SELECT id, started_at, ended_at, duration_seconds,
       TIMESTAMPDIFF(SECOND, started_at, ended_at) AS expected
FROM attendance_sessions
WHERE status = 'closed'
  AND ABS(duration_seconds - TIMESTAMPDIFF(SECOND, started_at, ended_at)) > 60;
```

---

## 4. Still open from the previous list

Lower priority than the two above, but unresolved:

- **§1 — punch-in date filter.** The actual lockout fix. We cannot verify it
  from outside without creating a stale session; please confirm it shipped.
  Without it, an employee who forgets to punch out is still locked out until
  the nightly job runs.
- **§3 — `today()` returning an active session from any date.** Probably fixed;
  there is no stale session left to expose it either way.
- **§9 — `live()` N+1** (one ping query per active session).
- **§10 — `ALREADY_PUNCHED_TODAY` ignores `force_closed`.** Confirm this is
  intended: it is *required* for the punch-in fix to work, but it also lets a
  session force-closed *today* start a second cycle.
- **§11 — the guide's deleted Known Issues section.** Two entries in it were
  never fixed (`client_captured_at` temporal bounds, the `live()` N+1) and now
  have no record anywhere.

---

## 4b. 🟢 Small ask — return `battery_pct` (you already store it)

We want to show the device's battery level on the map and timeline, next to
each point — the way Snapchat's map does. It explains gaps in a trail: a flat
phone and a switched-off phone look identical otherwise.

**You already have the data.** We send it on every ping and on every punch;
you store both. It is simply never returned.

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

Worth adding to `live()`'s `last_ping` too — the admin dashboard gets it free.

Note your own guide §3.7 already documents `battery_pct` in the history ping
example, so this is the response catching up with the contract.

### Punches — one line, from `device_info`

`attendance_punches` has no battery column, but since 1 Sep we send it inside
the `device_info` JSON on punch-in and punch-out, alongside model, OS, app
version and `device_id`. The column is cast to `array`, so:

```php
// today() and history() punch maps
'battery_pct' => data_get($p->device_info, 'battery_pct'),   // ← add
```

That way the punch-in marker carries a reading like every other point, rather
than being the one gap on the trail.

If you would rather return the whole `device_info` object instead, that also
works — we read the nested value either way. Returning just `battery_pct`
keeps the payload smaller and avoids exposing device metadata to the employee's
own client.

**Our side is already done.** Both shapes are parsed and the badge renders the
moment the field appears — no app release needed.

---

## 5. What we verified working

So this reads fairly — checked live, not taken on trust:

| Item | Status |
|---|---|
| `live()` branch payload | ✅ returns `{id, branch_name}` only — no `l1`…`ec_l6`, no `address` |
| `captured_at` timezone | ✅ pings store IST, no 5h30m drift |
| Stale-session cleanup | ✅ session 134 force-closed |
| `/me/geofence` | ✅ flat shape, correct branch, `geofence_attendance: "Yes"` |
| Branch coordinates | ✅ correct — **my earlier report was wrong, retracted** |
| Punch payloads | ✅ `session_id`, coordinates, `accuracy_m`, `address`, `selfie_url` all present |

And for context, the client side is behaving: session 142's pings landed at
`13:39 · 14:09 · 14:47 · 15:17 · 15:47 · 16:17 · 16:47 · 17:17 · 17:47` —
30-minute intervals within ±5 s across four hours, with the app closed. The
ping pipeline is healthy; the problem is confined to the session row.
