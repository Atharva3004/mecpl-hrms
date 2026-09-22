# Geofence Module — Contract Gap Analysis

**Date:** 2026-08-29
**Compares:** `docs/geofence-module-guide.md` (v1.0, from the backend dev)
**Against:** the Flutter app's actual parsing code
**Verdict:** the backend is **built and correct**. The app is parsing a
**different response shape** than the backend actually returns. Every
"geofence and ping not showing" symptom traces to **four field-name /
nesting mismatches**, all fixable on the Flutter side.

---

## 0. Executive summary

The backend guide answers the open questions from
`docs/geofence-ping-not-showing-report.md`. Two of the four P0 causes in that
report were **wrong about the mechanism** and are corrected here.

| # | Mismatch | Symptom it causes | Fix side |
|---|---|---|---|
| **M1** | `/me/geofence` nests branch fields under `branch{}`; the app reads them flat, and `branch_id` does not exist at all | Geofence **never caches**. Neutral ribbons, distances measured against a hard-coded Pune office, no fence circle. | **Flutter** |
| **M2** | `/attendance/today` punches carry **no `latitude`/`longitude`** | Every punch row is discarded → "Waiting for today's punch-in…" | **Backend** (add fields) |
| **M3** | `/attendance/today` punches carry **no `session_id`** | App cannot resolve the session after an app kill/reinstall → timeline never fetched → **pings never show** | **Backend** (add field) |
| **M4** | 409 error key is `code`, the app reads `error_code` | `ALREADY_PUNCHED_TODAY` is misread as `SESSION_ALREADY_OPEN` — wrong message, wrong UI state | **Flutter** |

M1 is the geofence bug. M3 is the ping bug. Neither needs a big rewrite.

---

## 1. M1 — `/me/geofence` response shape (Flutter fix) 🔴

### What the backend actually returns (guide §3.1)

```json
{
    "status": true,
    "geofence_attendance": "Yes",
    "branch": {
        "id": 5,
        "branch_name": "Mumbai Office",
        "latitude": 19.0760,
        "longitude": 72.8777,
        "geofence_radius_m": 200
    }
}
```

### What the app tries to read

