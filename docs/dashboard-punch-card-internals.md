# Dashboard Punch Card — How It Works

The "Punch Card" is the white rounded card that floats over the red curved header at the top of the Dashboard. It shows today's attendance status at a glance and lets the user punch in/out with a single tap. This doc traces exactly what it shows, where every value comes from, when those values get fetched, and what happens when the user taps it.

**Source file:** [`lib/screens/dashboard/dashboard_screen.dart`](../lib/screens/dashboard/dashboard_screen.dart) (around line 314 onwards, "Overlapping Punch Card — Attendance Style").

---

## What the card displays

```
┌───────────────────────────────────────────────────┐
│  [Present] · Work Hours: 7.50 hrs                 │
│                                                   │
│  Punch In        Punch Out         →              │
│  09:25 AM        04:34 PM       (arrow btn)       │
└───────────────────────────────────────────────────┘
```

Five visible elements:

| Element | Example | What it means |
|---|---|---|
| Status badge (left) | `Present` (green), `Absent` (red), `Half Day` (orange) | Today's attendance status from the biometric system |
| Work hours (right) | `7.50 hrs` | Hours worked today |
| Punch In time | `09:25 AM` | The first / latest punch-in time today |
| Punch Out time | `04:34 PM` | The first / latest punch-out time today |
| Arrow button | `→` | Tap to punch in or out (hidden if no geofence flag or cycle already completed) |

---

## Where every value comes from

The card is rebuilt by a `Consumer<AttendanceProvider>` whenever the provider notifies — so it reflects the latest values from `AttendanceProvider`.

`AttendanceProvider` is fed by **two backend endpoints** that get merged on the card:

### Endpoint 1 — `GET /today-employee-attendance` (authoritative)

The "biometric" endpoint. Same data HR sees. Parsed into `TodayAttendanceModel` ([`lib/models/today_attendance_model.dart`](../lib/models/today_attendance_model.dart)). Fields used by the card:

| JSON field | Model getter | Used for |
|---|---|---|
| `first_in` | `formattedFirstIn` → `"09:25 AM"` | Punch In time |
| `last_out` | `formattedLastOut` → `"04:34 PM"` | Punch Out time |
| `total_work_hours` | `totalWorkHours` → `"7.50"` | Work hours |
| `status` | `status` → `"P"` / `"A"` / `"HD"` | Status badge color & label |

