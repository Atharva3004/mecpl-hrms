# Backend Developer Tasks — Geofence & Geotagging

_Generated: 2026-05-19_
_Target: Laravel + MySQL backend supporting the MECPL Flutter app_

This is the complete punch-list for the backend dev to make the Flutter app's geofence + geotagging features fully functional. Every endpoint path and field name is taken **verbatim** from the existing contract docs in this folder ([geofencing-backend-integration.md](geofencing-backend-integration.md), [geofencing-api-reference.md](geofencing-api-reference.md), [laravel-backend-implementation.md](laravel-backend-implementation.md), [laravel-backend-pending.md](laravel-backend-pending.md), [laravel-backend-changes-v2.md](laravel-backend-changes-v2.md)).

The Flutter client already calls all of these endpoints — see [lib/services/api_service.dart](../lib/services/api_service.dart) `punchInWithLocation`, `punchOutWithLocation`, `sendLocationPing`, `flushPingQueue`.

---

## 1. Database Schema

### 1.1 ALTER `branches` — add geofence columns

| Column | Type | Nullable | Notes |
|---|---|---|---|
| `latitude` | `DECIMAL(10,7)` | yes | Branch centre |
| `longitude` | `DECIMAL(10,7)` | yes | Branch centre |
| `geofence_radius_m` | `SMALLINT UNSIGNED` | yes | NULL = no fence enforced |

### 1.2 CREATE `attendance_sessions`

| Column | Type | Notes |
|---|---|---|
| `id` | `BIGINT UNSIGNED` PK | |
| `employee_id` | `BIGINT UNSIGNED` FK → employees | |
| `branch_id` | `BIGINT UNSIGNED` FK → branches | |
| `date` | `DATE` | Local (IST) date for grouping |
| `punch_in_id` | `BIGINT UNSIGNED` FK | nullable |
| `punch_out_id` | `BIGINT UNSIGNED` FK | nullable |
| `started_at` | `TIMESTAMP` | |
| `ended_at` | `TIMESTAMP` | nullable |
| `duration_seconds` | `INT UNSIGNED` | nullable |
| `ping_count` | `INT UNSIGNED` | default 0 |
| `status` | `ENUM('active','closed','force_closed')` | default `'active'` |

Indexes: `(employee_id, status)`, `(employee_id, date)`, `(branch_id, status)`.

### 1.3 CREATE `attendance_punches`

| Column | Type | Notes |
|---|---|---|
| `id` | `BIGINT UNSIGNED` PK | |
| `employee_id`, `branch_id`, `session_id` | `BIGINT UNSIGNED` FKs | |
| `type` | `ENUM('in','out')` | |
| `punched_at` | `TIMESTAMP` | **server time, authoritative** |
| `client_captured_at` | `TIMESTAMP` | nullable, device time |
| `latitude`, `longitude` | `DECIMAL(10,7)` | |
| `accuracy_m` | `FLOAT` | nullable |
| `address` | `VARCHAR(500)` | nullable |
| `inside_geofence` | `TINYINT(1)` | flag only; punch accepted either way |
| `distance_m` | `INT UNSIGNED` | nullable |
| `selfie_path` | `VARCHAR(255)` | relative path under `storage/app/public/` |
| `device_info` | `JSON` | nullable |
| `is_first_of_day`, `is_last_of_day` | `TINYINT(1)` | default 0 |

Indexes: `(employee_id, punched_at)`, `(session_id)`, `(branch_id, punched_at)`.

### 1.4 CREATE `attendance_location_pings`

| Column | Type | Notes |
|---|---|---|
| `id` | `BIGINT UNSIGNED` PK | |
| `session_id` | `BIGINT UNSIGNED` FK ON DELETE CASCADE | |
| `employee_id` | `BIGINT UNSIGNED` FK | denormalized for fast queries |
| `latitude`, `longitude` | `DECIMAL(10,7)` | |
| `accuracy_m` | `FLOAT` | nullable |
| `address` | `VARCHAR(500)` | nullable |
| `inside_geofence` | `TINYINT(1)` | pings never rejected |
| `distance_m` | `INT UNSIGNED` | nullable |
| `battery_pct` | `TINYINT UNSIGNED` (0–100) | nullable |
| `captured_at` | `TIMESTAMP` | device time when ping was captured |
| `received_at` | `TIMESTAMP` | server time when it arrived |
| `is_queued` | `TINYINT(1)` | 1 = flushed from offline queue |

No `updated_at` — pings are immutable.
Indexes: `(employee_id, captured_at)`, `(session_id, captured_at)`, `(captured_at)` (for nightly purge).

---

## 2. API Endpoints

**Common:**
- Auth: `Authorization: Bearer <sanctum-token>` on every endpoint
- `Accept: application/json`
- Rate limits: punch **6/min**, pings **30/min**, others default

### 2.1 `GET /api/me/geofence` — bootstrap on login

**200**
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
- `radius_m: null` → no geofence enforced (client treats as "allow all")
- `geofence_attendance: "Yes" | "No"` → tells client whether to surface in-fence warnings
- **404** if employee has no branch assigned

