# Laravel Backend Changes — Round 2

**For:** Laravel developer
**Date:** 2026-04-22
**Context:** The Flutter client is rolling out four new behaviors for geofence-enabled employees (Cases 1–4 below). Most of the work is client-side. This document lists **only the backend changes required** to support them. The reference for existing endpoints is [geofencing-api-reference.md](./geofencing-api-reference.md).

---

## Business rules (what's changing)

1. **Case 1** — Only employees with `geofence_attendance = "Yes"` on their branch see the punch-in/out button. Non-geofence employees continue using the existing (non-geofence) attendance flow untouched.
2. **Case 2** — Geofence-enabled employees get **one punch-in and one punch-out per calendar day**. After they punch out, the punch-in button stays hidden until the next calendar day (IST).
3. **Case 3** — Background location tracking must continue even after the OS kills the app. Handled fully on the client (new plugin + permissions). No backend changes.
4. **Case 4** — The "today's route" graph must survive a fresh install / new device. Today's pings are pulled from the backend instead of local cache.

---

## Required backend changes

### Change 1 — Enforce one-punch-per-day on `POST /api/attendance/punch-in` (Case 2)

**Current behavior:** rejects only when a session is already open (`409 SESSION_ALREADY_OPEN`). Allows multiple in/out pairs per day.

**New behavior:** also reject when the employee has **already punched out once today** (same calendar day in IST, `Asia/Kolkata`). Return **HTTP 409** with a new error code.

**New error response:**
```json
{
    "status": false,
    "error_code": "ALREADY_PUNCHED_TODAY",
    "message": "You have already completed today's punch-in and punch-out."
}
```

**Server-side check (pseudocode):**
```
$today = Carbon::now('Asia/Kolkata')->startOfDay();
$alreadyCompleted = AttendanceSession::where('employee_id', $emp->id)
    ->where('status', 'closed')
    ->whereDate('started_at', $today)
    ->exists();

if ($alreadyCompleted) {
    return response()->json([
        'status' => false,
        'error_code' => 'ALREADY_PUNCHED_TODAY',
        'message' => 'You have already completed today\'s punch-in and punch-out.',
    ], 409);
}
```

**Notes:**
- Keep the existing `SESSION_ALREADY_OPEN` 409 for the case where a session is still open — the client distinguishes between the two via `error_code`.
- Day boundary is **local calendar day in IST** (`Asia/Kolkata`), not UTC day.
- This check applies **only** to branches where `geofence_attendance = "Yes"`. For non-geofence branches, the behavior is unchanged (if your backend even supports it — the client won't call this endpoint for non-geofence users anyway).

**Checklist:**
- [ ] Add the "already punched today" check to `AttendancePunchController@punchIn`.
- [ ] Return 409 with `error_code: ALREADY_PUNCHED_TODAY` when triggered.
- [ ] Use `Asia/Kolkata` for the day-boundary comparison.

---

### Change 2 — Include `session_id` in `GET /api/attendance/today` punches array (Case 4)

**Current response:**
```json
{
    "status": true,
    "data": {
        "active_session": null,
        "punches": [
            { "type": "in",  "punched_at": "...", "selfie_url": "...", "inside_geofence": true, "distance_m": 15 },
            { "type": "out", "punched_at": "...", "selfie_url": "...", "inside_geofence": true, "distance_m": 20 }
        ],
        "total_seconds": 32405
    }
}
```

**New response (add `session_id` to each punch):**
```json
{
    "status": true,
    "data": {
        "active_session": null,
        "punches": [
            { "session_id": 1, "type": "in",  "punched_at": "...", "selfie_url": "...", "inside_geofence": true, "distance_m": 15 },
            { "session_id": 1, "type": "out", "punched_at": "...", "selfie_url": "...", "inside_geofence": true, "distance_m": 20 }
        ],
        "total_seconds": 32405
    }
}
```

**Why:** the client needs to call `GET /api/attendance/session/{id}/timeline` to plot today's route on a fresh install / new device. Without `session_id` in the punches array, the client has no way to discover today's session when there's no active session.

**Checklist:**
- [ ] Add `session_id` to each punch object returned by `AttendanceViewController@today`.
- [ ] Works for both active and closed sessions.
- [ ] No change to any other field.

---

## No change needed (just confirming)

### `/api/me/geofence`
- Current response already returns `geofence_attendance: "Yes" | "No"`. The Flutter client reads this on login and gates the UI.

### `/api/attendance/location-ping` and `/api/attendance/location-ping/batch`
- Unchanged. The client's new background-tracking plugin will hit these on the same 30-minute interval. Keep the 30/min rate limit.

### `/api/attendance/session/{id}/timeline`
- Unchanged. The client will use this to plot today's graph after Change 2 is deployed.

### `/api/attendance/punch-out`
- Unchanged. Still rejects with 409 if the session is not active.

---

## Deployment order (recommended)

1. Deploy **Change 2** first (add `session_id` to punches). It's additive and risk-free; the client already tolerates the old shape.
2. Deploy **Change 1** (one-punch-per-day enforcement) after the mobile release ships. If you deploy it before the client is updated, users on old app versions will see a generic 409 error when trying to punch in a second time — not a bug, just a UX regression.

---

## Verification checklist (run after changes are live)

- [ ] `GET /api/attendance/today` now returns `session_id` inside each punch object.
- [ ] `POST /api/attendance/punch-in` returns `409` with `error_code: ALREADY_PUNCHED_TODAY` when the employee has already completed today's cycle.
- [ ] `POST /api/attendance/punch-in` still returns `409` with `error_code: SESSION_ALREADY_OPEN` when a session is already active (unchanged behavior).
- [ ] The "already punched today" check uses IST day boundaries (not UTC).
- [ ] Non-geofence branches are unaffected — their employees don't hit `/attendance/today` or `/attendance/punch-in` at all.

---

## Contact

Questions on expected JSON shapes or client parsing logic — ping the mobile team. Relevant client files:
- `lib/providers/attendance_provider.dart` — punch-in/out flow + `/attendance/today` parser
- `lib/repositories/geofence_repository.dart` — `/me/geofence` and `geofence_attendance` flag
