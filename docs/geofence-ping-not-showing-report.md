# Geofence & Location-Ping — "Not Showing" Diagnostic Report

**Date:** 2026-08-29
**App:** MECPL Flutter (`mecpl_flutter`)
**Backend:** `https://hrms.mecpl.in/api` (Laravel)
**Audience:** Backend developer (Sections 3, 5, 6, 7) + Mobile team (Section 4)

---

## 0. TL;DR

The geofence circle and the 30-minute tracking pings do not appear on the
**Today's Timing / Location History** screen or the **attendance map**.

All eight API routes **exist and are reachable** — this is *not* a "route not
built" problem. The breakage is in **what the endpoints return** (missing
fields, wrong types, unpopulated branch data) combined with **two app-side
defects** that would block pings even against a perfect backend.

There are **four P0 causes**. Any one of them alone is enough to make the
feature look completely dead:

| # | Cause | Owner | Effect |
|---|-------|-------|--------|
| **P0-1** | `/me/geofence` omits `geofence_attendance` → app treats it as `"No"` | **Backend** | Punch button hidden → no session → **no pings at all, ever** |
| **P0-2** | `branches.latitude / longitude / geofence_radius_m` are NULL in DB | **Backend** | No fence → no circle, no inside/outside ribbon, distance measured against a hard-coded Pune office |
| **P0-3** | `/attendance/today` `punches[]` missing `session_id` (and often `latitude`/`longitude`) | **Backend** | App cannot resolve the session id → timeline call is never made → **ping list stays empty** |
| **P0-4** | App never requests Android "Allow all the time" location permission | **Mobile** | Background Workmanager ping cannot get a GPS fix → **no pings are ever sent** |

Fix P0-1 + P0-3 first (backend, roughly an hour), P0-2 is a data-entry task,
P0-4 is on the mobile side.

---

## 1. What "not showing" means, precisely

Three separate symptoms are being reported as one:

| Symptom | Screen | Where it comes from |
|---|---|---|
| **A. Geofence circle wrong / at the wrong office** | Attendance Map | `attendance_map_screen.dart` |
| **B. Every punch row shows a neutral ribbon and a nonsense distance** | Today's Timing rows | `GeofenceRepository.check()` |
| **C. Tracking (ping) rows never appear when the toggle is ON** | Today's Timing, toggle ON | `GET /attendance/session/{id}/timeline` |

A and B are geofence problems. C is the ping problem. They have different
root causes; both are covered below.

---

## 2. Verified evidence (what was actually tested)

### 2.1 Route existence probe — all routes are live

Unauthenticated `curl` against production. An unregistered route on this
server returns **404**; a registered-but-protected route returns **401**.
Control probes confirmed the 404 behaviour.

| Method | Route | Status | Verdict |
|---|---|---|---|
| GET | `/api/me/geofence` | 401 | registered |
| GET | `/api/attendance/today` | 401 | registered |
| GET | `/api/attendance/live` | 401 | registered |
| GET | `/api/attendance/session/1/timeline` | 401 | registered |
| GET | `/api/attendance/history` | 401 | registered |
| POST | `/api/attendance/punch-in` | 401 | registered |
| POST | `/api/attendance/punch-out` | 401 | registered |
| POST | `/api/attendance/location-ping` | 401 | registered |
| POST | `/api/attendance/location-ping/batch` | 401 | registered |
| GET | `/api/definitely-not-a-route-xyz` | **404** | control |
| GET | `/api/attendance/bogus-xyz` | **404** | control |

**Conclusion: routing and middleware are fine. The problem is payload
content, DB data, and two client defects.**

### 2.2 What could NOT be verified

There was no valid Sanctum bearer token available, so the **response bodies**
could not be inspected. Every item in Section 3 is a cause derived from
reading the client's parsing code — the backend dev can confirm or clear each
one in about 10 minutes with the curl commands in Section 6.

---

## 3. Backend issues (ranked)

### P0-1 — `/me/geofence` must return `geofence_attendance`

**This is the single most likely reason nothing works.**

Client code — `lib/repositories/geofence_repository.dart`:

```dart
geofenceAttendance: (json['geofence_attendance'] ?? 'No').toString(),
...
bool get isAttendanceEnabled => geofenceAttendance.toLowerCase() == 'yes';
```