### 2.2 `POST /api/attendance/punch-in` — multipart

Fields:
- `selfie` (file, required) — JPG/JPEG/PNG, ≤ 2 MB
- `latitude`, `longitude` (number, required)
- `accuracy_m` (float, optional)
- `address` (string, optional, ≤ 500)
- `client_captured_at` (ISO 8601, required)
- `device_info` (JSON string, optional)

Server logic:
1. Look up employee's branch + geofence
2. Active session exists? → **409 `SESSION_ALREADY_OPEN`**
3. Already completed today's in/out cycle (IST)? → **409 `ALREADY_PUNCHED_TODAY`** (v2 change)
4. Haversine distance → set `inside_geofence` flag (never reject)
5. Save selfie to `storage/app/public/attendance/{YYYY}/{MM}/{employee_id}_{ts}.jpg`
6. Insert punch (`type='in'`, `is_first_of_day` if applicable)
7. Insert session row, link `punch_in_id`

**200**
```json
{
  "status": true,
  "message": "Punch-in recorded.",
  "data": {
    "session_id": 3401,
    "punch_id": 98765,
    "server_time": "2026-04-20T03:35:23.000000Z",
    "is_first_of_day": true,
    "geofence": { "inside": true, "distance_m": 12, "radius_m": 50 }
  }
}
```

**409 SESSION_ALREADY_OPEN**
```json
{
  "status": false,
  "error_code": "SESSION_ALREADY_OPEN",
  "message": "You already have an open session.",
  "data": { "session_id": 3400, "started_at": "..." }
}
```

**409 ALREADY_PUNCHED_TODAY**
```json
{
  "status": false,
  "error_code": "ALREADY_PUNCHED_TODAY",
  "message": "You have already completed today's punch-in and punch-out."
}
```

### 2.3 `POST /api/attendance/punch-out` — multipart

Same fields as punch-in **plus** `session_id` (integer, required).

Server logic:
1. Verify session belongs to employee + status is `active`
2. Compute distance / `inside_geofence`
3. Save selfie
4. Insert punch (`type='out'`, mark this as the only `is_last_of_day=true` for the day)
5. Close session: `ended_at`, `duration_seconds`, `status='closed'`, `punch_out_id`

**200**
```json
{
  "status": true,
  "data": {
    "session_id": 3401,
    "punch_id": 98801,
    "duration_seconds": 28740,
    "ping_count": 14,
    "is_last_of_day": true,
    "geofence": { "inside": true, "distance_m": 20, "radius_m": 50 }
  }
}
```

### 2.4 `POST /api/attendance/location-ping` — JSON

```json
{
  "session_id": 3401,
  "latitude": 18.5743,
  "longitude": 73.7736,
  "accuracy_m": 8.2,
  "address": "Pune HQ",
  "battery_pct": 73,
  "captured_at": "2026-04-20T04:05:00.000000Z"
}
```
- Verify active session owned by employee
- Compute distance, insert ping, increment `session.ping_count`
- **200** `{ "status": true, "data": { "ping_id": 554321 } }`
- **409** if session not active / not owned
- Rate limit: 30/min

### 2.5 `POST /api/attendance/location-ping/batch` — JSON, offline flush

```json
{ "pings": [ { ...same shape as single ping... }, ... ] }
```
- Max **100 pings** per request, `is_queued=true` on each insert
- Per-ping verification: invalid ones go into `rejected[]`, valid ones inserted

**200**
```json
{
  "status": true,
  "data": {
    "accepted": 2,
    "rejected": [{ "index": 2, "reason": "SESSION_NOT_ACTIVE" }],
    "ping_ids": [554322, 554323]
  }
}
```

### 2.6 `GET /api/attendance/today` — employee view

**200**
```json
{
  "status": true,
  "data": {
    "active_session": {
      "session_id": 3401,
      "started_at": "...",
      "ping_count": 14,
      "last_ping": { "latitude": ..., "longitude": ..., "captured_at": "..." }
    },
    "punches": [
      {
        "session_id": 3401,
        "type": "in",
        "punched_at": "...",
        "selfie_url": "https://hrms.mecpl.in/storage/attendance/2026/04/2914_1713600923.jpg",
        "inside_geofence": true,
        "distance_m": 15
      }
    ],
    "total_seconds": 32405
  }
}
```
> **v2:** `session_id` must be present on every punch object so a freshly installed client can fetch the timeline.

### 2.7 `GET /api/attendance/live` — **admin only**

Query: `branch_id` (optional), `limit` (default 100)
- Non-admin → **403**
- **200:** list of active sessions with employee, branch, `started_at`, `ping_count`, `last_ping`

### 2.8 `GET /api/attendance/session/{id}/timeline` — admin or session owner

**200:** `{ session, punch_in, punch_out, pings: [...] }` — full breadcrumb for map render. 403 if neither owner nor admin.

---

## 3. Business Rules

