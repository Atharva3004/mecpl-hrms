# Backend Action List — Geofence & Location Ping

**Date:** 2026-08-29
**From:** Mobile (Flutter) team
**To:** Backend team
**Re:** `docs/geofence-module-guide.md` v1.0 — gaps found while wiring the app to it

---

## 0. Read this first

Your guide is good and the module is built. We diffed it against the app's
parsing code and found **8 items that need backend work**, plus a short list
of confirmations.

**Everything on the app side is our own fix and is not listed here** — the
`/me/geofence` `branch{}` envelope, the `code` vs `error_code` key, the
background-location permission. We are handling those. This document is
only what we need **from you**.

### Priority summary

| ID | Item | Priority | Effort |
|---|---|---|---|
| **B1** | Add GPS coords to `punches[]` on `/today` and `/history` | 🔴 P0 | ~15 min |
| **B2** | Add `session_id` to `punches[]` on `/today` and `/history` | 🔴 P0 | ~10 min |
| **B3** | Fix `hasGeofence()` NULL→0 cast (your §6.2) | 🔴 P0 | ~10 min |
| **B4** | Fix IST vs UTC date boundary (your §6.3) | 🔴 P0 | ~1 hr |
| **B5** | Serialise numbers as JSON numbers, not strings | 🟠 P1 | ~20 min |
| **B6** | Add `total_seconds` to `/attendance/history` | 🟠 P1 | ~5 min |
| **B7** | Branch geofence data audit | 🟠 P1 | ~15 min |
| **B8** | Fix punch-in race condition (your §6.1) | 🟠 P1 | ~30 min |
| **C1–C5** | Confirmations, no code change expected | 🟡 | ~15 min |
| **B9–B12** | Your own §6 items — security & hygiene | 🟡 P2 | — |

**B1 + B2 are the two that make "pings and punches don't show" go away.**
If you only have an hour, do B1, B2, B3.

> All Laravel snippets below are illustrative — we don't have your source, so
> adapt to your actual controller/resource structure.

---

## 1. 🔴 B1 — `punches[]` must include GPS coordinates

**Endpoints:** `GET /api/attendance/today`, `GET /api/attendance/history`
**Your guide:** §3.6 and §3.7

### Current response

```json
"punches": [
    {
        "id": 283,
        "type": "in",
        "punched_at": "2026-08-29T09:30:15.000000Z",
        "selfie_url": "https://.../123_1724920215.jpg",
        "inside_geofence": true,
        "distance_m": 45
    }
]
```

### The problem

There is no `latitude` or `longitude`. The app plots every punch as a point
on a map and in the timeline list, and its parser hard-requires coordinates:

```dart
final lat = (m['latitude'] as num?)?.toDouble();
final lng = (m['longitude'] as num?)?.toDouble();
if (lat == null || lng == null) return null;   // row is discarded
```

So **every punch row is silently dropped** and the screen shows
"Waiting for today's punch-in…" even immediately after a successful punch-in.

The data already exists — your §2.4 lists `latitude`, `longitude`,
`accuracy_m`, `address` on `attendance_punches`. And
`/attendance/session/{id}/timeline` (§3.8) **already returns them** on
`punch_in` / `punch_out`. It is only `/today` and `/history` that omit them.

### Required response

```json
"punches": [
    {
        "id": 283,
        "session_id": 142,
        "type": "in",
        "punched_at": "2026-08-29T09:30:15.000000Z",
        "latitude": 19.0760,
        "longitude": 72.8777,
        "accuracy_m": 15.5,
        "address": "Andheri East, Mumbai",
        "selfie_url": "https://.../123_1724920215.jpg",
        "inside_geofence": true,
        "distance_m": 45
    }
]
```

| Field | Type | Required | Note |
|---|---|---|---|
| `latitude` | number | **yes** | row is dropped without it |
| `longitude` | number | **yes** | row is dropped without it |
| `accuracy_m` | number \| null | no | defaults to 0 in the app |
| `address` | string \| null | no | app reverse-geocodes client-side if empty — slow and rate-limited, so please send it |
| `session_id` | integer | **yes** | see B2 |

### Illustrative fix