And `lib/providers/attendance_provider.dart`:

```dart
final next = g?.isAttendanceEnabled ?? true;   // no cache  -> optimistic ON
_isGeofenceAttendanceEnabled = next;           // cached + missing field -> OFF
```

**The failure mode:** if `/me/geofence` returns **200 with the field absent**,
the app defaults it to `"No"`, sets `_isGeofenceAttendanceEnabled = false`,
and **hides the punch-in button entirely**. No punch-in → no session →
no session_id → no pings → nothing to draw on the timeline.

Note the asymmetry: a *failed* call leaves the feature ON, but a *successful
call with a missing field* turns it OFF. So this fails silently and looks
like "the whole feature is dead".

**Required response — exact shape:**

```json
{
  "status": true,
  "data": {
    "branch_id": 12,
    "branch_name": "Pune HQ",
    "latitude": 18.5743404,
    "longitude": 73.7736299,
    "radius_m": 50,
    "geofence_attendance": "Yes"
  }
}
```

- `geofence_attendance` — **required**, exactly the string `"Yes"` or `"No"`.
  Not a boolean, not `1`/`0`, not `null`. Comparison is case-insensitive on
  the client, but please send `"Yes"`.
- The app accepts the payload either at the top level or nested under `data`.

---

### P0-2 — Branch geofence columns are not populated

`GeofenceRepository.isEnforced` requires **all three** of `latitude`,
`longitude`, `radius_m` to be non-null, with `radius_m > 0`:

```dart
bool get isEnforced =>
    latitude != null && longitude != null && radiusM != null && radiusM! > 0;
```

If any is NULL, the app treats the branch as "no fence":

- inside/outside ribbon → **neutral (grey), never green/red**
- distance → measured against the **legacy hard-coded Pune HQ**
  (`18.5743404, 73.7736299`) in `office_config.dart`, which is wrong for
  every non-Pune employee — this is why distances look like nonsense
- the map draws a 50 m circle over Pune HQ regardless of the real branch

**Action:** populate `branches.latitude`, `branches.longitude`,
`branches.geofence_radius_m` for **every active branch**. This was already
flagged as a P0 blocker in `docs/backend-dev-tasks-geofence-geotagging.md` §7
and appears to still be outstanding.

Please also confirm the intended policy for a branch with `radius_m: null` —
the client currently reads it as "no fence, allow punching from anywhere".

---

### P0-3 — `/attendance/today` → `punches[]` must carry `session_id`, `latitude`, `longitude`

Two separate gaps here, both already documented as "v2 changes" and both
still biting.

**(a) Missing `session_id` → the ping timeline is never fetched.**

`lib/screens/tracking/location_history_screen.dart`:

```dart
final sessionId = att.todaySessionId;
if (sessionId == null) { _refreshTimer?.cancel(); return; }  // <- silent dead end
provider.loadFromTodaysSession(token: token, sessionId: sessionId, userId: userId);
```

`todaySessionId` resolves from the in-memory active session, and otherwise
falls back to scanning `punches[].session_id` from `/attendance/today`. On a
fresh install, after the app is killed, or after punch-out, the in-memory
session is gone — **`session_id` on each punch object is the only way to
recover it.** Without it the timeline call is never issued and the user sees
an empty tracking list with no error message.

**(b) Missing `latitude` / `longitude` on punches.**

`_pointFromMap` drops any punch without coordinates:

```dart
final lat = (m['latitude'] as num?)?.toDouble();
final lng = (m['longitude'] as num?)?.toDouble();
if (lat == null || lng == null || tsRaw == null) return null;   // row discarded
```

There is already a comment in the codebase noting the backend omits these,
which left the screen stuck on "Waiting for today's punch-in…". A local
fallback was added to paper over it, but that only covers punches made on
*this device, today* — not history, not a reinstall, not an admin view.

**Required response:**

