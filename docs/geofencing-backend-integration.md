# Geofencing & Location Tracking — Backend Integration Spec

Complete reference for wiring the Flutter attendance/geofencing flow to a Laravel 10+ backend on `hrms.mecpl.in`.

---

## 1. Overview

The Flutter app already captures selfies, GPS coordinates, and 30-minute background location pings. Today the selfies and pings live only on the device. This document specifies the server-side tables, endpoints, and business rules needed to persist everything, plus the Flutter changes that pair with them.

### Core flow

```
[ First punch-in of day ]  → selfie + location + hard-fence check ─→ opens session
        │
        ├── every 30 min (while session open) → location ping only (no selfie)
        │    └── if offline, ping is queued on device and flushed later
        │
        ├── optional mid-day punch-out / punch-in (lunch) → selfie + location each
        │
[ Last punch-out of day ]  → selfie + location + hard-fence check ─→ closes session
```

---

## 2. Key Decisions (locked in)

| # | Decision |
|---|---|
| DB | MySQL (Laravel dev writes the actual migration files) |
| Selfie storage | `storage/app/public/attendance/{YYYY}/{MM}/{employee_id}_{timestamp}.jpg` |
| Geofence scope | Per-employee's **assigned branch** (employee → branch_id → branch geofence) |
| Out-of-fence punches | **Allowed** — backend accepts, flags `inside_geofence=0`. App shows a warning badge but does not block. |
| Out-of-fence pings | **Logged with `inside_geofence=0` flag** — never rejected (we still want the trail) |
| Punches per day | **Multiple in/out pairs allowed**; every punch captures a selfie |
| Realtime viewer | Admin role only (for now) |
| Retention | Location pings auto-purged after **180 days**; punches kept forever |
| Offline pings | **Queue-and-retry** via SharedPreferences; batch-flush on next success |
| Auth | Laravel Sanctum `Bearer <token>` — same scheme as current APIs |

---

## 3. Current Flutter State (what already exists)

| Concern | File | Status |
|---|---|---|
| Punch in/out UI | [attendance_screen.dart:528-634](../lib/screens/attendance/attendance_screen.dart) | Working; selfie captured but not uploaded |
| Provider logic | [attendance_provider.dart:461-592](../lib/providers/attendance_provider.dart) | Posts to `/attendance/clock-in` and `/attendance/clock-out`; needs to be replaced with new endpoints |
| Geofence math | [location_service.dart:75-92](../lib/services/location_service.dart) | Haversine distance works; coordinates source must move from `OfficeConfig` to API |
| Office coords | [office_config.dart](../lib/core/config/office_config.dart) | Hardcoded; **to be deprecated** |
| 30-min tracking | [background_location_service.dart](../lib/services/background_location_service.dart) | Timer runs; writes to SharedPreferences only; **needs to POST to backend** |
| Selfie capture | `services/camera_service.dart` | Saves jpg to app documents; **needs upload via multipart** |
| Branch model | `models/branch_model.dart` | Has `id` + `branchName`; **needs lat/lng/radius** |

---

## 4. Laravel Backend Work

### 4.1 Database schema

Four migrations needed. One ALTER, three CREATE.

#### 4.1.1 `branches` — ALTER (add geofence columns)

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| latitude | DECIMAL(10,7) | YES | NULL | Branch center |
| longitude | DECIMAL(10,7) | YES | NULL | Branch center |
| geofence_radius_m | SMALLINT UNSIGNED | YES | NULL | Typical 50–500 m; NULL means "no geofence enforced" |

Nullable so existing branch rows don't break. Admin UI can fill these later.

---

#### 4.1.2 `attendance_sessions` — CREATE

