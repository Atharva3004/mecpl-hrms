# Backend Response — Geofence Action List

**Date:** 2026-08-29  
**From:** Backend team  
**To:** Mobile (Flutter) team  
**Re:** `docs/backend-action-list-geofence.md` — review and fixes

---

## 0. Summary

We reviewed all 8 items. **4 needed real fixes** (now done), **4 were already working** — your testing may have hit a different issue than what you diagnosed. Details below.

| ID | Status | Notes |
|---|---|---|
| **B1** | **Partially fixed** | `/today` was missing GPS fields — fixed. `/history` already had `latitude`/`longitude`. |
| **B2** | **Partially fixed** | `/history` was missing `session_id` — fixed. `/today` already had it. |
| **B3** | **Fixed** | `hasGeofence()` now checks `> 0` instead of `!== null` |
| **B4** | **Already correct** | App timezone is `Asia/Kolkata` — no 5.5hr window exists |
| **B5** | **Already correct** | Models already have `float`/`integer` casts |
| **B6** | **Already correct** | `/history` already returns `total_seconds` |
| **B7** | Audit needed | Run the SQL queries below |
| **B8** | **Fixed** | `lockForUpdate()` inside transaction |

---

## 1. B1 — GPS fields in punches

### What was actually wrong

- **`/today`** was missing `latitude`, `longitude`, `accuracy_m`, `address` in `punches[]` — **fixed now**.
- **`/history`** already had `latitude` and `longitude` in `punches[]`. We added the missing `accuracy_m` and `address` fields.

### What's there now (both endpoints)

```json
"punches": [
    {
        "session_id": 142,
        "type": "in",
        "punched_at": "2026-08-29T09:30:15+05:30",
        "latitude": 19.076,
        "longitude": 72.8777,
        "accuracy_m": 15.5,
        "address": "Andheri East, Mumbai",
        "selfie_url": "https://.../storage/attendance/2026/08/123_1724920215.jpg",
        "inside_geofence": true,
        "distance_m": 45
    }
]
```

### Why you might have seen empty data

