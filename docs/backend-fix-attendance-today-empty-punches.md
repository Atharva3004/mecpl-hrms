# Backend Fix Required — `/attendance/today` returns `punches: []`

**From:** Flutter developer
**To:** Backend developer
**Date:** 2026-08-04
**Severity:** High — geofence employees cannot see their own punch-in / punch-out
**Related:** `attendance-history-flutter-feedback.md` Issue 1 (reported 2026-06-03, still open)

---

## 1. The bug in one line

`GET /api/attendance/today` **always returns an empty `punches[]` array**, even when
the employee has punched in and out that same day.

---

## 2. Evidence — live response from a device today

```json
{
  "status": true,
  "data": {
    "active_session": { ... "...:49+05:30" },
    "punches": [],
    "total_seconds": 0
  }
}
```

Note the contradiction: the response contains an **`active_session`**, which can only
exist because a punch-in row was written. Yet `punches[]` is empty. The punch rows are
in the database — they are just not being returned.

This is the identical payload reported on 2026-06-03 for user 77 (`session_id: 2`) and
user 1822 (`session_id: 7`). It was never fixed.

---

## 3. Why this breaks the app

For a geofence employee, `punches[]` is the **only** source of punch times. The legacy
biometric endpoint `/today-employee-attendance` is empty for them, because app punches
write to the session tables, not the biometric aggregate.

So with `punches: []`:

| Employee action | What the dashboard shows | Why |
|---|---|---|
| Punches in | Punch In time appears | Only because the app derives it from `active_session.started_at` — **not** from a punch record |
| Punches out | Punch In **and** Punch Out both vanish → `--:--` | Session closes → `active_session: null`. With `punches[]` also empty, the app has zero data left |
| Any refresh / app restart | `--:--` | Same as above |

Work hours also stay at `0.00` because `total_seconds` is 0.

**This is what the employee's screenshot shows.** He punched in and out correctly; the
API simply does not report it back.

---

## 4. What to fix

Return the actual punch rows for the current IST calendar day.

### Required response shape

Already specified in `geofencing-api-reference.md` §`GET /api/attendance/today`:

```json
{
  "status": true,
  "data": {
    "active_session": null,
    "punches": [
      {
        "session_id": 42,
        "type": "in",
        "punched_at": "2026-08-04T09:00:05+05:30",
        "latitude": 18.5743404,
        "longitude": 73.7736299,
        "selfie_url": "https://hrms.mecpl.in/storage/attendance/2026/08/123_1754280005.jpg",
        "inside_geofence": true,
        "distance_m": 15
      },
      {
        "session_id": 42,
        "type": "out",
        "punched_at": "2026-08-04T18:00:10+05:30",
        "latitude": 18.5743404,
        "longitude": 73.7736299,
        "selfie_url": "https://hrms.mecpl.in/storage/attendance/2026/08/123_1754312410.jpg",
        "inside_geofence": true,
        "distance_m": 20
      }
    ],
    "total_seconds": 32405
  }
}
```

### Field requirements

| Field | Required | Notes |
|---|---|---|
| `session_id` | **Yes** | The app groups punches by session and uses this to filter out cross-midnight sessions. Missing → punches may be dropped. |
| `type` | **Yes** | `"in"` or `"out"`. Must contain the substring `in` / `out` — `"I"` / `"O"` will **not** parse. |
| `punched_at` | **Yes** | ISO-8601 **with `+05:30` offset**, as you already do elsewhere. Do not emit a `Z` suffix on IST wall-clock times. |
| `latitude` / `longitude` | **Yes** | The app **drops any punch without coordinates** — it cannot plot or list it. This is the single most common reason a punch disappears. |
| `selfie_url` | Yes when one exists | Full absolute URL. `null` is acceptable if no image. |
| `inside_geofence` | Yes | Boolean. |
| `distance_m` | Optional | App computes locally if absent or 0. |

Ordering: ascending by `punched_at`. Include **both** punches of a closed session.

### `total_seconds`

Must be the sum of all **closed** sessions for the day. Currently returns 0 even after a
punch-out. Open sessions contributing 0 is fine and expected.

---

## 5. Likely root cause — where to look

The punch rows exist (the session proves it), so this is a query/serialisation problem,
not a write problem. Check, in order:

1. **The day filter.** Is `punches` filtered on a `attendance_date` / `DATE(punched_at)`
   column that is never populated, or compared in UTC instead of IST? A UTC-vs-IST
   comparison silently excludes everything after 18:30 IST.
2. **The join condition.** Is the punch query scoped to *closed* sessions only
   (`whereNotNull('ended_at')`), or to `active_session` only? Either way the other half
   disappears.
3. **The eager-load.** If it's `$session->punches` on a relation that was never loaded
   (or a `with()` that got dropped), the collection serialises as `[]` instead of erroring.
4. **The resource/transformer.** Confirm the API Resource for `punches` isn't filtering
   on a column that is null in production (e.g. `where('is_valid', 1)`).

Fastest confirmation: run the query the endpoint uses directly against the punch table
for the affected `emp_id` and today's date, and compare the row count to what the JSON
returns.

---

## 6. Acceptance tests

Please verify all four before closing:

1. **Punched in, not out** → `active_session` present **and** `punches[]` contains exactly
   one `type: "in"` entry with lat/lng.
2. **Punched in and out** → `active_session: null`, `punches[]` contains **both** entries,
   `total_seconds` > 0.
3. **Late punch** — punch in at 19:00 IST → `punched_at` comes back as
   `"...T19:00:00+05:30"`, not `"...T19:00:00Z"`, and the punch is attributed to that same
   calendar day.
4. **Nothing punched yet today** → `active_session: null`, `punches: []`, `total_seconds: 0`.
   (This is the only case where an empty array is correct.)

---

## 7. Same root cause — please fix together

`GET /api/attendance/history?date=YYYY-MM-DD` omits **active/open sessions** entirely, so
any day with an unclosed session renders blank in the app. Reported as Issue 1 in
`attendance-history-flutter-feedback.md`; the spec promised open sessions would be
included with `ended_at: null`, `status: "active"`. Still not happening.

If both endpoints share the punch-fetching code, one fix likely covers both — worth
checking before doing them separately.

---

## 8. What the app already does (no backend dependency)

Shipped as a mitigation so the employee is not blocked while this is fixed:

- Punch times are cached on-device and survive refresh and app restart.
- An empty `punches[]` no longer erases times the app already knows.

**This is device-local only.** It does not fix work-hours totals, punch history with
selfies, viewing punches on a different device or after a reinstall, or anything on the
HR/reporting side. Those all need the API fix above.