One row per in→out pair. Groups the pings under a session for easy lookup and clean purge.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | BIGINT UNSIGNED | NO | AUTO_INC | PK |
| employee_id | BIGINT UNSIGNED | NO | — | FK → employees.id |
| branch_id | BIGINT UNSIGNED | NO | — | FK → branches.id (snapshot of assigned branch at punch-in) |
| date | DATE | NO | — | Workday (local date, for grouping) |
| punch_in_id | BIGINT UNSIGNED | NO | — | FK → attendance_punches.id |
| punch_out_id | BIGINT UNSIGNED | YES | NULL | FK → attendance_punches.id (null while session open) |
| started_at | TIMESTAMP | NO | — | Server time when punch-in accepted |
| ended_at | TIMESTAMP | YES | NULL | Server time when punch-out accepted |
| duration_seconds | INT UNSIGNED | YES | NULL | Computed on close |
| ping_count | INT UNSIGNED | NO | 0 | Incremented per ping accepted |
| status | ENUM('active','closed','force_closed') | NO | 'active' | `force_closed` = admin manually ended |
| created_at | TIMESTAMP | NO | — | |
| updated_at | TIMESTAMP | NO | — | |

**Indexes**:
- `(employee_id, status)` — fast "does this employee have an open session?" check
- `(employee_id, date)` — fast "show me today's sessions"
- `(branch_id, status)` — admin live view