Called via:
```dart
ApiService.getTodayAttendance(token);   // GET /today-employee-attendance
```
defined in [`api_constants.dart:56`](../lib/core/constants/api_constants.dart#L56).

### Endpoint 2 — `GET /attendance/today` (geofence/session bootstrap)

The session-based endpoint that knows about open sessions and live work seconds. Only hit for geofence-enabled users via `attendanceProvider.bootstrapForGeofenceUser(token)`. It populates:

| Provider field | Card use |
|---|---|
| `lastPunchInDisplay` | Fallback for Punch In time when biometric is stale |
| `lastPunchOutDisplay` | Fallback for Punch Out time |
| `todayWorkHoursDisplay` | Fallback work hours (derived from `total_seconds / 3600`) |
| `isClockedIn` | Decides if the tap punches IN or OUT |
| `activeSession` | Open session details, drives `todayCycleCompleted` |
| `isGeofenceAttendanceEnabled` | Hides the arrow button entirely if the employee isn't on geofence attendance |

### The merge rule — why there are two

The biometric endpoint is the **source of truth**, but it lags slightly (the biometric backend re-aggregates a few moments after each punch). Until that aggregation catches up, the session endpoint gives instant feedback. So every field on the card uses a **fallback chain**:

```dart
// from dashboard_screen.dart:333-345
final punchInTime  = todayAtt?.formattedFirstIn ?? attProvider.lastPunchInDisplay  ?? '--:--';
final punchOutTime = todayAtt?.formattedLastOut ?? attProvider.lastPunchOutDisplay ?? '--:--';
final workHours    = todayAtt?.totalWorkHours
                     ?? (isGeofence ? attProvider.todayWorkHoursDisplay : null)
                     ?? '--';
```

Read: *"Use the biometric value if present; otherwise use the session value; otherwise show a placeholder."*

This is why the card sometimes appears to "update twice" after a punch — first instantly from the session endpoint, then a second later when the biometric aggregate confirms.

---

## When the data is fetched

There are **four** triggers:

1. **On dashboard mount** — `initState` schedules a `WidgetsBinding.addPostFrameCallback` that fires both `bootstrapForGeofenceUser(token)` and `fetchTodayAttendance(token)` in parallel. (`dashboard_screen.dart:62-87`)
2. **Pull-to-refresh** — `RefreshIndicator` on the scroll view calls `_fetchData()` which re-runs the same two calls.
3. **Immediately after a successful punch** — `fetchTodayAttendance(token)` is re-invoked from inside the tap handler (`dashboard_screen.dart:431`).
4. **After app resume** — when the geofence provider rehydrates on `loadPersistedSession()`, providers notify; the card rebuilds with whatever was persisted in SharedPreferences.

No polling. No websocket. The card is **fetch-on-event**, not live.

---

## What controls the arrow button

```dart
// dashboard_screen.dart:324-325
final canPunch = attProvider.isGeofenceAttendanceEnabled
              && !attProvider.todayCycleCompleted;
```

- `isGeofenceAttendanceEnabled` — boolean from the `/me/geofence` bootstrap. False for non-geofence employees (e.g. people who use only physical biometric devices). The arrow is hidden entirely for them.
- `todayCycleCompleted` — derived locally: *"the most recent punch-out has today's local date AND no session is currently open."* When both punch-in and punch-out exist for today, the arrow is hidden and the card becomes view-only until midnight.

The arrow icon itself switches:
- **Not clocked in yet today** → arrow points to "Punch In"
- **Currently clocked in (open session)** → arrow becomes "Punch Out"

---

## Status badge logic

```dart
// dashboard_screen.dart:351-371
switch (todayStatus) {
  case 'P':  statusText = 'Present';   color = green;
  case 'A':  statusText = 'Absent';    color = red;
  case 'HD': statusText = 'Half Day';  color = orange;
  default:   statusText = '--';        color = grey;
}
```

The `P` / `A` / `HD` value comes from the biometric endpoint's `status` field — the same status HR's dashboard uses. The app does no client-side computation here; it just renders what the backend says.

---

## What happens when the user taps the card

The tap handler runs the full punch flow (`dashboard_screen.dart:373-491`):

1. **Permission gate** — `LocationPermissionService.showPermissionDialog(context)` runs the prominent disclosure + system dialog. Aborts if denied.
2. **Selfie capture** — `attProvider.capturePunchSelfie()` opens the camera. Aborts if cancelled.
3. **Loading dialog** — non-dismissable spinner so the user can't double-tap.
4. **Punch API call** — branches on `isClockedIn`:
   - True → `punchOutWithLocation(time, token)` → `POST /attendance/punch-out`
   - False → `punchInWithLocation(time, location, userId, token)` → `POST /attendance/punch-in`
5. **Close loading dialog.**
6. **Refresh** — re-fetches `/today-employee-attendance` so the card values update.
7. **Status snackbar** — three branches:
   - Success **and** the server reported outside-fence → orange snackbar: *"Punched 80m outside fence — flagged for review"*
   - Failed because the employee already has an open session → red snackbar with the open `session_id`
   - Other failure → generic orange snackbar
8. **Open `PunchViewScreen`** — pushes a confirmation screen with the new punch record.

---

## Example: one day on the card

Let's trace what the card shows minute-by-minute for **Asha, geofence employee**, attendance date 2026-05-28.

| Time | Event | Card display |
|---|---|---|
| 08:50 | Opens app. `/today-employee-attendance` returns `null` (no record yet). `/attendance/today` returns empty too. | Status `--`, Work `--`, Punch In `--:--`, Punch Out `--:--`, arrow visible (canPunch = true) |
| 09:00 | Taps arrow → selfie → punch in. `POST /attendance/punch-in` succeeds, returns session_id. | Card refreshes: status still `--` (biometric not yet aggregated), Punch In `09:00 AM` (from session fallback `lastPunchInDisplay`) |
| 09:00:30 | Biometric backend aggregates the punch. Next refresh would show `P`. | (Not auto-refreshed yet — value updates on next event) |
| 12:30 | User pulls down to refresh. `/today-employee-attendance` returns `{ first_in: "09:00:12", status: "P", total_work_hours: "3.50" }`. | Status `Present` (green), Work `3.50 hrs`, Punch In `09:00 AM` |
| 18:00 | Taps arrow (now in "Punch Out" mode because `isClockedIn = true`). Punch out succeeds, session closed. | Punch Out `06:00 PM`, Work `9.00 hrs`. `todayCycleCompleted` flips to `true`. Arrow disappears. |
| 18:00–23:59 | Card stays read-only with final values. | Status `Present`, Work `9.00 hrs`, In `09:00 AM`, Out `06:00 PM`, no arrow |
| 00:00 next day | New IST day. `todayCycleCompleted` flips back to `false`. Both endpoints return empty for the new date. | Status `--`, arrow returns |

---

## What's *not* on the card (but lives nearby)

These bits are part of the same flow but render outside the card itself:

- **Outside-fence warning toast** — shown after a successful punch when `lastPunchGeofence['inside'] == false`. Uses the `geofence` block returned by the punch endpoint.
- **Session conflict toast** — shown when the server rejects a punch-in because there's already an open session (`session_id` of the open one is included in the message).
- **PunchViewScreen** — full confirmation page pushed after the tap flow finishes, showing the selfie, time, and geofence verdict for the just-completed punch.
- **Punch History tile** — separate dashboard tile labelled "Punch History" that opens `PunchHistoryScreen`. Only visible when the user has both `punch_history` permission and `isGeofenceEnabled`.

---

## Quick reference

| Question | Answer |
|---|---|
| Where is the card defined? | `dashboard_screen.dart`, the `Positioned` block around line 314, inside `_buildTopSection`. |
| What provider? | `AttendanceProvider` via a `Consumer`. |
| What endpoints feed it? | `GET /today-employee-attendance` (primary) + `GET /attendance/today` (geofence/session fallback). |
| When are they called? | Dashboard mount, pull-to-refresh, after every punch, after session rehydrate. |
| What hides the arrow button? | `!isGeofenceAttendanceEnabled` OR `todayCycleCompleted` (both punches done today). |
| What flips arrow between IN and OUT? | `isClockedIn` (true while a session is open). |
| What controls badge color/text? | Biometric `status` field (`P` / `A` / `HD` / other). |
| Does it auto-refresh? | No. Only on the four triggers listed above. |
| Why two endpoints? | Biometric is authoritative but lags; session endpoint gives instant feedback until biometric re-aggregates. |
| Where does outside-fence warning come from? | The `geofence` block in the punch-in/out API response, surfaced as `attProvider.lastPunchGeofence`. |