If your parser was checking `/today` and discarding rows without `latitude`/`longitude`, that explains "Waiting for today's punch-in..." after a successful punch. But `/history` was already returning coordinates — if that was also failing, the issue on your side may be something else (e.g., parsing `session_id` from the wrong place, or the date mismatch you described in B4 — which doesn't actually exist, see below).

---

## 2. B2 — `session_id` in punches

### What was actually wrong

- **`/today`** already had `session_id` in `punches[]` — it was there from the start.
- **`/history`** was missing `session_id` — **fixed now**.

### Your "pings not showing after punch-out" issue

You said:
> After punch-out, `active_session` becomes `null`, and `punches[].session_id` doesn't exist on `/today`, so there's no recovery path.

**`session_id` was already on `/today` punches.** Your app code at:
```dart
final sessionId = att.todaySessionId;
if (sessionId == null) { return; }
```

...suggests you're reading `session_id` from somewhere other than `punches[]`. Please double-check your parsing — the field was always there in the `/today` response. The silent discard with no error message is likely a client-side parsing issue.

---

## 3. B3 — `hasGeofence()` NULL→0 cast — FIXED

Changed from:
```php
$this->geofence_radius_m !== null   // always true because integer cast turns NULL to 0
```
To:
```php
$this->geofence_radius_m > 0        // correctly handles both NULL (cast to 0) and explicit 0
```

### Historical data backfill

Please run this query and share the result:
```sql
SELECT COUNT(*) AS bad_rows
FROM attendance_punches p
JOIN branches b ON b.id = p.branch_id
WHERE p.inside_geofence = 0
  AND (b.latitude IS NULL OR b.longitude IS NULL
       OR b.geofence_radius_m IS NULL OR b.geofence_radius_m = 0);
```

If there are affected rows, we'll correct them with:
```sql
UPDATE attendance_punches p
JOIN branches b ON b.id = p.branch_id
SET p.inside_geofence = 1, p.distance_m = NULL
WHERE p.inside_geofence = 0
  AND (b.latitude IS NULL OR b.longitude IS NULL
       OR b.geofence_radius_m IS NULL OR b.geofence_radius_m = 0);
```

---

## 4. B4 — IST vs UTC — ALREADY CORRECT

Your analysis assumed the server timezone is UTC. It's not.

**`config/app.php` line 72:**
```php
'timezone' => 'Asia/Kolkata',
```

This means `now()` returns IST everywhere. Both:
- `Carbon::now('Asia/Kolkata')->toDateString()` (explicit IST in punchIn)
- `now()->toDateString()` (in today/history)

...produce the same IST date. **There is no 5.5-hour disagreement window.**

### `client_captured_at` format

Either format works:
- UTC with `Z`: `2026-08-29T04:00:15.000Z`
- IST with offset: `2026-08-29T09:30:15.000+05:30`

We store it as-is via Carbon, which handles both. **Keep sending whichever you prefer** — no change needed.

### Test it yourself

At 07:00 IST, punch in, then call `/attendance/today`. It will return today's data correctly. It always has.

---

## 5. B5 — Numbers as strings — ALREADY CORRECT

All models already have proper casts:

**AttendancePunchModel:**
```php
'latitude'  => 'float', 'longitude' => 'float', 'accuracy_m' => 'float',
'distance_m' => 'integer', 'inside_geofence' => 'boolean'
```

**AttendanceLocationPingModel:**
```php
'latitude'  => 'float', 'longitude' => 'float', 'accuracy_m' => 'float',
'distance_m' => 'integer', 'battery_pct' => 'integer', 'inside_geofence' => 'boolean'
```

**BranchModel:**
```php
'latitude' => 'float', 'longitude' => 'float', 'geofence_radius_m' => 'integer'
```

`jq '.data.punches[0].latitude | type'` will print `"number"`.

---

## 6. B6 — `/history` `total_seconds` — ALREADY EXISTS

The response already includes it:
```php
return response()->json([
    'status' => true,
    'data'   => [
        'date'          => $date,
        'total_seconds' => $totalSeconds,   // ← line 181
        'sessions'      => $sessionData,
    ],
]);
```

Sum of `duration_seconds` across closed sessions for the day, same as `/today`.

---

## 7. B7 — Branch geofence data audit

**Action for Omkar:** Run these queries and share results with the Flutter team:

```sql
-- Summary
SELECT
  COUNT(*) AS total_branches,
  SUM(latitude IS NOT NULL AND longitude IS NOT NULL
      AND geofence_radius_m IS NOT NULL AND geofence_radius_m > 0) AS fully_configured,
  SUM(latitude IS NULL OR longitude IS NULL) AS missing_coords,
  SUM(geofence_radius_m IS NULL OR geofence_radius_m = 0) AS missing_radius
FROM branches;

-- Per-branch detail
SELECT id, branch_name, latitude, longitude, geofence_radius_m
FROM branches
ORDER BY branch_name;
```

---

## 8. B8 — Race condition — FIXED

The active-session check and completed-session check are now **inside** the DB transaction with `lockForUpdate()`:

```php
$result = DB::transaction(function () use (...) {
    $existing = AttendanceSessionModel::where('employee_id', $employee->id)
        ->where('status', 'active')
        ->lockForUpdate()    // ← prevents concurrent reads
        ->first();
    if ($existing) {
        return ['error' => 'SESSION_ALREADY_OPEN', ...];
    }

    $completedSession = AttendanceSessionModel::where(...)
        ->lockForUpdate()
        ->first();
    if ($completedSession) {
        return ['error' => 'ALREADY_PUNCHED_TODAY', ...];
    }

    // ... create session + punch ...
});
```

Two concurrent punch-in requests will now serialize — the second will see the session created by the first.

We did **not** add the DB-level unique constraint yet. The `lockForUpdate()` is sufficient for now. We'll add the constraint in a future migration after auditing for existing duplicates.

---

## 9. Confirmations C1–C5

| ID | Answer | Detail |
|---|---|---|
| **C1** | **Yes** | `/location-ping` and `/location-ping/batch` accept `Content-Type: application/json` when no selfie is attached. Laravel's `$request->input()` reads from both JSON and form data. Keep posting JSON — no change needed. |
| **C2** | **Ignored** | Extra `is_queued` key in the pings array is silently ignored. Laravel only reads fields it explicitly asks for. No 422. You can keep sending it or drop it — either way is fine. |
| **C3** | **Yes** | Session owner gets 200 on `/attendance/session/{id}/timeline`. The check is: `if ($session->employee_id !== $user->id && !$isAdmin)` — owners pass. |
| **C4** | **Yes** | `battery_pct: null` is accepted. Validation rule is `nullable|integer|between:0,100`. Null passes the nullable check. |
| **C5** | **Frozen, but note the key name** | The error key is **`error_code`**, not `code`. Example: `{"error_code": "SESSION_ALREADY_OPEN", ...}`. Please parse `error_code` in your app. The shape of `/me/geofence` and all other responses is stable. |

### Diagnostic

Run this and share:
```sql
SELECT COUNT(*) AS pings_last_24h
FROM attendance_location_pings
WHERE captured_at > NOW() - INTERVAL 1 DAY;
```

If 0 rows → pings aren't arriving (likely your background-permission fix will resolve it).
If rows exist → pings are stored and the display issue is client-side parsing.

---

## 10. Important: `error_code` vs `code`

Your doc (§12) says:
> Read `code` as well as `error_code` on 409s

Our responses use **`error_code`** consistently:
```json
{
    "status": false,
    "error_code": "SESSION_ALREADY_OPEN",
    "message": "You already have an open session."
}
```

Please use `error_code` as the primary key. We will not rename it.

---

## Files Changed

| File | Change |
|------|--------|
| `app/Http/Controllers/Api/AttendanceViewController.php` | Added `latitude`, `longitude`, `accuracy_m`, `address` to `/today` punches; added `session_id`, `accuracy_m`, `address` to `/history` punches |
| `app/Models/BranchModel.php` | `hasGeofence()` now checks `> 0` instead of `!== null` |
| `app/Http/Controllers/Api/AttendancePunchController.php` | Moved session checks inside DB transaction with `lockForUpdate()` |