**Business rule**: at most one row per employee with `status='active'` at any time. Enforce in code, not with a unique index (since MySQL won't do partial indexes cleanly).

---

#### 4.1.3 `attendance_punches` — CREATE

One row per punch event (in OR out). Each row has a selfie.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | BIGINT UNSIGNED | NO | AUTO_INC | PK |
| employee_id | BIGINT UNSIGNED | NO | — | FK → employees.id |
| branch_id | BIGINT UNSIGNED | NO | — | FK → branches.id |
| session_id | BIGINT UNSIGNED | NO | — | FK → attendance_sessions.id |
| type | ENUM('in','out') | NO | — | |
| punched_at | TIMESTAMP | NO | — | Server time (authoritative) |
| client_captured_at | TIMESTAMP | YES | NULL | Device time (for clock-skew audit) |
| latitude | DECIMAL(10,7) | NO | — | |
| longitude | DECIMAL(10,7) | NO | — | |
| accuracy_m | FLOAT | YES | NULL | GPS accuracy reported by device |
| address | VARCHAR(500) | YES | NULL | Reverse-geocoded (optional) |
| inside_geofence | TINYINT(1) | NO | — | 1 = inside radius, 0 = outside. Punch is accepted either way; this is a reporting flag only. |
| distance_m | INT UNSIGNED | YES | NULL | Distance from branch center |
| selfie_path | VARCHAR(255) | NO | — | Relative path under `storage/app/public/` |
| device_info | JSON | YES | NULL | `{platform, model, os_version, app_version, battery_pct}` |
| is_first_of_day | TINYINT(1) | NO | 0 | Set to 1 for the day's first punch-in |
| is_last_of_day | TINYINT(1) | NO | 0 | Set to 1 for the day's final punch-out (updated when a newer out is recorded) |
| created_at | TIMESTAMP | NO | — | |
| updated_at | TIMESTAMP | NO | — | |

**Indexes**:
- `(employee_id, punched_at)`
- `(session_id)`
- `(branch_id, punched_at)` — admin reports

---

#### 4.1.4 `attendance_location_pings` — CREATE

Breadcrumb points between punch-in and punch-out. Purged after 180 days.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | BIGINT UNSIGNED | NO | AUTO_INC | PK |
| session_id | BIGINT UNSIGNED | NO | — | FK → attendance_sessions.id **ON DELETE CASCADE** |
| employee_id | BIGINT UNSIGNED | NO | — | Denormalized for fast per-employee queries |
| latitude | DECIMAL(10,7) | NO | — | |
| longitude | DECIMAL(10,7) | NO | — | |
| accuracy_m | FLOAT | YES | NULL | |
| address | VARCHAR(500) | YES | NULL | |
| inside_geofence | TINYINT(1) | NO | — | Flag only — pings are never rejected |
| distance_m | INT UNSIGNED | YES | NULL | |
| battery_pct | TINYINT UNSIGNED | YES | NULL | 0–100 |
| captured_at | TIMESTAMP | NO | — | Device time (when the ping was taken) |
| received_at | TIMESTAMP | NO | — | Server time (when it arrived — differs if queued) |
| is_queued | TINYINT(1) | NO | 0 | 1 = flushed from offline queue |
| created_at | TIMESTAMP | NO | — | |

**Indexes**:
- `(employee_id, captured_at)` — employee timeline queries
- `(session_id, captured_at)` — per-session ordered fetch
- `(captured_at)` — nightly purge cutoff

**No `updated_at`** — pings are immutable.

---

### 4.2 Selfie storage

- Directory: `storage/app/public/attendance/{YYYY}/{MM}/`
- Filename: `{employee_id}_{unix_timestamp}.jpg`
- Run `php artisan storage:link` once so files are served at `https://hrms.mecpl.in/storage/attendance/...`
- Validation: `mimes:jpg,jpeg,png`, `max:2048` (2 MB)
- Store only the relative path (e.g., `attendance/2026/04/2914_1713600000.jpg`) in `selfie_path`; the app builds the full URL by prepending the storage base.

---

### 4.3 Scheduled task — nightly purge (180-day retention)

Create a console command, e.g. `PurgeOldLocationPings`:

```
DELETE FROM attendance_location_pings WHERE captured_at < NOW() - INTERVAL 180 DAY
```

Register in `app/Console/Kernel.php`:
```php
$schedule->command('attendance:purge-pings')->dailyAt('02:30');
```

Only pings are purged. `attendance_sessions` and `attendance_punches` are kept forever.

---

### 4.4 API endpoints

All endpoints:
- Prefix: `/api`
- Auth: `Authorization: Bearer <sanctum-token>` header (existing convention)
- Content-Type: `multipart/form-data` for endpoints with selfie; `application/json` otherwise
- Error format: `{ "status": false, "error_code": "...", "message": "...", "data": {...} }`
- Success format: `{ "status": true, "message": "...", "data": {...} }`

---

#### 4.4.1 `GET /me/geofence`

Returns the employee's assigned branch geofence. Called once on login (and cached).

**Response 200**
```json
{
  "status": true,
  "data": {
    "branch_id": 12,
    "branch_name": "Pune HQ",
    "latitude": 18.5743404,
    "longitude": 73.7736299,
    "radius_m": 50
  }
}
```

If the employee's branch has no geofence configured, return `radius_m: null` — the app treats this as "no enforcement, always allow".

---

#### 4.4.2 `POST /attendance/punch-in`

Opens a new session.

**Request (multipart/form-data)**
| Field | Type | Required | Notes |
|---|---|---|---|
| selfie | file | yes | JPG/PNG, ≤ 2 MB |
| latitude | decimal | yes | |
| longitude | decimal | yes | |
| accuracy_m | float | no | |
| address | string | no | Reverse-geocoded client-side |
| client_captured_at | string (ISO 8601) | yes | Device time |
| device_info | JSON string | no | `{"platform":"android","model":"...","os_version":"14","app_version":"1.2.0","battery_pct":73}` |

**Backend logic**:
1. Resolve employee's assigned `branch_id`. Load branch geofence.
2. Compute Haversine distance. Record `inside_geofence` flag and `distance_m`. **Do not reject** — accept the punch regardless.
3. Check for existing `attendance_sessions` row with `employee_id=me, status='active'`. If found → `409 SESSION_ALREADY_OPEN` with the open session_id (UI can force-close or continue).
4. Save selfie to `storage/app/public/attendance/YYYY/MM/{employee_id}_{timestamp}.jpg`.
5. Insert `attendance_punches` row with `type='in'`, `is_first_of_day` = (is this the first punch today for this employee?).
6. Insert `attendance_sessions` row, status `active`.
7. Update the punch row with the new `session_id`.

**Response 200**
```json
{
  "status": true,
  "message": "Punch-in recorded.",
  "data": {
    "session_id": 3401,
    "punch_id": 98765,
    "server_time": "2026-04-20T03:35:23.000000Z",
    "is_first_of_day": true,
    "geofence": {"inside": true, "distance_m": 12, "radius_m": 50}
  }
}
```

**Response 200 when outside fence** — same 200 shape; `geofence.inside` is false. Client uses this to render a warning badge but does not treat it as an error.

**Response 409 SESSION_ALREADY_OPEN**
```json
{
  "status": false,
  "error_code": "SESSION_ALREADY_OPEN",
  "message": "You have an open session from 09:05. Punch out first.",
  "data": {"session_id": 3400, "started_at": "2026-04-20T03:35:23.000000Z"}
}
```

---

#### 4.4.3 `POST /attendance/punch-out`

Closes an active session.

**Request (multipart/form-data)**
| Field | Type | Required | Notes |
|---|---|---|---|
| session_id | integer | yes | The session being closed |
| selfie | file | yes | |
| latitude | decimal | yes | |
| longitude | decimal | yes | |
| accuracy_m | float | no | |
| address | string | no | |
| client_captured_at | string (ISO 8601) | yes | |
| device_info | JSON string | no | |

**Backend logic**:
1. Verify session belongs to `me` and `status='active'`. Else `403` / `404`.
2. Compute distance. Record `inside_geofence` and `distance_m`. **Do not reject** on out-of-fence.
3. Save selfie.
4. Insert `attendance_punches` row, `type='out'`, `is_last_of_day=1`.
5. Update previous `is_last_of_day=1` on older out-punches of the same employee today → set to 0 (only the newest out is "last").
6. Close session: `ended_at = NOW()`, `duration_seconds`, `status='closed'`, `punch_out_id`.

**Response 200**
```json
{
  "status": true,
  "message": "Punch-out recorded.",
  "data": {
    "session_id": 3401,
    "punch_id": 98801,
    "duration_seconds": 28740,
    "ping_count": 14,
    "is_last_of_day": true
  }
}
```

---

#### 4.4.4 `POST /attendance/location-ping`

Single ping (used during normal 30-min cadence).

**Request (application/json)**
```json
{
  "session_id": 3401,
  "latitude": 18.5743,
  "longitude": 73.7736,
  "accuracy_m": 8.2,
  "address": "Pune HQ, Hinjewadi",
  "battery_pct": 73,
  "captured_at": "2026-04-20T04:05:00.000000Z"
}
```

**Backend logic**:
1. Verify session belongs to `me` and is `active`. Else `403`.
2. Compute `inside_geofence` & `distance_m` (for the flag; never reject).
3. Insert `attendance_location_pings` row with `received_at = NOW()`, `is_queued = 0`.
4. `UPDATE attendance_sessions SET ping_count = ping_count + 1 WHERE id = ?`.

**Response 200**
```json
{
  "status": true,
  "data": {"ping_id": 554321}
}
```

**Rate limit suggestion**: max 1 ping per 60 seconds per session (prevents abuse if a malicious client loops).

---

#### 4.4.5 `POST /attendance/location-ping/batch`

Flush offline queue. Accepts up to 100 pings.

**Request (application/json)**
```json
{
  "pings": [
    {"session_id": 3401, "latitude": ..., "captured_at": "2026-04-20T04:05:00Z", "is_queued": true, ...},
    {"session_id": 3401, "latitude": ..., "captured_at": "2026-04-20T04:35:00Z", "is_queued": true, ...}
  ]
}
```

**Backend logic**: same as single ping, applied to each. Skip pings for closed/unknown sessions silently (return them in `rejected` so client can drop from queue).

**Response 200**
```json
{
  "status": true,
  "data": {
    "accepted": 2,
    "rejected": [],
    "ping_ids": [554322, 554323]
  }
}
```

---

#### 4.4.6 `GET /attendance/today`

Employee's own view — current session + today's punches.

**Response 200**
```json
{
  "status": true,
  "data": {
    "active_session": {
      "session_id": 3401,
      "started_at": "2026-04-20T03:35:23Z",
      "ping_count": 14,
      "last_ping": {"latitude": 18.5743, "longitude": 73.7736, "captured_at": "2026-04-20T04:05:00Z"}
    },
    "punches": [
      {"type": "in", "punched_at": "2026-04-20T03:35:23Z", "selfie_url": "https://hrms.mecpl.in/storage/attendance/2026/04/2914_1713600923.jpg"}
    ],
    "total_hours_today": 0.5
  }
}
```

If no active session, `active_session: null`.

---

#### 4.4.7 `GET /attendance/live` — admin only

Live snapshot of every open session in the company (or a branch).

**Query params**: `branch_id` (optional), `limit` (default 100)

**Authorization**: middleware `can:view-live-attendance` (admin role).

**Response 200**
```json
{
  "status": true,
  "data": [
    {
      "session_id": 3401,
      "employee": {"id": 2914, "name": "UDAYRAJ", "emp_code": "30444"},
      "branch": {"id": 12, "name": "Pune HQ"},
      "started_at": "2026-04-20T03:35:23Z",
      "last_ping": {
        "latitude": 18.5743,
        "longitude": 73.7736,
        "inside_geofence": true,
        "captured_at": "2026-04-20T04:05:00Z"
      },
      "ping_count": 14
    }
  ]
}
```

Polled every ~30 s by the admin UI. If websocket infra exists, prefer pushing updates; otherwise polling is fine.

---

#### 4.4.8 `GET /attendance/session/{session_id}/timeline` — admin only

Full breadcrumb for a single session. Used by the admin map view.

**Response 200**
```json
{
  "status": true,
  "data": {
    "session": {"id": 3401, "employee_id": 2914, "started_at": "...", "ended_at": null, "status": "active"},
    "punch_in": {"latitude": ..., "punched_at": "...", "selfie_url": "..."},
    "punch_out": null,
    "pings": [
      {"latitude": ..., "longitude": ..., "captured_at": "...", "inside_geofence": true, "accuracy_m": 8},
      ...
    ]
  }
}
```

---

#### 4.4.9 `GET /attendance/history` — list sessions

Existing endpoint stays. Add `session_id` to each row so the client can drill into `timeline`.

---

### 4.5 Authorization matrix

| Endpoint | Who can call |
|---|---|
| `GET /me/geofence` | Any authenticated employee |
| `POST /attendance/punch-in` | Any employee |
| `POST /attendance/punch-out` | Owner of the session |
| `POST /attendance/location-ping` | Owner of the session |
| `POST /attendance/location-ping/batch` | Owner of the sessions in the batch |
| `GET /attendance/today` | Self only |
| `GET /attendance/live` | Admin |
| `GET /attendance/session/{id}/timeline` | Admin, or the session's owner |

Enforce with Sanctum + Laravel policies / Gates.

---

### 4.6 Validation rules (Laravel FormRequest)

```php
// PunchInRequest
'selfie'            => 'required|file|mimes:jpg,jpeg,png|max:2048',
'latitude'          => 'required|numeric|between:-90,90',
'longitude'         => 'required|numeric|between:-180,180',
'accuracy_m'        => 'nullable|numeric|min:0|max:10000',
'address'           => 'nullable|string|max:500',
'client_captured_at'=> 'required|date',
'device_info'       => 'nullable|json',
```

Mirror for punch-out (+ `session_id: required|integer|exists:attendance_sessions,id`).

---

### 4.7 Rate limiting

Add to `RouteServiceProvider` or directly in routes:
```php
Route::middleware(['auth:sanctum', 'throttle:30,1'])->group(function () {
    Route::post('/attendance/location-ping', ...);   // 30/min is generous; normal cadence is 1/30min
});
```

Punch endpoints: `throttle:6,1` (someone spam-tapping the button shouldn't create 60 rows).

---

## 5. Flutter Work

### 5.1 New files to create

| File | Purpose |
|---|---|
| `lib/repositories/geofence_repository.dart` | Fetches `GET /me/geofence` on login, caches in SharedPrefs, exposes `isInside(lat,lng)` + `distance(lat,lng)`. Replaces `OfficeConfig`. |
| `lib/models/attendance_session.dart` | Represents an active session (`sessionId`, `startedAt`, `pingCount`). Persisted in SharedPrefs. |
| `lib/services/ping_queue_service.dart` | Wraps SharedPrefs list `pending_pings`. `enqueue(ping)`, `flush()` via `location-ping/batch`. |
| `lib/screens/admin/live_attendance_screen.dart` | Admin realtime view. Polls `/attendance/live` every 30s. List of active employees with last known location. |

### 5.2 Existing files to modify

| File | Change |
|---|---|
| `lib/services/api_service.dart` | Replace `postClockIn` / `postClockOut` with new methods: `punchIn(...)`, `punchOut(...)`, `sendLocationPing(...)`, `flushPingBatch(...)`, `getTodayAttendance()`, `getMyGeofence()`, `getLiveAttendance()`. All use multipart where appropriate. |
| `lib/providers/attendance_provider.dart` | `punchInWithLocation` → call new `punchIn`, receive `session_id`, store in SharedPrefs under `active_session`. `punchOutWithLocation` → call new `punchOut`, clear `active_session`. Handle 409 `SESSION_ALREADY_OPEN`. Surface `geofence.inside=false` as a non-blocking warning. |
| `lib/services/location_service.dart` | Replace `OfficeConfig` references with `GeofenceRepository`. |
| `lib/services/background_location_service.dart` | Instead of writing to SharedPrefs, call `sendLocationPing`. On failure, delegate to `PingQueueService.enqueue`. On next successful ping OR on app resume, call `PingQueueService.flush`. Pass `session_id` from SharedPrefs. Stop the timer when no active session. |
| `lib/core/config/office_config.dart` | Mark deprecated; delete after `GeofenceRepository` is fully wired. |
| `lib/screens/attendance/attendance_screen.dart` | If `geofence.inside == false` on the response, show a non-blocking warning badge (e.g., "Punched 153 m outside fence — flagged for review"). Keep the punch buttons enabled regardless of distance. |
| `lib/screens/dashboard/dashboard_screen.dart` | For admin role, add a new quick-action button "Live Attendance" that opens `LiveAttendanceScreen`. |

### 5.3 Offline queue design

**SharedPreferences key**: `pending_pings` → JSON-encoded list of ping objects (each includes `session_id`, `captured_at`, coordinates).

**Triggers for flush**:
1. Before each normal 30-min ping — if queue is non-empty, flush via `location-ping/batch` first, then send current ping.
2. On app resume (`AppLifecycleState.resumed`) — flush queue.
3. On connectivity restore (optional; listen to `connectivity_plus` if already a dep).

**Enqueue rules**:
- Cap queue at 500 pings (should never happen — 500 × 30 min = 10 days continuous offline; if reached, drop oldest).
- If session has been closed for > 24 hours, drop its queued pings silently (server would reject anyway).

### 5.4 Realtime admin screen (minimal)

A single `ListView` polling `/attendance/live`:

```
┌──────────────────────────────────────────────────┐
│ UDAYRAJ (EMP#30444) — Pune HQ                    │
│ Started: 09:05 | Pings: 14 | Inside fence ✓     │
│ Last: 18.5743, 73.7736 (2 min ago)              │
├──────────────────────────────────────────────────┤
│ RAJESH... (EMP#30441) — Pune HQ                  │
│ Started: 09:12 | Pings: 13 | Outside fence ⚠   │
└──────────────────────────────────────────────────┘
```

Tap a row → `/attendance/session/{id}/timeline` → map (later phase; for now just a scrollable list of coordinates is acceptable).

### 5.5 Gating

- `LiveAttendanceScreen` button visibility: `role == UserRole.admin`. Add the route guard at the `Navigator.push` site.
- Gate on the backend too — never trust the client.

---

## 6. End-to-end sequence (for reference)

```
App                                           Laravel
 │                                               │
 │── Login ───────────────────────────────────▶ │
 │◀── token + user ──────────────────────────── │
 │                                               │
 │── GET /me/geofence ──────────────────────▶ │
 │◀── {lat, lng, radius_m} ──────────────────── │
 │   (cached to SharedPreferences)               │
 │                                               │
 │   User taps Punch In, selfie captured         │
 │── POST /attendance/punch-in (multipart) ──▶ │
 │   server records inside_geofence + distance   │
 │   (never rejects on distance)                 │
 │◀── 200 {session_id, geofence:{inside,...}} ── │
 │   (session_id stored locally)                 │
 │                                               │
 │   Background timer fires every 30 min        │
 │── POST /attendance/location-ping ────────▶ │
 │   (if fails → PingQueueService.enqueue)      │
 │◀── 200 ─────────────────────────────────── │
 │                                               │
 │   User taps Punch Out                         │
 │── POST /attendance/location-ping/batch ──▶ │  (flush any queue first)
 │── POST /attendance/punch-out (multipart) ─▶ │
 │◀── 200 {duration_seconds, ...} ───────────── │
 │   (clear active_session)                      │
 │                                               │
 │   [Admin] opens Live Attendance               │
 │── GET /attendance/live ──────────────────▶ │
 │◀── [{session, employee, last_ping}, ...] ─── │
 │   (re-poll every 30 s)                        │
```

---

## 7. Testing checklist

**Laravel**:
- [ ] Migrations run cleanly on a fresh DB
- [ ] Punch-in inside fence → 200, row created with `inside_geofence=1`, selfie saved
- [ ] Punch-in outside fence → 200, row created with `inside_geofence=0`, `distance_m` populated, selfie saved
- [ ] Second punch-in while session open → 409 with existing session_id
- [ ] Punch-out with wrong session_id (someone else's) → 403
- [ ] Punch-out outside fence → 200 with `inside_geofence=0`, session closed normally
- [ ] Location ping outside fence → 200 with `inside_geofence=false`
- [ ] Batch ping with 1 invalid session → rest accepted, invalid returned in `rejected`
- [ ] `GET /attendance/live` as non-admin → 403
- [ ] `php artisan attendance:purge-pings` deletes only rows > 180 days old

**Flutter**:
- [ ] First punch of day captures selfie, uploads, receives session_id
- [ ] Second punch-in same day (after punch-out) also captures selfie
- [ ] Out-of-fence punch shows non-blocking warning badge with distance
- [ ] Airplane mode → pings queue → restore network → queue flushes on next ping
- [ ] Force-closing app during session: on reopen, timer resumes using stored session_id
- [ ] Admin Live screen shows active sessions; updates on poll
- [ ] Non-admin user does not see Live Attendance button

---

## 8. Open items / future work

1. **Websockets for live view**: polling is fine for now; migrate to Laravel Reverb / Pusher once admin usage grows.
2. **Map view**: `google_maps_flutter` integration for the session timeline — not in v1.
3. **Geofence violation alerts**: when a ping falls outside the fence for > N consecutive points, notify manager.
4. **Selfie face-match**: verify the selfie is actually the employee (ML Kit face detection). Out of scope here.
5. **Multi-branch employees**: if an employee legitimately visits other branches, decide whether to match against nearest branch instead of assigned branch. Currently locked to assigned branch.
6. **Timezone handling**: all server timestamps are UTC; client converts to `Asia/Kolkata` (IST) for display. Confirm backend DB `timezone='+00:00'`.

---

## 9. Change log for this spec

| Date | Change |
|---|---|
| 2026-04-20 | Initial spec |