| Rule | Behaviour |
|---|---|
| **Out-of-fence punch** | Accepted, flagged `inside_geofence=0`, `distance_m` populated. **Never rejected.** |
| **Out-of-fence ping** | Always accepted. Flagged for audit only. |
| **Open session conflict** | 409 `SESSION_ALREADY_OPEN` |
| **Already punched today (v2)** | 409 `ALREADY_PUNCHED_TODAY` — IST day boundary |
| **Selfie validation** | `mimes:jpg,jpeg,png`, `max:2048` (2 MB) |
| **Geofence scope** | One per employee, taken from their assigned branch. NULL radius = no enforcement. |
| **Retention** | Pings purged after **180 days**. Punches + selfies kept indefinitely. |
| **Day boundary** | `Asia/Kolkata` (IST), not UTC |
| **Rate limits** | Punch 6/min, ping 30/min, others 60/min — return **429** when exceeded |

---

## 4. Storage & Selfies

- Directory: `storage/app/public/attendance/{YYYY}/{MM}/`
- Filename: `{employee_id}_{unix_timestamp}.jpg`
- Public URL: `https://hrms.mecpl.in/storage/attendance/...` (run `php artisan storage:link`)
- DB stores relative path; API returns full URL

---

## 5. Console / Scheduled Jobs

Create `app/Console/Commands/PurgeOldLocationPings.php`:
```php
DB::table('attendance_location_pings')
  ->where('captured_at', '<', now()->subDays(180))
  ->delete();
```

Schedule daily at 02:30:
```php
$schedule->command('attendance:purge-pings')->dailyAt('02:30');
```

---

## 6. Admin Panel Work

- **Branch geofence config CRUD** — admin form to set `latitude`, `longitude`, `geofence_radius_m` per branch
- **Live attendance dashboard** — polls `/attendance/live` every 30s, plots active employees on a map
- **Session timeline view** — uses `/attendance/session/{id}/timeline` to draw punch-in → pings → punch-out on a map with selfie thumbnails
- **Pending approvals** — out-of-fence punches show a flag; admin can approve / mark as regularisation request (see [laravel-admin-pending-approvals.md](laravel-admin-pending-approvals.md))

---

## 7. Open Items from Pending Docs

### From [laravel-backend-pending.md](laravel-backend-pending.md)

- [ ] **P0 blocker** — populate `latitude`, `longitude`, `geofence_radius_m` on all active branches
- [ ] Confirm `radius_m: null` semantics (no fence = allow all) and decide policy for unconfigured branches
- [ ] Verify response shapes exactly match client parsing (`session_id`, `server_time` ISO format)
- [ ] Ensure both 409 error codes (`SESSION_ALREADY_OPEN`, `ALREADY_PUNCHED_TODAY`) are returned
- [ ] Add `geofence_attendance: "Yes"/"No"` flag to `/me/geofence` response
- [ ] Smoke-test selfie storage path + public URL generation

### From [laravel-backend-changes-v2.md](laravel-backend-changes-v2.md)

- [ ] **Change 1:** add `ALREADY_PUNCHED_TODAY` check to `/attendance/punch-in` (IST day boundary)
- [ ] **Change 2:** add `session_id` to every punch object in `/attendance/today` response
- [ ] **Deploy order:** Change 2 first (additive, safe), then Change 1 after mobile rolls out updated UX

---

## 8. Acceptance Checklist

- [ ] Punch-in inside fence → 200, `inside_geofence=1`, selfie saved, session active
- [ ] Punch-in outside fence → 200, `inside_geofence=0`, `distance_m` populated (NOT rejected)
- [ ] Punch-in with open session → 409 `SESSION_ALREADY_OPEN`
- [ ] Punch-in after completing today → 409 `ALREADY_PUNCHED_TODAY`
- [ ] Single ping on active session → 200, `ping_count` incremented
- [ ] Batch ping with one bad `session_id` → others accepted, bad one in `rejected[]`
- [ ] `/attendance/today` returns `session_id` on every punch
- [ ] `/attendance/live` as admin → 200; as employee → 403
- [ ] `/attendance/session/{id}/timeline` as owner → 200; as stranger → 403
- [ ] Nightly purge deletes pings older than 180 days; punches preserved
- [ ] Rate limits return 429 when exceeded

---

## TL;DR for the Backend Dev

1. **Migrate** four tables (branches alter + 3 new).
2. **Build 8 endpoints** — `/me/geofence`, punch-in/out, location-ping (single + batch), `/today`, `/live`, `/session/{id}/timeline`.
3. **Selfies** stored under `storage/app/public/attendance/{YYYY}/{MM}/` — multipart upload, 2 MB cap.
4. **Out-of-fence is never rejected** — backend just flags `inside_geofence=0`.
5. **Two 409 conflicts** to implement: `SESSION_ALREADY_OPEN` and `ALREADY_PUNCHED_TODAY`.
6. **Scheduled job** purges pings > 180 days nightly at 02:30.
7. **Admin** gets live-attendance polling, session-timeline map, branch-geofence CRUD, out-of-fence approval flow.
8. **All identifiers, error codes, and JSON field names** are fixed by the mobile contract — do not rename.