```json
{
  "status": true,
  "data": {
    "active_session": {
      "session_id": 3401,
      "started_at": "2026-08-29T09:12:03+05:30",
      "ping_count": 14,
      "last_ping": { "latitude": 18.5743, "longitude": 73.7736, "captured_at": "2026-08-29T14:12:03+05:30" }
    },
    "punches": [
      {
        "session_id": 3401,
        "type": "in",
        "punched_at": "2026-08-29T09:12:03+05:30",
        "latitude": 18.5743404,
        "longitude": 73.7736299,
        "accuracy_m": 8.2,
        "address": "Baner, Pune, Maharashtra",
        "selfie_url": "https://hrms.mecpl.in/storage/attendance/2026/08/2914_1756000000.jpg",
        "inside_geofence": true,
        "distance_m": 15
      }
    ],
    "total_seconds": 32405
  }
}
```

Every field above must be present on **every** punch object, including
`session_id` on both the `in` and the `out` punch.

---

### P1 — Numeric columns returned as JSON strings

Laravel serialises `DECIMAL` columns as strings by default —
`"latitude": "18.5743404"` instead of `18.5743404`. The client is
inconsistent about this and **hard-crashes** in the timeline path:

| Location | Parse style | Behaviour on a string value |
|---|---|---|
| `geofence_repository.dart` lat/lng/radius | tolerant (`double.tryParse`) | survives |
| `geofence_repository.dart` `branch_id` | `(json['branch_id'] as num).toInt()` | **throws** → geofence silently never caches |
| `location_history_provider.dart` `_pointFromMap` | `(m['latitude'] as num?)` | **throws** → whole timeline load fails |
| `attendance_provider.dart` punches | tolerant (`_asDouble`) | survives |

**Two asks:**

1. **Backend:** return real JSON numbers for `latitude`, `longitude`,
   `radius_m`, `distance_m`, `accuracy_m`, `branch_id`, `session_id`,
   `ping_id`. In Laravel: `protected $casts = ['latitude' => 'float', ...]`.
2. **Mobile:** make every parse tolerant of both forms. Tracked as A3 in
   Section 4 — the app should not depend on the backend for this.

---

### P1 — `/attendance/session/{id}/timeline` → `pings[]` shape

This is the endpoint that draws the tracking rows. The app reads exactly:

```dart
body['punch_in']    // object
body['pings']       // array   <- the tracking rows
body['punch_out']   // object
```

and per ping, exactly these keys:

| Key | Required | Notes |
|---|---|---|
| `latitude` | **yes** | ping is silently dropped if missing |
| `longitude` | **yes** | ping is silently dropped if missing |
| `captured_at` | **yes** | ISO-8601 **with timezone offset** — see P2 below |
| `accuracy_m` | no | defaults to 0 |
| `address` | no | app reverse-geocodes client-side if empty (slow) |
| `inside_geofence` | no | informational |
| `selfie_url` | no | currently always absent — see P2 below |

**Please confirm:**

1. Is `pings[]` actually populated for a live session, or is it coming back
   as `[]`? If `[]`, are rows landing in `attendance_location_pings` at all?
   (See the next item.)
2. Are the keys named exactly `latitude` / `longitude` / `captured_at`?
   `lat`, `lng`, or `created_at` would render nothing, with no error shown.
3. Does the session **owner** (not just an admin) get 200 here? A 403 on the
   employee's own session produces exactly this empty-list symptom.

---

### P1 — Are pings being rejected server-side?

If pings are being POSTed but rejected, the app currently swallows it — the
ping goes into a local retry queue and the user just sees nothing.

Please check the server logs / DB for:

1. **`SESSION_NOT_ACTIVE` / 409 on `/attendance/location-ping`.** If a
   nightly job force-closes sessions (e.g. at midnight IST) while the phone
   still holds that `session_id`, **every subsequent ping is rejected** and
   silently dropped. That produces exactly "punches show, pings never do".
2. **429 rate limiting.** Ping limit is documented at 30/min. A batch flush
   of a day's backlog could trip it.
3. **422 validation.** The app currently sends `"battery_pct": null` on every
   ping (it is never populated — see A4). If `battery_pct` is validated as
   `required|integer`, **every single ping 422s**. Please make it `nullable`.
4. **`is_queued`.** The app sends `"is_queued": true` inside each object in
   the batch payload. Confirm the backend ignores or accepts it rather than
   failing validation on an unexpected key.

**Ask:** please run and report

```sql
SELECT COUNT(*) FROM attendance_location_pings
WHERE captured_at > NOW() - INTERVAL 1 DAY;
```

That one number splits the problem cleanly:

