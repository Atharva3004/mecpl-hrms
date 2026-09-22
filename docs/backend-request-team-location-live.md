# Backend request — date support on `GET /api/attendance/live`

> ## ⛔ SUPERSEDED — do not implement
>
> Backend answered this with something better: a purpose-built endpoint,
> **`GET /api/attendance/geofence-live`**, documented in
> **`docs/geofence-live-dashboard-api.md`**. It carries everything asked for
> below (`date`, closed sessions, punch-out, status, department) *plus* the
> branch fences and summary counts in the same response, and adds a route-trail
> endpoint. The app now calls it.
>
> Kept only as the record of what was asked and why. Read
> `geofence-live-dashboard-api.md` for the live contract.

**Status:** superseded 2026-09-19 by `/attendance/geofence-live`
**Raised:** 2026-09-19
**Consumer:** `lib/screens/tracking/team_location_map_screen.dart` (Team Location, director-only)
**Scope:** one existing endpoint gains four things. No new route, no new table.

---

## 1. Why

The Team Location screen puts every employee's latest GPS ping on a map for a
chosen day. It is wired to `GET /api/attendance/live` today and works for
*right now*. Two of its three controls cannot function against that endpoint
as it stands:

| Control | Needs | Endpoint has |
|---|---|---|
| **Active** chip | open sessions | ✅ |
| **Completed** chip | closed sessions for the day | ❌ endpoint returns only open ones |
| **Today** date picker | `?date=` | ❌ no date parameter at all |

`GET /api/attendance/history?date=&user_id=` is date-scoped but returns **one
employee per call** — it cannot back a team map without N requests.

So the app currently refuses past dates with an explicit notice rather than
showing an empty map, and the Completed chip reads 0 all day. Both clear up
the moment this lands; no client release is required for the date parameter
beyond removing that guard.

---

## 2. What we need

### 2.1 New query parameter

| Param | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `date` | `YYYY-MM-DD` | no | today (IST) | Return **all** sessions whose IST calendar date matches, open *and* closed |

Existing `branch_id` and `limit` keep their current behaviour. The app sends
neither `branch_id` (it shows every site at once) nor a `date` yet; it sends
`limit=500`.

**Behaviour change:** with `date` present the `status = 'active'` filter must
be dropped. Without `date`, today's date is assumed — which means the default
response changes from "open sessions" to "all of today's sessions". If that
breaks the Laravel admin dashboard, keep the old behaviour when `date` is
absent and treat an explicit `date=<today>` as the new one. Either is fine for
us; say which you picked.

### 2.2 Two things to pin down

**Which timestamp decides the day.** A session that opens 23:50 and closes
02:10 the next morning belongs to whichever date you say it does. We want it
filed under its **`started_at`** date (the day the person punched in), so a
night shift appears once, on the day it began. Please confirm — if you file it
by `ended_at` instead, the map will show people on the wrong day and neither
side will notice for weeks.

**One row per session, not per employee.** If someone punches out for lunch
and back in, that is two sessions and we want two rows, each with its own
`last_ping`. The app keys rows on `session_id` precisely for this. Do not
collapse them to one row per employee — we would lose the morning's location.

An employee with no session that day simply does not appear. That is correct;
this screen maps attendance, not the roster.

### 2.3 Three new fields per row

| Field | Type | Notes |
|---|---|---|
| `punch_out` | ISO-8601 `+05:30`, or `null` | `null` while the session is open |
| `status` | `"active"` \| `"completed"` \| `"force_closed"` | The app treats anything other than `active` as finished |
| `employee.designation` | string | Shown under the name; `""` is acceptable |

`last_ping` keeps its current meaning — the **latest** ping of *that session*
(`latestOfMany('captured_at')`), `null` when the session has no ping yet. The
app counts those rows separately and reports "N not on the map"; it does not
drop them.

### 2.4 Response shape

Unchanged envelope, three fields added (marked `NEW`):

```json
{
  "status": true,
  "data": [
    {
      "session_id": 142,
      "status": "completed",                                  // NEW
      "employee": {
        "id": 123,
        "emp_name": "Rajesh Kumar",
        "emp_code": "EMP001",
        "designation": "Project Director"                     // NEW
      },
      "branch": { "id": 5, "branch_name": "Mumbai Office" },
      "started_at": "2026-09-19T08:47:00+05:30",
      "punch_out":  "2026-09-19T17:52:00+05:30",              // NEW (null if open)
      "ping_count": 34,
      "last_ping": {
        "latitude": 19.0761,
        "longitude": 72.8778,
        "inside_geofence": true,
        "captured_at": "2026-09-19T17:50:00+05:30"
      }
    }
  ]
}
```

Keep `data` a bare array. Keep `status: true` as the envelope key (not
`success`). Errors stay `{status: false, error_code, message}`.

---

## 3. Key names the client accepts

`_LiveEmployee.fromJson` reads both spellings, so you do not have to rename
anything that already ships:

| Meaning | Accepted keys (first match wins) |
|---|---|
| Employee name | `employee.name`, then `employee.emp_name` |
| Session start | `punch_in`, then `started_at` |
| Branch name | `branch.name`, then `branch.branch_name` |
| Session key | `id`, then `session_id` |

`latitude` / `longitude` are parsed through `double.tryParse`, so Laravel's
`decimal`-as-string will not break the map — but real JSON numbers are
preferred, per the guide's own data-type appendix.

If `status` is absent the client falls back to "no `punch_out` ⇒ active".
That is correct for a live-only feed and **wrong for a past date**, which is
exactly why `status` is on this list.

---

## 4. Auth and limits

- Admin only, as today. Non-admin ⇒ **403**. The app surfaces the message.
- `Authorization: Bearer <sanctum token>` plus `X-API-Key`, as every other
  geofence call.
- The app polls every **45 s**, and stops polling entirely for a past date
  (settled history, identical payload). With `limit=500` and ~100 employees
  that is one query per poll per director.
- Please keep the eager-loaded `latestPing()` relation — a date-filtered query
  over a full day's sessions is where an N+1 would actually hurt.

---

## 5. Acceptance

With `date=<a past working day>`:

1. Response lists **every** session for that day, closed ones included.
2. Each closed row carries `punch_out` and `status: "completed"`.
3. Each row carries `employee.designation`.
4. `last_ping` is that session's final ping — so the map shows where each
   person **ended** the day, not where they are now.
5. `date=<a future day>` returns `data: []`, not an error.
6. An employee with two sessions that day appears as two rows with
   different `session_id` values.

Then in the app: delete the `!_isToday` guard in `_loadSnapshot`, pass
`date: _date` through `ApiService.getLiveAttendance`, and the Completed chip
and date picker both come alive with no other change.

---

## 6. Related

- `docs/geofence-module-guide.md` §3.9 — current `/attendance/live` contract
- `docs/backend-dev-tasks-geofence-geotagging.md` §2.7 — where it was specced
- `docs/geofence-contract-gap-analysis.md` — earlier round of contract drift