[`lib/repositories/geofence_repository.dart:60-65`](../lib/repositories/geofence_repository.dart#L60-L65):

```dart
branchId: (json['branch_id'] as num).toInt(),      // ← key does not exist
branchName: (json['branch_name'] ?? '').toString(), // ← nested under branch{}
latitude:  toDOrNull(json['latitude']),             // ← nested under branch{}
longitude: toDOrNull(json['longitude']),            // ← nested under branch{}
radiusM:   toIntOrNull(json['radius_m']),           // ← named geofence_radius_m
geofenceAttendance: (json['geofence_attendance'] ?? 'No').toString(),  // ← this one is correct
```

And [`geofence_repository.dart:112`](../lib/repositories/geofence_repository.dart#L112) unwraps `raw['data']`,
but this response has **no `data` envelope** — the payload is at the top
level, so `payload` correctly falls through to `raw`.

### The failure chain

1. `json['branch_id']` is `null`
2. `(null as num)` **throws a TypeError** — this is a non-null cast
3. The throw is swallowed by the bare `catch (_) { return _cached; }` in `refresh()`
4. **Nothing is ever written to SharedPreferences.** `GeofenceRepository.cached`
   stays `null` for the entire life of the app

### Everything that breaks as a result

| Consequence | Where |
|---|---|
| `check()` falls back to the deprecated hard-coded Pune HQ (`18.5743404, 73.7736299`) | `geofence_repository.dart` `check()` |
| `isInside` is set to `null` on every row → **grey/neutral ribbon, never green or red** | `location_history_provider.dart` `_pointFromMap` |
| Distances shown are the distance to **Pune**, not to the employee's branch | same |
| No fence circle can be drawn from real branch data | `attendance_map_screen.dart` |

One accidental piece of luck: `_applyGeofenceFlag` uses
`g?.isAttendanceEnabled ?? true`, so a `null` cache defaults to
**enabled** — which is why the punch button still appears. Had the parse
half-succeeded, the button would have been hidden instead.

### Fix (Flutter)

```dart
factory Geofence.fromJson(Map<String, dynamic> json) {
  // Backend nests branch fields under `branch{}` and names the radius
  // `geofence_radius_m`. Accept the flat shape too so a future contract
  // change (or a cached older payload) doesn't break us again.
  final branch = json['branch'] is Map<String, dynamic>
      ? json['branch'] as Map<String, dynamic>
      : json;

  return Geofence(
    branchId: toIntOrNull(branch['id'] ?? json['branch_id']) ?? 0,
    branchName: (branch['branch_name'] ?? '').toString(),
    latitude:  toDOrNull(branch['latitude']),
    longitude: toDOrNull(branch['longitude']),
    radiusM:   toIntOrNull(branch['geofence_radius_m'] ?? branch['radius_m']),
    geofenceAttendance: (json['geofence_attendance'] ?? 'No').toString(),
  );
}
```

Also change `branchId` off the non-null `as num` cast — a single missing
key must never be able to throw away the whole geofence.

> **Note on the cache:** `toJson()` writes the *flat* shape to
> SharedPreferences and `fromJson()` reads it back. Once `fromJson` accepts
> both shapes (as above), the round-trip stays consistent. Bump the prefs key
> (e.g. `my_geofence_cache_v2`) so any garbage from before the fix is dropped.

---

## 2. M2 — `/attendance/today` punches have no coordinates (Backend fix) 🔴

### What the backend returns (guide §3.6)

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

**Missing:** `latitude`, `longitude`, `accuracy_m`, `address`, `session_id`.

### Why that empties the screen

[`location_history_provider.dart`](../lib/providers/location_history_provider.dart) `_pointFromMap`:

```dart
final lat = (m['latitude'] as num?)?.toDouble();
final lng = (m['longitude'] as num?)?.toDouble();
if (lat == null || lng == null || tsRaw == null) return null;   // row discarded
```

Every punch is dropped, so Today's Timing shows the empty state even after a
successful punch-in. The local-cache fallback added earlier masks this only
on the device that made the punch, on the same day.

The columns **exist in the DB** — guide §2.4 lists `latitude`, `longitude`,
`accuracy_m`, `address` on `attendance_punches`. They are simply not being
selected into the `/today` response.

### Ask for the backend

Add to each object in `punches[]`: `latitude`, `longitude`, `accuracy_m`,
`address`, and `session_id` (see M3). Same for `sessions[].punches[]` in
`/attendance/history` (guide §3.7 has the same omission).

Note `/attendance/session/{id}/timeline` (guide §3.8) **does** include
`latitude`/`longitude` on `punch_in` and `punch_out` — so the fields are
already being exposed elsewhere. It is just `/today` and `/history` that omit
them.

---

## 3. M3 — `/attendance/today` punches have no `session_id` (Backend fix) 🔴

**This is the direct cause of "pings not showing."**

[`location_history_screen.dart:770`](../lib/screens/tracking/location_history_screen.dart#L770):

```dart
final sessionId = att.todaySessionId;
if (sessionId == null) { _refreshTimer?.cancel(); return; }   // silent dead end
provider.loadFromTodaysSession(token: token, sessionId: sessionId, ...);
```

`todaySessionId` resolves in this order:
1. the in-memory `_activeSession` (present only while the app remembers the punch), then
2. `punches[].session_id` from `/attendance/today`

Without step 2 there is **no recovery path** after an app kill, a reinstall,
a punch-out, or an admin viewing someone else. The timeline request is never
issued and the user sees an empty tracking list with **no error message at
all**.

The guide's own §4.2 Step 2 says "If `active_session != null` … use the
existing session_id" — that works while a session is open. But once the
session closes, `active_session` is `null` and the day's pings become
unreachable, because the punches don't carry the id either.

### Ask for the backend

Add `session_id` to every object in `punches[]` on `/attendance/today` **and**
on `/attendance/history` `sessions[].punches[]`.

> Cheap alternative if that's awkward: `/attendance/history` already returns
> `sessions[].id`. The app could read the session id from there. But `/today`
> has no `sessions[]` array, so `punches[].session_id` is still needed for
> today's closed session.

---

## 4. M4 — Error code key is `code`, not `error_code` (Flutter fix) 🟠

### What the backend returns (guide §3.2, §5)

```json
{
    "status": false,
    "code": "SESSION_ALREADY_OPEN",
    "message": "You already have an active session.",
    "session_id": 142
}
```

### What the app reads

[`attendance_provider.dart:1253`](../lib/providers/attendance_provider.dart#L1253) and
[`api_service.dart:3542`](../lib/services/api_service.dart#L3542):

```dart
final errorCode = raw['error_code']?.toString();   // ← always null
```

So the `ALREADY_PUNCHED_TODAY` branch is **never taken**. Both 409s fall
through to the default handler, which shows *"You already have an open
session. Punch out first."* — wrong message and wrong state for an employee
who has actually finished the day.

### Fix (Flutter)

Accept both keys everywhere the error code is read:

```dart
final errorCode = (raw['code'] ?? raw['error_code'])?.toString();
```

Good news: `_extractPayload` falls back to `raw` when there is no `data`
envelope, so the top-level `session_id` in the 409 body **is** reachable
already.

Also unhandled: the new **403 `GEOFENCE_NOT_ENABLED`** (guide §3.2). Today it
surfaces as a generic error string. It should disable the punch UI and show
"Geofence attendance is not enabled for your account. Contact admin."

---

## 5. Contract changes we had not implemented yet

### 5.1 Ping endpoints are now `multipart/form-data` with an optional selfie 🟠

Guide §3.4 / §3.5 answer the open questions from
`docs/ping-and-punch-images-backend-requirements.md` — the backend **built
what we asked for**:

| Our ask | Backend answer |
|---|---|
| Field name | `selfie` / `selfie_url` ✅ (matches punch) |
| Batch max with images | **20** (100 without) ✅ |
| Image optional on pings | ✅ optional, `selfie_url: null` when absent |
| Batch file naming | `selfie_0`, `selfie_1`, … by array index ✅ |

The app currently posts **`application/json`** to both ping endpoints and
never sends a selfie. Laravel does parse a JSON body into `$request->all()`,
so this most likely still works for the no-image case — **but confirm it**,
because the guide documents multipart only.

Follow-up work on our side: switch the ping calls to multipart and attach a
selfie when one is genuinely available. Per §6 of our earlier requirements
doc, background pings usually cannot capture one, so this stays optional.

### 5.2 `is_queued` is no longer ours to send 🟡

`PingQueueService.toJson()` adds `"is_queued": true` to every queued ping.
The backend's batch endpoint sets that column itself and the guide's
`pings[]` schema does not list the field. Harmless if ignored — **confirm it
isn't a validation failure**, then drop it from our payload.

### 5.3 Batch response `rejected` changed type 🟡

Old contract: `rejected` was an **array** of `{index, reason}`.
Guide §3.5: `rejected` is an **integer count**, with details in a separate
`errors[]` array.

`PingQueueService.flush()` only reads `accepted`, so nothing breaks today.
But it also **never inspects `errors[]`** — permanently rejected pings
("Session not active") are silently dropped with no log. Worth wiring up so
this class of failure stops being invisible.

### 5.4 Timestamps are clean — remove our workaround 🟡

Every timestamp in the guide is ISO-8601 with an explicit `Z`
(`"2026-08-29T09:30:15.000000Z"`). That retires the concern about naive
timestamps.

So `_alignTrackingTimestampsToPunchIn()` — which **overwrites every real
`captured_at` with `punch_in + n × 30 min`** — is now actively harmful. It is
currently showing invented times on the timeline. Delete it once M1–M3 are
fixed and real pings render.

---

## 6. Backend bugs disclosed in the guide that affect us

The backend dev documented these in §6. Two change how we should behave:

### 6.1 `hasGeofence()` NULL→0 cast bug (guide §6.2) 🔴

`geofence_radius_m` is cast to `integer`, so Eloquent turns `NULL` into `0`,
and `hasGeofence()` returns `true` for an unconfigured branch. Distance is
then compared against a **0-metre radius**, so **every punch at an
unconfigured branch is flagged `inside_geofence: false`**.

This directly contradicts the guide's own Business Rules table, which states
that a branch with no coordinates marks all punches `inside_geofence: true`.

**Impact on us:** until it's fixed, out-of-fence warning badges will appear
for everyone at a branch that has no geofence configured. Do not treat
`inside_geofence: false` as trustworthy until the backend confirms the fix
**and** the branch actually has lat/lng/radius set.

**Ask:** fix as described (`geofence_radius_m > 0` or `getRawOriginal()`),
and confirm which branches currently have coordinates configured at all.

### 6.2 IST vs UTC date boundary (guide §6.3) 🟠

Session `date` is stored in server timezone (UTC) while the
"already punched today" check uses IST. Between **05:30 and 11:00 IST**, the
two disagree by one day.

**Impact on us:** `/attendance/today` can return **yesterday's** data during
the morning — exactly when employees punch in. This is a second, independent
reason the screen can look empty or wrong first thing in the day, and it will
survive the M2/M3 fixes.

**Ask:** treat this as P0 alongside M2/M3 — it is in the punch-in window.
Our side: keep sending `client_captured_at` with an explicit `+05:30` offset
(we currently send `.toUtc()`, which is valid ISO-8601 but hands the backend
a UTC date; worth confirming which they key off).

### 6.3 Double-tap race creating two sessions (guide §6.1) 🟠

Their recommended client workaround is to disable the punch button on tap.
**We should verify our punch button actually does this** — `_isLoading` is
set only *after* the GPS fix and the reverse-geocode, which can take several
seconds. That is a wide open window for a second tap.

### 6.4 Batch selfie filename collision (guide §6.5) 🟡

Second selfie in a batch overwrites the first (1-second timestamp
resolution). Only matters once we start sending ping selfies — worth knowing
before we build 5.1.

---

## 7. Corrections to our earlier report

`docs/geofence-ping-not-showing-report.md` was written without the backend
contract. Two items in it should be retracted:

| Earlier claim | Reality |
|---|---|
| **P0-1:** "`/me/geofence` omits `geofence_attendance`, so the punch button is hidden" | **Wrong.** The field is returned, at the top level, correctly named. The real bug is M1 — `branch_id` doesn't exist and the branch fields are nested, which throws and kills the whole parse. The button is *not* hidden (the null-cache default is "enabled"). |
| **P0-2:** "branch lat/lng/radius are NULL in the DB" | **Unconfirmed and probably not the issue.** The columns exist and the endpoint returns them. Still worth asking which branches are actually populated — and guide §6.2 means an unconfigured branch misbehaves in a specific way. |

Items that **stand as written**: M2/M3 (was P0-3), the strict-cast fragility,
and the app-side background-location-permission gap (A1 — still the reason a
backgrounded ping cannot get a GPS fix, entirely independent of the backend).

---

## 8. Action list

### Flutter (ours) — do these first, they unblock everything

- [ ] **M1** Rewrite `Geofence.fromJson` for the `branch{}` envelope + `geofence_radius_m`; drop the non-null `as num` on `branchId`; bump the cache key
- [ ] **M4** Read `code` as well as `error_code` in `attendance_provider` and `api_service`
- [ ] Handle **403 `GEOFENCE_NOT_ENABLED`** — disable punch UI with the admin-contact message
- [ ] Make `_pointFromMap` tolerant of string numerics (Laravel `decimal` casts)
- [ ] **A1** Request `LocationPermission.always` — background pings cannot get a fix without it
- [ ] Disable the punch button on **first tap**, before the GPS fix, not after (guide §6.1)
- [ ] Migrate `attendance_map_screen.dart` off `OfficeConfig` onto `GeofenceRepository`
- [ ] Delete `_alignTrackingTimestampsToPunchIn()` once real pings render
- [ ] Log `errors[]` from the batch response instead of silently dropping rejects
- [ ] Populate `battery_pct` (backend accepts 0–100, nullable)
- [ ] Later: switch ping calls to multipart and send a selfie when one exists

### Backend — short list

- [ ] **M2** Add `latitude`, `longitude`, `accuracy_m`, `address` to `punches[]` on `/attendance/today` and `/attendance/history`
- [ ] **M3** Add `session_id` to `punches[]` on `/attendance/today` and `/attendance/history`
- [ ] **§6.2** Fix `hasGeofence()` NULL→0 cast — currently flags everyone at an unconfigured branch as outside
- [ ] **§6.3** Fix the IST/UTC date boundary — `/today` returns yesterday's data between 05:30 and 11:00 IST
- [ ] Confirm the ping endpoints still accept `application/json` when no selfie is attached (guide documents multipart only)
- [ ] Confirm an extra `is_queued` key in the batch payload is ignored, not a 422
- [ ] Confirm which branches actually have `latitude` / `longitude` / `geofence_radius_m` populated
- [ ] Add `total_seconds` to the `/attendance/history` response (the app reads it; §3.7 does not show it)

---

## 9. What the guide confirms is working

- All 9 endpoints built, documented, and matching the agreed paths
- Punch-in/out multipart with selfie, GPS, accuracy, `client_captured_at`, `device_info`
- Haversine distance and `inside_geofence` flagging — track-only, never blocking
- Session lifecycle with `duration_seconds` and `ping_count`
- `/session/{id}/timeline` returns `punch_in` + `pings[]` + `punch_out` with full coordinates — **exactly the shape the app already parses**
- Offline batch sync, with the ping-selfie support we asked for (20 with images, 100 without)
- All three punch-in error codes implemented, including the new `GEOFENCE_NOT_ENABLED`
- Timestamps are ISO-8601 with an explicit timezone marker
- The backend dev disclosed 10 of their own known bugs, with file names and suggested fixes — that is unusually good handover

**Bottom line: the backend did its job. The remaining work is mostly ours —
one parser rewrite (M1) and one error-key fix (M4) — plus two additive field
changes on their side (M2, M3).**