```php
// AttendanceViewController@today  (and the same shape inside history())
'punches' => $punches->map(fn ($p) => [
    'id'              => $p->id,
    'session_id'      => $p->session_id,      // B2
    'type'            => $p->type,
    'punched_at'      => $p->punched_at?->toIso8601String(),
    'latitude'        => (float) $p->latitude,   // B1  (cast — see B5)
    'longitude'       => (float) $p->longitude,  // B1
    'accuracy_m'      => $p->accuracy_m !== null ? (float) $p->accuracy_m : null,
    'address'         => $p->address,
    'selfie_url'      => $p->selfie_path ? Storage::disk('public')->url($p->selfie_path) : null,
    'inside_geofence' => (bool) $p->inside_geofence,
    'distance_m'      => $p->distance_m,
]),
```

Apply the identical shape to `sessions[].punches[]` in `/attendance/history`
(§3.7) — it has the same omission.

### Acceptance

```bash
curl -s -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" \
  "$BASE/api/attendance/today" | jq '.data.punches[0] | {session_id, latitude, longitude, address}'
```
Must return four non-null values after a punch-in.

---

## 2. 🔴 B2 — `punches[]` must include `session_id`

**Endpoints:** `GET /api/attendance/today`, `GET /api/attendance/history`

### Why this one specifically breaks the ping timeline

To draw the 30-minute tracking trail, the app calls
`GET /attendance/session/{id}/timeline`. To do that it needs a session id.
It resolves one in this order:

1. the in-memory active session (only exists while the app remembers the punch), then
2. `punches[].session_id` from `/attendance/today`

Step 2 does not exist in your response, so **there is no recovery path**
after: an app kill, a reinstall, a device switch, or — most commonly — after
**punch-out**, when `active_session` becomes `null`.

The app then hits this and gives up **silently, with no error shown**:

```dart
final sessionId = att.todaySessionId;
if (sessionId == null) { return; }    // <- pings never load, no message
```

That is the whole of "the pings are not showing."

Your §4.2 Step 2 says *"If `active_session != null` … use the existing
session_id"* — correct while a session is open. But the moment it closes, the
day's pings become unreachable, because the punches don't carry the id either.

### Required

Add `session_id` (integer) to **every** object in:
- `/attendance/today` → `data.punches[]`
- `/attendance/history` → `data.sessions[].punches[]`

on both the `in` and the `out` punch. The column already exists (§2.4).

### Acceptance

```bash
curl -s "${H[@]}" "$BASE/api/attendance/today" | jq '.data.punches[].session_id'
```
Must return an integer for every punch, including after punch-out.

---

## 3. 🔴 B3 — `hasGeofence()` NULL→0 cast

**This is your own §6.2 — raising it to P0 because it corrupts live data.**

`geofence_radius_m` is cast to `integer` on the model, so Eloquent turns
`NULL` into `0`. `hasGeofence()` then returns `true` for a branch that has no
geofence configured, and the distance check runs against a **0-metre radius**.

Result: **every punch at an unconfigured branch is written to the DB with
`inside_geofence = false`.**

That directly contradicts your own Business Rules table:

> **Branch must have coordinates** — If branch has no lat/lng/radius
> configured, all punches are marked `inside_geofence: true` by default.

The table describes the intent; the code does the opposite.

### Impact on the app

Every employee at an unconfigured branch sees an "outside geofence" warning
badge on every punch, and admins see false out-of-fence flags on the review
dashboard. Until this is fixed we cannot trust `inside_geofence` at all.

### Fix

```php
// BranchModel.php
public function hasGeofence(): bool
{
    return $this->latitude !== null
        && $this->longitude !== null
        && (int) $this->geofence_radius_m > 0;   // 0 and NULL both mean "no fence"
}
```

Your own suggestion of `getRawOriginal()` works too. The `> 0` form is
simpler and also correctly handles a radius explicitly set to 0.

### Please also confirm

Whether historical rows need backfilling. If punches were recorded with a
false `inside_geofence = 0` at unconfigured branches, that is bad data on the
admin dashboard:

```sql
SELECT COUNT(*)
FROM attendance_punches p
JOIN branches b ON b.id = p.branch_id
WHERE p.inside_geofence = 0
  AND (b.latitude IS NULL OR b.longitude IS NULL
       OR b.geofence_radius_m IS NULL OR b.geofence_radius_m = 0);
```

If that returns a meaningful number, those rows should be corrected to
`inside_geofence = 1, distance_m = NULL`.

---

## 4. 🔴 B4 — IST vs UTC date boundary

