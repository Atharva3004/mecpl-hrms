# Geofence & Geotagging — Employee Scenarios

This doc walks through how the MECPL Flutter app handles **geofence verification** and **location geotagging** in every realistic situation an employee can land in. Each scenario describes what the user sees, what the app does internally, what gets sent to the backend, and where it ends up.

If you only want the architecture summary, read [§ Quick reference](#quick-reference) at the bottom.

---

## How the system works (one paragraph)

When an employee punches in, the app captures GPS + selfie and posts them to `/attendance/punch-in`. The server replies with a `session_id` and a `geofence` block (`inside`, `distance_m`, `radius_m`). The app then registers an Android **WorkManager** (iOS BGTaskScheduler) task that fires **every 30 minutes** until punch-out, posting a location breadcrumb to `/attendance/location-ping` from a background isolate — so it keeps running even when the app is closed or killed. The geofence itself is a **per-branch radius** (default 50 m, configured server-side) and the check is **soft**: out-of-fence punches succeed but are flagged on the backend for HR review.

Key files:

- `lib/repositories/geofence_repository.dart` — caches `GET /me/geofence`
- `lib/core/config/office_config.dart` — deprecated 50 m fallback
- `lib/services/location_service.dart` — GPS + Haversine distance
- `lib/services/background_location_service.dart` — WorkManager registration
- `lib/services/background_ping_worker.dart` — the isolate that fires every 30 min
- `lib/services/ping_queue_service.dart` — offline queue
- `lib/providers/attendance_provider.dart` — punch in/out orchestration
- `lib/screens/attendance/attendance_screen.dart` — UI

---

## Scenario 1 — The happy path: full day in the office

**Setup:** Priya arrives at the office at **09:00 AM**, exactly inside the 50 m radius.

| Time | What Priya does | What the app does | Server state |
|---|---|---|---|
| 09:00 | Taps **Punch In** | GPS fix (3 m accuracy, 20 m from office) → selfie → `POST /attendance/punch-in` | Creates session `1001`, returns `{ inside: true, distance_m: 20, radius_m: 50 }` |
| 09:00:01 | Sees green badge *"Inside MECPL Office"* | `BackgroundLocationService.startTracking()` registers WorkManager task, fires ping #1 immediately | Breadcrumb 1 stored |
| 09:30, 10:00, 10:30, … | Working normally | Isolate fires every 30 min, posts ping | Breadcrumbs 2 … N |
| 18:00 | Taps **Punch Out** | GPS fix → `POST /attendance/punch-out` (`session_id: 1001`) → `stopTracking()` cancels WorkManager | Session closed. ~18 breadcrumbs total. |

**Result:** Clean 9-hour session, no flags, full timeline visible on the Session Timeline screen as a polyline.

---

## Scenario 2 — Punched in just outside the fence

**Setup:** Rahul parks 80 m from the entrance (radius is 50 m) and punches in from the parking lot.

What happens:

1. Punch In succeeds. The toast reads *"Punched 80m outside fence — flagged for review"*.
2. Status badge turns **orange**: *"80m away from MECPL Office"*.
3. `geofence.inside = false`, `distance_m = 80` on the server.
4. He walks inside; the badge flips back to green at ~10:02. **But the punch record stays flagged** — the verdict is set at the moment of punch.
5. Background pings continue normally every 30 minutes.

**Admin view:** The Live Attendance screen shows a small orange chip next to Rahul's row. The full attendance record in the admin dashboard shows *"Punched in 80m outside fence"*.

**Why the design lets it succeed:** A hard block would lock out delivery staff, field engineers, and anyone whose GPS drifts. HR can act on the flag instead.

---

## Scenario 3 — Field employee working from a client site all day

**Setup:** Anjali is a field service engineer. She's at a client's office 12 km from MECPL all day.

| Time | App behavior |
|---|---|
| 08:50 | Opens app. Badge shows *"12000m away from MECPL Office"* in orange. |
| 09:00 | Taps **Punch In** at client site. Punch succeeds, flagged. |
| 09:00–18:00 | Background pings every 30 min carry her actual locations — Server reconstructs a polyline that visibly leaves the office area. |
| 18:00 | Taps **Punch Out** at client site. |

**What the polyline looks like:** Pings cluster around the client coordinates the entire day — admin can confirm she was genuinely on-site, not at home.

---

## Scenario 4 — GPS turned off / Location Services disabled

**Setup:** Karan disabled Location Services system-wide (Settings → Location: OFF).

1. Taps **Punch In**.
2. `Geolocator.getCurrentPosition()` throws `LocationServiceDisabledException`.
3. App shows a blocking dialog: *"Location is required to punch in. Enable Location Services in Settings."* with a "Open Settings" button.
4. **No punch is attempted.** Backend records nothing.

**Recovery:** He enables it, the screen retries automatically when he comes back.

---

## Scenario 5 — Permission denied at the system dialog

First-time launch flow:

1. Custom **Prominent Disclosure** dialog opens: *"This app collects location data to enable attendance tracking and geofencing verification even when the app is closed or not in use."* (mandatory wording for Google Play.)
2. User taps **I Agree**.
3. System dialog asks for `ACCESS_FINE_LOCATION`. User taps **Deny**.
4. App stays on the attendance screen, but the Punch In button is **disabled** with helper text *"Location permission required."*

If they tap Deny twice (Android marks "deniedForever"), the app deep-links to system Settings on the next attempt — it can't re-show the dialog itself.

---

## Scenario 6 — No GPS fix within 10 seconds

**Setup:** Meera is in a basement parking lot; sky is occluded.

- `Geolocator.getCurrentPosition(LocationAccuracy.high)` is called with a **10-second timeout**.
- After 10 s with no fix, it throws `TimeoutException`.
- App shows error toast: *"Could not get your location. Move to an open area and try again."*
- **No fallback to last-known location** — the punch aborts cleanly.

She walks to the entrance, retries, gets a fix in 2 s, punch succeeds.

---

## Scenario 7 — App is killed mid-session

**Setup:** Vikram punches in at 9:00. At 10:15 he force-stops the app from Recent Apps. He doesn't open it again until 18:00.

This is the case the **WorkManager isolate** is designed for. The old code used `Timer.periodic` which dies on app kill — that was retired.

| Time | What happens |
|---|---|
| 09:00 | Punch in. WorkManager task registered. |
| 09:30 | First scheduled tick. App is foreground — ping fires from the main isolate. |
| 10:15 | App killed. WorkManager task **survives** (it's an OS-managed scheduler). |
| 10:30 | OS spawns the background isolate (`backgroundPingCallbackDispatcher`). The isolate reads the auth token + active `session_id` from SharedPreferences, gets a GPS fix, posts the ping. App is still killed. |
| 11:00 … 17:30 | Same — one ping every 30 min from the background isolate. |
| 18:00 | He reopens the app, taps Punch Out. WorkManager task cancelled. |

**Result:** Continuous breadcrumbs the entire day, even though the app process was dead for 7+ hours.

---

## Scenario 8 — Offline / no network for several hours

**Setup:** Sneha is in a basement co-working space — phone has zero connectivity from 10:00 to 14:00.

- Punch In at 09:00 — fine (was online then).
- 09:30 ping — sent successfully.
- 10:00 ping — network fails. `PingQueueService` enqueues it.
- 10:30, 11:00, 11:30, 12:00, 12:30, 13:00, 13:30 — all enqueued. Queue has 8 pings.
- 14:00 — connectivity returns. Queue flushes **one ping at a time** to `/attendance/location-ping`.
- 14:00 ping — sent live.
- Punch Out at 18:00 — fine.

**Result:** No data loss, but the queue flushes serially, not as a batch — so a 4-hour offline stretch can take a minute or two to drain.

---

## Scenario 9 — Reverse geocoding fails

The `geocoding` package's `placemarkFromCoordinates()` occasionally throws (rate limits, OS-level service hiccup).

- Punch payload still goes through — `latitude`, `longitude`, `accuracy_m`, `client_captured_at`, `selfie` are present.
- The `address` field is simply **omitted** from the multipart form.
- Backend stores `address = null` for that record.
- No error shown to user. (Address is best-effort, not load-bearing.)

The same applies to background pings.

---

## Scenario 10 — Employee logs out while a session is still open

**Setup:** Amit punches in at 09:00, then signs out of the app at 11:00 (without punching out — maybe he was switching accounts).

1. Auth token is cleared from SharedPreferences.
2. WorkManager periodic task is **still registered** — logout doesn't cancel it.
3. At 11:30 the background isolate fires. It tries to read the token, finds it missing.
4. The ping **fails silently** — no auth, can't post. The isolate has no way to surface this to the foreground app (the foreground app may not even exist).

**Open issue worth noting:** the task keeps trying every 30 min until either the user logs back in (token reappears) or the OS cleans up the registration. Sessions left open this way show up in the admin dashboard with a gap in breadcrumbs.

**Workaround:** punch out before logging out. The submit-resignation / withdraw flows don't trigger this, only manual logout.

---

## Scenario 11 — iOS, low-power mode

iOS's `BGTaskScheduler` is **opportunistic** — it doesn't guarantee the requested interval.

| Phone state | Actual ping cadence on iOS |
|---|---|
| Plugged in, screen on | ~30 min, near-exact |
| Battery > 20%, normal use | ~30 min, may slip 5–15 min |
| Low Power Mode | 60+ min between pings, OS may skip entirely |
| Battery < 10% | OS often suspends background work |

On Android, WorkManager respects the 30-min request closely unless the user has enabled aggressive battery saving for the app.

**Implication for HR:** iOS users with Low Power Mode may show sparse breadcrumbs. Don't read that as "the employee was off-site" — it could just be the OS.

---

## Scenario 12 — Branch transfer mid-day

**Setup:** Rohit gets transferred from the Pune branch (50 m radius around `18.5743, 73.7736`) to the Mumbai branch (`19.07, 72.87`, 80 m radius) effective immediately. HR updates the backend at 11:30.

1. The change is on the server but not yet in the local cache.
2. At 12:00 the next ping fires — backend silently uses the new branch for the `inside / distance_m` check, but the local app's badge still references Pune (showing huge distances).
3. The next time the app comes to foreground, `GeofenceRepository.refresh()` is called, fetches the new geofence from `GET /me/geofence`, updates the SharedPreferences cache, and the UI immediately reflects Mumbai.

No restart required.

---

## Scenario 13 — Brand-new app install, before `/me/geofence` returns

**Setup:** Asha installs the app at home, opens it, taps Punch In before the network call completes.

- `GeofenceRepository` cache is empty.
- `LocationService.checkGeofenceStatus()` falls back to **`OfficeConfig`** (the deprecated 50 m Pune coordinates).
- Asha lives in Bengaluru — the badge shows *"850000m away from MECPL Office"* (absurd because she's not in Pune).
- She punches anyway; payload reaches the backend, which uses the **real** branch (Bengaluru, configured server-side) to determine `inside / distance_m`, ignoring whatever the client thought.
- Next foreground tick fetches `/me/geofence` → cache hydrates → subsequent badges show realistic Bengaluru distances.

This is why the comment on `OfficeConfig` says it's a "first launch fallback only" and is `@Deprecated`.

---

## Scenario 14 — Network failure during the punch itself

Different from Scenario 8 (which is about pings).

If `POST /attendance/punch-in` fails (timeout, 500, DNS):

- The punch is **not retried automatically** by the app.
- Error dialog: *"Could not punch in. Check your connection and try again."*
- Selfie is **not cached** — they'll take a fresh one on retry.
- No session is created server-side, so no orphaned record.

Tap Retry → fresh GPS fix, fresh selfie, fresh request.

---

## Scenario 15 — Multiple employees at the same branch

The geofence is **per-branch**, not per-employee. If 80 people work out of the Pune office:

- All 80 share the same `latitude / longitude / radius_m` (delivered by `/me/geofence`, but identical values).
- When HR updates the Pune branch's radius from 50 m → 75 m, **everyone's next `/me/geofence` refresh picks it up** automatically.
- No per-employee overrides supported in the current code.

---

## Scenario 16 — Admin watches a live session

The Live Attendance screen polls `GET /attendance/live` every **30 seconds**.

What an admin sees per open session:
- Employee name + ID + avatar
- Punch-in time
- Current geofence status: a chip showing "Inside" (green) or "100m away" (orange) — updated server-side from the latest ping
- Battery level (if available)
- Last-seen timestamp (server time of the most recent ping)

No map on the live view — just a scrollable list. To see the polyline of an individual day, the admin drills into the Session Timeline screen.

---

## Quick reference

| Thing | Value | Where |
|---|---|---|
| Default geofence radius | 50 m | `OfficeConfig.geofenceRadius` (fallback only) |
| Default office coords | 18.5743, 73.7736 (Pune) | `OfficeConfig` |
| Authoritative geofence source | `GET /me/geofence` | `GeofenceRepository` |
| GPS accuracy mode | `LocationAccuracy.high` | `LocationService` |
| GPS timeout | 10 seconds | `LocationService` |
| Background ping interval | 30 minutes | `_pingFrequency` in `background_location_service.dart` |
| Initial WorkManager delay | 1 minute | `BackgroundLocationService` |
| Backoff on failed pings | 5 minutes | `BackgroundLocationService` |
| Admin Live poll interval | 30 seconds | `LiveAttendanceScreen` |
| Geofence enforcement | **Soft** (flagged, never blocked) | server-side |
| Reverse geocoding | Local, via `geocoding` package | `LocationService.getAddressFromCoordinates()` |
| Offline ping queue | `PingQueueService` (FIFO, one-by-one flush) | `lib/services/ping_queue_service.dart` |

### Payload sent on punch in/out

```
POST /attendance/punch-in     (multipart/form-data)
  latitude            : double
  longitude           : double
  accuracy_m          : double (optional)
  address             : string (optional, omitted if geocoding fails)
  client_captured_at  : ISO8601 datetime
  device_info         : JSON string (optional)
  selfie              : file
```

### Payload sent every 30 min during an active session

```
POST /attendance/location-ping     (form-encoded)
  session_id   : int
  latitude     : double
  longitude    : double
  accuracy_m   : double (optional)
  address      : string (optional)
  captured_at  : ISO8601 datetime
```

### Permissions declared (Android)

- `ACCESS_FINE_LOCATION`
- `ACCESS_COARSE_LOCATION`
- `ACCESS_BACKGROUND_LOCATION`
- `FOREGROUND_SERVICE_LOCATION`
- `WAKE_LOCK`, `RECEIVE_BOOT_COMPLETED` (for WorkManager)

### Failure modes summary

| Failure | App response |
|---|---|
| Location Services off | Block punch, prompt to enable |
| Permission denied | Disable Punch button, surface explanation |
| Permission denied forever | Deep-link to Settings |
| 10 s timeout, no fix | Toast error, no punch attempt |
| Geocoding throws | Omit `address`, continue |
| Punch API fails | Show error, no retry, no record |
| Ping API fails | Enqueue in `PingQueueService`, retry later |
| App killed | WorkManager respawns isolate every 30 min |
| Token cleared (logout) | Pings silently fail; task stays registered until next punch-in/out |