- **0 rows** → pings never arrive (app-side P0-4, or server-side rejection)
- **rows exist but the timeline is empty** → read-path bug (timeline shape)

---

### P2 — Timestamps without a timezone offset

The client has a workaround in `_parseTimestamp` because pings arrive as
naive strings like `"2026-05-29T07:27:00"` while punches arrive with a `Z`
or `+05:30`. Worse, the app currently **throws the real ping timestamps away**
and fabricates them as `punch_in + n × 30 min`
(`_alignTrackingTimestampsToPunchIn`) because backend ping times were not
trustworthy.

That means **the timeline is currently showing invented times, not real
ones.** The goal is to delete that workaround.

**Ask:** return every timestamp as ISO-8601 **with an explicit offset**, e.g.
`2026-08-29T14:27:00+05:30`, consistently across `punched_at`, `captured_at`,
`started_at`, `ended_at`, and `server_time`. Once that is confirmed, the
client-side re-stamping is removed and displayed times become real.

---

### P2 — Ping images (already raised, still open)

Covered in full in `docs/ping-and-punch-images-backend-requirements.md`.
Status: ping endpoints are JSON-only, no image field, and `pings[]` carries
no `selfie_url`. Result: every tracking row falls back to borrowing the
punch-in selfie (a deliberate workaround) or a map-pin icon.

Still awaiting answers to the 7 open questions in §8 of that document.
Not a blocker for "pings not showing" — listed here so it is not lost.

---

### P2 — `selfie_url` must be an absolute URL

The app renders `selfie_url` directly as a network image. A relative path
like `/storage/attendance/...` renders a broken thumbnail. Confirm
`php artisan storage:link` is in place and the API returns the full
`https://hrms.mecpl.in/...` URL.

---

### P2 — `/attendance/history?date=` must include `sessions[].pings[]`

Past-date browsing with the toggle ON reads:

```
data.sessions[].punches[]   -> In / Out rows
data.sessions[].pings[]     -> Tracking rows
data.total_seconds
```

Same key requirements as the timeline endpoint. Confirm `pings[]` is present
per session (not only at the top level, and not only for today).

---

## 4. App-side issues (mobile team — not for the backend dev)

Listed so the backend dev is not chasing problems that are not theirs.

### A1 (P0) — Background location permission is never escalated to "Always"

`lib/services/location_permission_service.dart` calls
`Geolocator.requestPermission()` and accepts `whileInUse`:

```dart
LocationPermission permission = await Geolocator.requestPermission();
...
// Permission granted! (whileInUse or always)
return true;
```

On Android 10+ (API 29+), that grants **foreground-only** location.
`ACCESS_BACKGROUND_LOCATION` is declared in the manifest but **never
requested at runtime** — it needs a second, separate prompt that sends the
user to system Settings ("Allow all the time").

Consequence: the Workmanager ping isolate calls
`Geolocator.getCurrentPosition()` while the app is backgrounded, is denied or
times out, hits the `catch` in `background_ping_worker.dart`, returns
`false`, and **sends nothing**. Silently. Every time.

**This alone is sufficient to explain "pings never show", independent of
anything the backend does.** Fix: add a second permission step requesting
`LocationPermission.always` with the required rationale UI.

### A2 — Attendance map still hard-codes the office

`attendance_map_screen.dart` draws both the marker and the geofence circle
from the deprecated `OfficeConfig` (Pune HQ, 50 m) instead of
`GeofenceRepository`. Every employee sees Pune's circle regardless of branch.
Migration was flagged as pending in `docs/geofence-geotagging-status.md` and
is still outstanding.

### A3 — Strict type casts crash on string numerics

See P1 above. `_pointFromMap` and `Geofence.fromJson`'s `branch_id` should
use tolerant parsing (`num.tryParse(v.toString())`), the way
`attendance_provider` already does. The app should not be one Laravel cast
away from a blank screen.

### A4 — `battery_pct` is never populated

The field exists in the model, the queue, and the API signature, but nothing
ever assigns it — every ping sends `"battery_pct": null`. Either wire up a
battery plugin or drop the field from the payload. (See also P1 item 3 — if
the backend validates it as required, this 422s every ping.)

### A5 — Ping timestamps are fabricated client-side

`_alignTrackingTimestampsToPunchIn()` overwrites every real `captured_at`
with `punch_in + n × 30 min`. Remove once timezone-correct timestamps are
confirmed.

