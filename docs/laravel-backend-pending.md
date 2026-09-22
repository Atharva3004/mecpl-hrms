# Laravel Backend — Pending Items for Flutter Integration

**As of:** 2026-04-21
**For:** Laravel developer
**Context:** All 8 geofencing + attendance routes are defined and reachable. The Flutter client now calls `/api/me/geofence` automatically after login, and the remaining endpoints need to be verified against the contract below before the mobile release.

This document lists **only what is pending or needs verification**. For the full implementation reference, see [laravel-backend-implementation.md](./laravel-backend-implementation.md).

---

## 1. Blockers (must be resolved before mobile release)

### 1.1 Populate branch geofence columns — **P0**

Current `GET /api/me/geofence` response for employees on HEAD OFFICE:

```json
{
  "status": true,
  "data": {
    "branch_id": 16,
    "branch_name": "HEAD OFFICE",
    "latitude": null,
    "longitude": null,
    "radius_m": null
  }
}
```

With `latitude` / `longitude` / `radius_m` all `NULL`, **geofence enforcement is effectively disabled** on both the server and the client. Every punch from any location will record as `inside_geofence=1`.

**Action required:**
- [ ] Populate `latitude`, `longitude`, `radius_m` on the `branches` table for all active branches (at minimum HEAD OFFICE / branch_id 16).
- [ ] Decide: is `NULL` a valid "no geofence" state (allow punches anywhere) or should unconfigured branches block punches? The Flutter client currently treats `NULL` as "no fence → allow". Confirm this matches backend business rules.
- [ ] Add an admin UI or seeder so the ops team can set these per branch without a developer.

---

## 2. Response contract verification

The Flutter client parses responses with the shapes below. Please verify each controller returns exactly these fields and types. Any mismatch will silently fail parsing in the client.

### 2.1 `POST /api/attendance/punch-in` — success (201)

Expected keys the client reads:

```json
{
  "status": true,
  "data": {
    "session_id": 123,
    "server_time": "2026-04-21T10:30:00.000000Z",
    "geofence": {
      "inside": true,
      "distance_m": 42.7,
      "radius_m": 150
    }
  }
}
```