**Your own §6.3 — also P0, because it lands squarely in the punch-in window.**

- "Already punched today" uses `Carbon::now('Asia/Kolkata')`
- Session `date` is stored with `now()->toDateString()` (server tz, likely UTC)
- `/attendance/today` also filters in server timezone

Between **00:00 and 05:30 UTC — i.e. 05:30 to 11:00 IST** — the two disagree
by a day. That is exactly when people punch in.

### Two user-visible failures

1. `/attendance/today` returns **yesterday's** session and punches during the
   IST morning, so the app shows stale or empty data right after punch-in.
2. An employee who punched yesterday (IST) can be wrongly blocked with
   `ALREADY_PUNCHED_TODAY`, or wrongly allowed a second cycle.

This will survive the B1/B2 fixes — the app will render whatever day you
hand it.

### Fix

Pick **IST as the single day-boundary authority** and apply it everywhere:

```php
// config/app.php  — or scope it to this module if a global change is risky
'timezone' => 'Asia/Kolkata',
```

If a global timezone change is too invasive, normalise at every read/write
instead:

```php
// writing
$sessionDate = Carbon::now('Asia/Kolkata')->toDateString();

// reading — today()
$today = Carbon::now('Asia/Kolkata')->toDateString();
$sessions = AttendanceSession::where('employee_id', $empId)
    ->where('date', $today)
    ->get();

// history?date=YYYY-MM-DD — treat the param as an IST calendar date
$start = Carbon::parse($request->date, 'Asia/Kolkata')->startOfDay();
$end   = Carbon::parse($request->date, 'Asia/Kolkata')->endOfDay();
```

The critical rule: **`date`, the `ALREADY_PUNCHED_TODAY` check, `/today`, and
`/history?date=` must all use the same timezone.** Mixing them is what
produces the 5.5-hour window.

### Please confirm

Which timezone the `date` column holds **today**, so we know whether existing
rows need correcting.

### Our side

We currently send `client_captured_at` as `.toUtc()` ISO-8601 (e.g.
`2026-08-29T04:00:15.000Z`) — valid, but it hands you a UTC date. **Tell us
which you want** and we will match:
- keep UTC with `Z`, and you convert to IST server-side, or
- send IST with an explicit `+05:30` offset

Either is fine; we just need one answer.

### Acceptance

At **07:00 IST**, punch in, then call `/attendance/today`. It must return
today's session — not yesterday's, and not empty.

---

## 5. 🟠 B5 — Serialise numbers as JSON numbers, not strings

Laravel serialises `decimal` columns as **strings** by default:

```json
"latitude": "19.0760000"      ← string
"latitude": 19.0760           ← what we need
```

Your guide's examples all show real numbers, so this may already be handled —
but the DB columns are `decimal(10,7)` and `decimal(8,2)`, which is exactly
the case where it bites.