### A6 — Workmanager does not actually survive force-stop on most OEMs

The design notes claim the periodic task "survives app kill". That is true
for a normal swipe-away on stock Android; it is **false** on Xiaomi/MIUI,
Oppo/ColorOS, Vivo/Funtouch, and Samsung with aggressive battery
optimisation, where a force-stopped app's WorkManager jobs are cancelled
outright. Also note Android's periodic-work minimum interval is 15 minutes
and `initialDelay` is not guaranteed to be honoured for periodic tasks.

For reliable 30-minute tracking through a shift, a **foreground service**
with a persistent notification is needed, not WorkManager alone. The
`FOREGROUND_SERVICE_LOCATION` permission is already declared but no
foreground service is implemented.

### A7 — No ping is sent at punch-in time

`startTracking()` calls `_saveCurrentLocation(userId, 'In')`, but that method
returns early for any type other than `'Tracking'`. The comment says "post
the initial location immediately" — it does not. The first ping is therefore
the first Workmanager wake-up, realistically 15–30+ minutes later on Android,
and opportunistic (possibly hours) on iOS.

### A8 — Silent auto-refresh only reacts to list-length changes

`refreshTimelineSilently()` updates the UI only when `points.length` differs.
Corrections to existing pings never repaint.

---

## 5. Diagnosis decision tree for the backend dev

```
Does GET /me/geofence return "geofence_attendance": "Yes"?
├─ NO  → P0-1. Fix this first. Nothing else can work; the punch button is hidden.
└─ YES
   └─ Does it return non-null latitude, longitude, radius_m?
      ├─ NO  → P0-2. Populate the branches table. (Punching works, fence does not.)
      └─ YES
         └─ SELECT COUNT(*) FROM attendance_location_pings
            WHERE captured_at > NOW() - INTERVAL 1 DAY;
            ├─ 0 rows → pings are not arriving.
            │           Check logs for 409 / 422 / 429 on /attendance/location-ping.
            │           If the logs are clean → it is app-side A1 (background permission).
            └─ >0 rows → pings ARE stored; this is a read-path bug.
               └─ Does GET /attendance/today punches[] include session_id?
                  ├─ NO  → P0-3. App can never resolve the session → timeline never called.
                  └─ YES → Check /attendance/session/{id}/timeline:
                           is pings[] present? keys latitude/longitude/captured_at?
                           does the owner (non-admin) get 200 rather than 403?
```

---

## 6. Reproduction commands

Replace `$TOKEN` with a real employee Sanctum token.

```bash
BASE=https://hrms.mecpl.in/api
H=(-H "Authorization: Bearer $TOKEN"
   -H "X-API-Key: <the mobile X-API-Key>"
   -H "Accept: application/json")

# 1. Geofence bootstrap — must show geofence_attendance + non-null lat/lng/radius
curl -s "${H[@]}" "$BASE/me/geofence" | jq .

# 2. Today — every punch must carry session_id, latitude, longitude
curl -s "${H[@]}" "$BASE/attendance/today" | jq '.data.punches'

# 3. Timeline for the active session — pings[] must be non-empty during a shift
SID=<session_id from step 2>
curl -s "${H[@]}" "$BASE/attendance/session/$SID/timeline" \
  | jq '{pings: .data.pings, punch_in: .data.punch_in}'

# 4. Past-day history with pings
curl -s "${H[@]}" "$BASE/attendance/history?date=2026-08-28" | jq '.data.sessions[].pings'

# 5. Manual ping — should be 200, and ping_count should increment
curl -s -X POST "${H[@]}" -H "Content-Type: application/json" \
  -d "{\"session_id\":$SID,\"latitude\":18.5743404,\"longitude\":73.7736299,
       \"accuracy_m\":8.2,\"address\":\"test\",\"battery_pct\":null,
       \"captured_at\":\"$(date -u +%Y-%m-%dT%H:%M:%S.000000Z)\"}" \
  "$BASE/attendance/location-ping" | jq .

# 6. Batch flush — note the extra "is_queued" key the app sends
curl -s -X POST "${H[@]}" -H "Content-Type: application/json" \
  -d "{\"pings\":[{\"session_id\":$SID,\"latitude\":18.5743,\"longitude\":73.7736,
       \"accuracy_m\":null,\"address\":null,\"battery_pct\":null,
       \"captured_at\":\"$(date -u +%Y-%m-%dT%H:%M:%S.000000Z)\",\"is_queued\":true}]}" \
  "$BASE/attendance/location-ping/batch" | jq .
```