Client code that consumes this: [attendance_provider.dart:575-599](../lib/providers/attendance_provider.dart#L575).

- [ ] Verify `session_id` is a numeric integer (client calls `.toInt()`).
- [ ] Verify `server_time` is ISO-8601 parseable by `DateTime.parse`.
- [ ] Verify the `geofence` block is present even when the fence is not enforced (send `inside: true, distance_m: 0, radius_m: null` in that case).

### 2.2 `POST /api/attendance/punch-in` — conflict (409)

If the employee already has an open session, return **HTTP 409** (not 200 / not 422). The client has dedicated handling for 409:

```json
{
  "status": false,
  "message": "You already have an open session.",
  "data": {
    "active_session_id": 123,
    "opened_at": "2026-04-21T09:15:00.000000Z"
  }
}
```

- [ ] Confirm 409 is returned on duplicate open-session attempts.

### 2.3 `POST /api/attendance/punch-out`

Same shape as punch-in success. The client sends `session_id` as a multipart text field; validate it matches the authenticated employee's open session.

### 2.4 `POST /api/attendance/location-ping` — success (200)

Client only checks the HTTP status; body can be minimal (`{"status": true}`).

- [ ] Return 200 on accepted ping, 422 on invalid coordinates, 409 if `session_id` doesn't belong to the employee or is already closed.

### 2.5 `POST /api/attendance/location-ping/batch` — success (200)

- [ ] Accept up to 100 pings per request under key `"pings"` (array of ping objects with the same fields as single-ping).
- [ ] Return 200 with a summary (`accepted_count`, `rejected_count`) so the client knows how much of the offline queue was consumed.

### 2.6 `GET /api/attendance/today`

**Currently not called by the Flutter UI, but the endpoint is required for session recovery after app restart** (planned in next sprint). Expected shape:

```json
{
  "status": true,
  "data": {
    "active_session": {
      "session_id": 123,
      "opened_at": "2026-04-21T09:15:00.000000Z"
    },
    "punches": [
      {
        "type": "in",
        "timestamp": "2026-04-21T09:15:00.000000Z",
        "latitude": 19.0760,
        "longitude": 72.8777,
        "inside_geofence": true,
        "distance_m": 42.7
      }
    ]
  }
}
```

- [ ] Return `active_session: null` (not missing) when there is no open session.
- [ ] Include today's punches in chronological order.

### 2.7 `GET /api/attendance/session/{id}/timeline`

**Currently not called by the Flutter UI.** When the session-timeline screen is built next sprint, expected shape:

```json
{
  "status": true,
  "data": {
    "session": {
      "id": 123,
      "opened_at": "...",
      "closed_at": "..."
    },
    "punch_in": { "latitude": 19.0760, "longitude": 72.8777, "selfie_url": "...", "address": "..." },
    "punch_out": { "latitude": 19.0770, "longitude": 72.8780, "selfie_url": "...", "address": "..." },
    "pings": [
      { "captured_at": "...", "latitude": 19.0762, "longitude": 72.8779, "accuracy_m": 15.0 }
    ]
  }
}
```

- [ ] Authorize: session owner OR admin can view. Return 403 otherwise.

### 2.8 `GET /api/attendance/live` (admin)

Already connected by the client in `LiveAttendanceScreen`. Verify it's reachable for admin users and returns employee locations for currently-open sessions.

---

## 3. Auth & headers

Client sends every request with:

```
Authorization: Bearer <sanctum_token>
Accept: application/json
X-API-Key: <app-wide API key>
X-Requested-With: XMLHttpRequest
```

- [ ] Confirm `X-API-Key` is either validated or safely ignored (not rejected as "unexpected header").
- [ ] Confirm Sanctum tokens issued by `/api/check_login_api` have the scopes needed for all `/attendance/*` routes.

---

## 4. Error body shape

The client reads `data['message']` on non-2xx responses. Please ensure all error responses use:

```json
{ "status": false, "message": "Human-readable reason" }
```

This includes throttled (429), validation (422), unauthorized (401/403), and conflict (409) responses.

- [ ] Confirm Laravel's default 422 validation envelope is transformed to this shape (or at minimum has a top-level `message` key).
- [ ] Confirm 429 responses from `throttle:6,1` and `throttle:30,1` include a `message` key.

---

## 5. Selfie storage

- [ ] Confirm `selfie` multipart file is stored on disk and a URL (or path) is persisted on the punch row so the admin UI and `/session/{id}/timeline` can display them.
- [ ] Confirm accepted mime types and max file size (client currently sends JPG, typically < 500 KB).

---

## 6. Verification checklist (run before handing back)

- [ ] `GET /api/me/geofence` returns populated lat/lng/radius for at least HEAD OFFICE
- [ ] `POST /api/attendance/punch-in` returns 201 with `session_id`, `server_time`, `geofence` block
- [ ] `POST /api/attendance/punch-in` returns 409 when session already open
- [ ] `POST /api/attendance/location-ping` accepts the single-ping JSON body
- [ ] `POST /api/attendance/location-ping/batch` accepts `{"pings": [...]}` up to 100 items
- [ ] `POST /api/attendance/punch-out` closes the session and returns the same success envelope
- [ ] `GET /api/attendance/today` returns `active_session` (or `null`) plus today's punches
- [ ] `GET /api/attendance/session/{id}/timeline` returns the full breadcrumb
- [ ] `GET /api/attendance/live` is admin-gated (403 for non-admins)
- [ ] All error responses have `{"status": false, "message": "..."}` shape
- [ ] Throttle returns 429 with a readable message (not a stack trace)

---

## 7. Contact

For questions on the expected client behavior or any of the JSON shapes above, contact the mobile team. The canonical client-side parsing logic lives in:

- `lib/services/api_service.dart` — all HTTP calls
- `lib/providers/attendance_provider.dart` — punch flow + response parsing
- `lib/repositories/geofence_repository.dart` — `/me/geofence` parsing and caching