We are making our parsers tolerant of both (that's our fix, not yours), but
please send real numbers so nobody has to guess.

### Fields affected

`latitude`, `longitude`, `accuracy_m`, `distance_m`, `geofence_radius_m`,
`branch.id`, `session_id`, `ping_id`, `duration_seconds`, `ping_count`,
`total_seconds`, `battery_pct`

### Fix

```php
// AttendancePunch.php / AttendanceLocationPing.php / BranchModel.php
protected $casts = [
    'latitude'          => 'float',
    'longitude'         => 'float',
    'accuracy_m'        => 'float',
    'distance_m'        => 'integer',
    'inside_geofence'   => 'boolean',
    'geofence_radius_m' => 'integer',   // see B3 — keep the NULL guard in hasGeofence()
];
```

⚠️ Note the interaction with B3: casting `geofence_radius_m` to `integer` is
what caused the NULL→0 bug. Keep the cast **and** fix `hasGeofence()` with the
`> 0` check — do not rely on the cast alone.

### Acceptance

```bash
curl -s "${H[@]}" "$BASE/api/attendance/today" | jq '.data.punches[0].latitude | type'
```
Must print `"number"`, not `"string"`.

---

## 6. 🟠 B6 — `/attendance/history` must return `total_seconds`

Your §3.7 response has `data.sessions[]` but no day total. The app reads:

```dart
_totalSeconds = (body['total_seconds'] as num?)?.toInt();
```

so the day-total display is blank on every past date.

### Required

```json
{
  "status": true,
  "data": {
    "sessions": [ ... ],
    "total_seconds": 32400
  }
}
```

Sum of `duration_seconds` across the day's **closed** sessions — same
semantics as `/attendance/today`.

---

## 7. 🟠 B7 — Branch geofence data audit

Please run and send us the output:

```sql
SELECT
  COUNT(*) AS total_branches,
  SUM(latitude IS NOT NULL AND longitude IS NOT NULL
      AND geofence_radius_m IS NOT NULL AND geofence_radius_m > 0) AS fully_configured,
  SUM(latitude IS NULL OR longitude IS NULL) AS missing_coords,
  SUM(geofence_radius_m IS NULL OR geofence_radius_m = 0) AS missing_radius
FROM branches
WHERE status = 'active';          -- adjust to your actual active-branch flag
```

And the per-branch detail:

```sql
SELECT id, branch_name, latitude, longitude, geofence_radius_m
FROM branches
ORDER BY branch_name;
```

**Why we need it:** a branch missing any of the three has no enforceable
fence. Combined with B3, those branches are currently generating false
"outside" flags. We also can't tell whether a grey/neutral ribbon in the app
means "not configured" or "endpoint problem" until we know which branches are
actually set up.

If branches are unconfigured, someone needs to enter the coordinates — that's
an admin/data task, not a code task, so it's worth surfacing early.

---

## 8. 🟠 B8 — Punch-in race condition

**Your own §6.1.** We are implementing the client-side workaround (disabling
the button on first tap), but that is not a fix — a flaky network retry, a
background retry, or two devices can still double-submit.

### Fix

```php
DB::transaction(function () use ($employeeId, $request) {
    $open = AttendanceSession::where('employee_id', $employeeId)
        ->where('status', 'active')
        ->lockForUpdate()          // <- inside the transaction
        ->first();

    if ($open) {
        throw new SessionAlreadyOpenException($open->id);
    }

    // ... create punch + session ...
});
```

Plus a DB-level backstop so it cannot happen even if the code path changes:

```sql
-- Only one active session per employee.
-- MySQL 8.0.13+ supports functional indexes; otherwise use a generated column.
ALTER TABLE attendance_sessions
  ADD COLUMN active_guard TINYINT
    GENERATED ALWAYS AS (IF(status = 'active', 1, NULL)) STORED,
  ADD UNIQUE KEY uniq_active_session (employee_id, active_guard);
```

**Before adding the constraint,** check for existing duplicates — the race
may already have created some:

```sql
SELECT employee_id, COUNT(*) AS open_sessions
FROM attendance_sessions
WHERE status = 'active'
GROUP BY employee_id
HAVING COUNT(*) > 1;
```

Those need to be force-closed first, or the `ALTER` will fail.

---

## 9. 🟡 Confirmations — no code change expected

Quick answers, so we stop guessing:

| ID | Question | Why we're asking |
|---|---|---|
| **C1** | Do `/location-ping` and `/location-ping/batch` still accept `Content-Type: application/json` when **no** selfie is attached? | Your §3.4/§3.5 document multipart only. The app currently posts JSON. Laravel normally parses a JSON body fine, but we need it confirmed before we ship — and we'd rather not rewrite both calls if JSON stays supported. |
| **C2** | Is an extra `"is_queued": true` key inside each object of the batch `pings` array **ignored**, or does it 422? | The app currently sends it. Your schema doesn't list it and the backend sets that column itself, so we'll drop it — but confirm it isn't currently rejecting our whole batch. |
| **C3** | Does the **session owner** (not just an admin) get 200 from `/attendance/session/{id}/timeline`? | Your §3.8 says "Regular employee: can only view own sessions", so we expect yes. A 403 here would look identical to "no pings exist". |
| **C4** | Is `battery_pct: null` accepted? | We send `null` on every ping today (not yet wired to the battery API). If it's `required|integer`, every ping is 422ing. Your §3.4 says optional — just confirming it matches the implementation. |
| **C5** | Are `/me/geofence`'s shape and the `code` error key **frozen**? | We're adapting our parser to `branch{}` / `geofence_radius_m` / `code`. If any of those are still in flux, tell us now — a rename after we ship breaks the app silently. |

### Diagnostic we'd like either way

```sql
SELECT COUNT(*) AS pings_last_24h
FROM attendance_location_pings
WHERE captured_at > NOW() - INTERVAL 1 DAY;
```

This one number tells us where the remaining ping problem lives:
- **0 rows** → pings are not arriving (our background-permission bug, or rejection). We own it.
- **rows exist** → pings are stored, and B2 is what's hiding them.

Plus any 409 / 422 / 429 hits on `/attendance/location-ping` in the logs.

---

## 10. 🟡 P2 — your remaining §6 items

Not blocking us, listed so they aren't lost. Your descriptions and fixes are
already correct; we're just confirming they matter.

| Your § | Item | Note from us |
|---|---|---|
| **6.4** | `'selfie_*'` glob doesn't validate — `selfie_0`, `selfie_1` are unvalidated | **Security.** Any file type or size can be uploaded to a public storage path. Worth fixing before we start sending ping selfies. Laravel needs an explicit loop or `Rule::forEach`, since glob keys aren't supported. |
| **6.5** | Batch selfie filename collision (1-second timestamp resolution) | Blocks ping-selfie support — the 2nd image in a batch overwrites the 1st. Add the ping's array index or a random suffix to the filename. |
| **6.6** | `getEmployeesByBranch()` has no admin check | **Security.** Any authenticated employee can enumerate every employee's code and geofence status. This one is worth doing regardless of our timeline. |
| **6.7** | No temporal bounds on `client_captured_at` | We always send real timestamps, but a `before:+5 minutes` / `after:-7 days` rule would stop a tampered client from backdating attendance. |
| **6.10** | N+1 on `live()` and `getGeofenceMapData()` | Admin dashboard only. A `latest-of-each-group` subquery or eager-loaded `hasOne` on last ping fixes it. |

---

## 11. Acceptance checklist

Copy into the ticket. Everything is verifiable with one employee account.

**P0**
- [ ] `/attendance/today` → `punches[].latitude` and `.longitude` are non-null numbers
- [ ] `/attendance/today` → `punches[].session_id` is an integer on both `in` and `out`
- [ ] `/attendance/today` → `punches[].address` is populated when available
- [ ] `/attendance/history?date=` → `sessions[].punches[]` has the same four fields
- [ ] `hasGeofence()` returns `false` when `geofence_radius_m` is NULL or 0
- [ ] A punch at an unconfigured branch is stored with `inside_geofence = 1`
- [ ] Existing false `inside_geofence = 0` rows audited (query in §3) and corrected if needed
- [ ] At 07:00 IST, `/attendance/today` returns **today's** data, not yesterday's
- [ ] `date`, `ALREADY_PUNCHED_TODAY`, `/today` and `/history` all agree on the IST boundary

**P1**
- [ ] `jq '.data.punches[0].latitude | type'` prints `"number"`
- [ ] `/attendance/history` returns `data.total_seconds`
- [ ] Branch audit output sent to mobile team
- [ ] Punch-in existence check moved inside the transaction with `lockForUpdate()`
- [ ] Duplicate active sessions checked for, then unique constraint added

**Confirmations**
- [ ] C1 — ping endpoints accept JSON without a selfie: **yes / no**
- [ ] C2 — extra `is_queued` key: **ignored / rejected**
- [ ] C3 — session owner gets 200 on their own timeline: **yes / no**
- [ ] C4 — `battery_pct: null` accepted: **yes / no**
- [ ] C5 — `/me/geofence` shape and `code` key frozen: **yes / no**
- [ ] `pings_last_24h` count + any 409/422/429 in the ping logs

---

## 12. What we're fixing on our side

Listed so you know these aren't waiting on you:

- Parse the `branch{}` envelope and `geofence_radius_m` from `/me/geofence`
  (we were reading a flat `branch_id` / `radius_m` shape that doesn't exist —
  it threw and silently discarded the whole geofence)
- Read `code` as well as `error_code` on 409s (we were misreporting
  `ALREADY_PUNCHED_TODAY` as `SESSION_ALREADY_OPEN`)
- Handle the new 403 `GEOFENCE_NOT_ENABLED`
- Request Android "Allow all the time" location — without it our background
  ping can't get a GPS fix, which is very likely why pings aren't reaching you
- Disable the punch button on first tap (your §6.1 workaround)
- Tolerate string-formatted numbers regardless of B5
- Stop sending `is_queued`; start sending a real `battery_pct`

**Thanks for documenting your own known bugs in §6 — that saved us a lot of
guesswork, and four of the items above came straight out of it.**