**Please paste the raw JSON of steps 1, 2 and 3 back to the mobile team** —
that alone will close out most of Section 3.

---

## 7. Backend checklist

Copy-paste for the ticket:

- [ ] **P0** `/me/geofence` returns `geofence_attendance` as the string `"Yes"` / `"No"` on every response
- [ ] **P0** `branches.latitude`, `longitude`, `geofence_radius_m` populated for all active branches
- [ ] **P0** `/attendance/today` — every object in `punches[]` includes `session_id`
- [ ] **P0** `/attendance/today` — every object in `punches[]` includes `latitude`, `longitude`, `punched_at`, `selfie_url`
- [ ] **P1** All numeric fields serialised as JSON numbers, not strings (`latitude`, `longitude`, `radius_m`, `branch_id`, `session_id`, `distance_m`, `accuracy_m`)
- [ ] **P1** `/attendance/session/{id}/timeline` returns `pings[]` with `latitude`, `longitude`, `captured_at` — exact key names
- [ ] **P1** Session **owner** (not only admins) gets 200 on their own `/session/{id}/timeline`
- [ ] **P1** `battery_pct` is `nullable` in ping validation (the app currently always sends `null`)
- [ ] **P1** The extra `is_queued` key in the batch payload is tolerated, not a validation failure
- [ ] **P1** Report yesterday's row count from `attendance_location_pings`, plus any 409 / 422 / 429 in the ping logs
- [ ] **P1** Confirm whether any job force-closes sessions (midnight IST?) — and what the app should do with a stale `session_id`
- [ ] **P2** All timestamps ISO-8601 **with offset** (`+05:30` or `Z`), consistently
- [ ] **P2** `selfie_url` is an absolute `https://hrms.mecpl.in/...` URL
- [ ] **P2** `/attendance/history?date=` includes `sessions[].pings[]`
- [ ] **P2** Answer the 7 open questions in `docs/ping-and-punch-images-backend-requirements.md` §8

## 8. Mobile checklist (app side)

- [ ] **P0** Request `LocationPermission.always` (Android "Allow all the time") as a second, explicit step
- [ ] **P1** Migrate `attendance_map_screen.dart` off `OfficeConfig` onto `GeofenceRepository`
- [ ] **P1** Tolerant numeric parsing in `_pointFromMap` and `Geofence.fromJson` (`branch_id`)
- [ ] **P1** Replace or supplement Workmanager with a foreground service for shift-duration tracking
- [ ] **P2** Send a real ping immediately at punch-in (the `'In'` type currently early-returns)
- [ ] **P2** Populate `battery_pct`, or drop it from the payload
- [ ] **P2** Delete `_alignTrackingTimestampsToPunchIn()` once backend timestamps carry offsets
- [ ] **P2** Surface ping/timeline errors in the UI instead of rendering a silent empty list
- [ ] **P2** `refreshTimelineSilently` should diff content, not just list length

---

## 9. What IS working

So this is not read as "everything is broken":

- All 9 attendance/geofence routes are deployed and auth-protected (verified by probe)
- Punch-in / punch-out multipart upload with selfie, coordinates, accuracy, address, `client_captured_at`
- Selfie storage and `selfie_url` on **punch** objects
- Session lifecycle — opened on punch-in, closed on punch-out, `session_id` returned and persisted locally
- 409 `SESSION_ALREADY_OPEN` and 409 `ALREADY_PUNCHED_TODAY` handled end-to-end
- Offline ping queue (500 cap, 24 h TTL, batches of 100) — the client side of it is sound
- Geofence caching in SharedPreferences, surviving app restart
- Haversine distance and inside/outside evaluation — correct **once real branch coordinates exist**
- Client-side reverse-geocoding backfill when `address` comes back empty
- Android and iOS permissions declared in the manifest / Info.plist
- Workmanager registered and cancelled at the right points in the punch lifecycle

**The plumbing is built. It is starved of correct data at three points and
blocked by one missing runtime permission.**
