# Geofence & Geotagging — Implementation Status

_Last updated: 2026-09-01_

What the MECPL Flutter app currently does for **geofencing** (validating that
an employee is inside their branch boundary) and **geotagging** (capturing GPS
on every attendance event).

> **This document was substantially rewritten on 1 Sep 2026.** The previous
> version described a Workmanager-only ping design and a map hard-coded to a
> single office; both have been replaced. Where behaviour changed, the reason
> is recorded — several of these were live bugs.

---

## 1. Source of truth

**The server owns attendance.** The app caches, it does not decide.

- A punch is persisted locally **only after** the server accepts it. It used to
  be written before the upload, so a rejected punch (409, 403, no signal) left
  a punch-in time on the card forever while the database held nothing.
- When `/attendance/today` succeeds and returns no punches, the local cache is
  **cleared** — card, punch history and the map trail. Data deleted on the
  server disappears from the app on the next sync.
- Punch times are never seeded from disk on cold start. The card shows `--:--`
  until the server answers.

**Consequence: offline punching does not work.** A punch with no connection
fails and says so explicitly — *"Your attendance was NOT recorded. Please check
your connection and punch again."* This is deliberate (decided 31 Aug); the
alternative was phantom punches that never reached the database.

---

## 2. Geofence config — [`geofence_repository.dart`](../lib/repositories/geofence_repository.dart)

Fetched from `GET /me/geofence` on login and on screen open, cached in
SharedPreferences under `my_geofence_cache`.

`Geofence.fromJson` accepts **both** documented response shapes:

| Shape | Keys |
|---|---|
| flat (guide v1.1, current) | `branch_id`, `latitude`, `longitude`, `radius_m` |
| `branch{}` envelope (guide v1.0) | `branch.id`, `branch.latitude`, `branch.geofence_radius_m` |

That contract has reversed twice. Parsing both is deliberate — a third flip
must not take attendance down. Every field read is lenient: a missing or
string-formatted value never throws, because the caller swallows exceptions
and a single bad key once discarded the entire geofence silently.

- `isEnforced` — needs lat + lng + a **positive** radius
- `isAttendanceEnabled` — `geofence_attendance == "Yes"`; `"No"` hides the punch button

Out-of-fence punches are **never blocked client-side**. The server flags them.

---

## 3. Map — [`attendance_map_screen.dart`](../lib/screens/attendance/attendance_map_screen.dart)

Draws the pin and ring from the employee's **own branch** via
`GeofenceRepository`. Falls back to the legacy `OfficeConfig` constants only
while the repository is cold.

When the branch is known but has **no radius**, the pin is drawn and the ring
is omitted — there is no fence, and inventing one would misrepresent where the
employee may punch.

> ⚠ **Currently unverifiable.** Branch coordinates in the database place a
> Baner punch ~28 km outside its fence, so the ring cannot be checked until the
> backend fixes that data. See `backend-remaining-work.md` §5.

---

## 4. What is captured

### Punch-in / punch-out

`latitude`, `longitude`, `accuracy_m`, `address` (reverse-geocoded),
`client_captured_at`, `selfie` (multipart, ≤2 MB), and `device_info` —
platform, manufacturer, brand, model, OS version, SDK level, app version,
`device_id`, `battery_pct`, `is_physical_device`.

`device_info` was wired up on 1 Sep; the column existed from the start but
nothing ever populated it.

### Location pings

`session_id`, `latitude`, `longitude`, `accuracy_m`, `address`,
`battery_pct`, `captured_at`.

**Timestamps carry an explicit `+05:30` offset**, via `ApiService.isoWithOffset`.
Sending `...Z` caused the server to store the UTC wall-clock and read it back
as IST — pings rendered 5h30m *before* the punch-in that opened their session.

---

## 5. Background tracking

Three independent sources, one shared clock.

| Source | Role |
|---|---|
| **Foreground service** ([`attendance_foreground_task.dart`](../lib/services/attendance_foreground_task.dart)) | Primary. Own isolate, `stopWithTask: false`, survives swipe-from-recents. |
| **Workmanager** ([`background_ping_worker.dart`](../lib/services/background_ping_worker.dart)) | Backstop. Survives reboot; covers the service being killed outright. |
| **Offline queue** ([`ping_queue_service.dart`](../lib/services/ping_queue_service.dart)) | 500 cap, 24 h TTL, batch-flushed on reconnect. |

**All three call `BackgroundLocationService.claimPingSlot()`** — a persisted,
cross-isolate claim in SharedPreferences (`last_ping_at`). Whichever fires
first takes the 30-minute slot; the others stand down. The claim is written
*before* the network call, so two sources cannot both pass.

Why it is persisted rather than in-memory: the throttle used to be a field on
a singleton, reset on every process start, and the Workmanager isolate never
saw it at all. That produced real intervals of 8 and 14 minutes.

### Cadence

- Handler ticks every **5 minutes**; `claimPingSlot()` gates at **30**. A window
  missed for want of a GPS fix or network retries minutes later instead of
  being lost for another half hour.
- `onStart` runs a due-check **immediately**, so a service restart does not
  delay an overdue ping.
- Punch-in **anchors** the window (`anchorPingWindow()`); punch-out clears it.
- Punch-in sends **no ping**. It would duplicate the Punch In row's time,
  place and selfie for no extra information.

### Lifecycle

- **Punch-in** → save "In" locally (for the map polyline) → anchor window →
  schedule Workmanager → start foreground service
- **Punch-out** → stop service (dismisses the notification) → clear window →
  cancel Workmanager → save "Out" locally
- **App killed mid-shift** → `resumeTrackingIfNeeded()` re-arms on next screen
  open. Never replays the `'In'` path, which would write a duplicate punch-in.
- **Second phone** → adopts the open session using the signed-in user id.
  `tracking_user_id` is device-local, so requiring it meant tracking silently
  refused to start on a second device and the trail just stopped.

### Verified on device (1 Sep, Xiaomi / MIUI, Android 12)

- Survives swipe-from-recents — service and isolate outlive the activity
- 13:39:12 → 14:09:11 — **29m59s**, exact cadence, app closed
- 14:47:36 restart → 14:47:39 ping — overdue ping recovered in 3 seconds

> **Not proven:** long-run stability. Three `(system)` restarts were observed,
> but most coincided with APK reinstalls during testing. A clean 90-minute run
> with no reinstalls is still outstanding.

> **OEM caveat:** nothing survives a *force-stop*. MIUI, ColorOS, Funtouch and
> One UI need Autostart enabled and battery restrictions removed, or they treat
> a swipe as a force-stop. That is device configuration; no app code fixes it.

---

## 6. Permissions

**Android** — `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`,
`ACCESS_BACKGROUND_LOCATION`, `FOREGROUND_SERVICE`,
`FOREGROUND_SERVICE_LOCATION`, `WAKE_LOCK`, `RECEIVE_BOOT_COMPLETED`,
`POST_NOTIFICATIONS`, `CAMERA`. The foreground service is declared in the app
manifest (the plugin ships only its boot/restart receivers).

Background location is requested as a **second, explicit step** after the
foreground grant. `Geolocator.requestPermission()` returns foreground-only on
Android 10+; accepting that as sufficient meant the background ping could
never get a fix, and failed silently.

**iOS** — when-in-use + always usage strings, `UIBackgroundModes`:
`fetch`, `location`, `processing`.

---

## 7. Error handling

| Case | Behaviour |
|---|---|
| 403 `GEOFENCE_NOT_ENABLED` | Hides the punch button, shows the contact-admin message |
| 409 `SESSION_ALREADY_OPEN`, **today** | Adopts the session so punch-out works |
| 409 `SESSION_ALREADY_OPEN`, **earlier day** | Names the date and ID: must be closed by an administrator. "Punch out first" was impossible advice — punch-in 409s and punch-out has nothing local to close |
| 409 `ALREADY_PUNCHED_TODAY` | Hides both buttons until the next day |
| No network | Explicit "attendance was NOT recorded" |
| No resolvable session | Says so, instead of an unexplained empty list |

Error codes are read as `code ?? error_code` — the guide has used both.

Punch and ping calls log status and full response body (`🟪 [PUNCH]`,
`🟨 [PING]`). Neither logged anything before 31 Aug, which is why a live
lockout took a device capture to find.

---

## 8. Regression guard

[`test/api_contract_test.dart`](../test/api_contract_test.dart) — 13 tests
pinning field names against the backend's own documented examples.

Fixtures are copied from the guide, **not** from what our code expects. A test
written against the parser would have happily passed with `opened_at`, the key
that silently wiped live sessions.

---

## 9. Known gaps

| Gap | Owner |
|---|---|
| Map ring unverifiable — branch coordinates ~28 km out | **Backend** |
| Stale sessions lock employees out permanently | **Backend** |
| Multi-device session adoption — implemented, untested | Mobile (needs 2 phones) |
| Long-run background stability on MIUI | Mobile (needs clean run) |
| Ping selfies | Closed (1 Sep) — see below |
| Offline punch queue | Closed — offline punching is intentionally off |

**Ping selfies — decided against.** The backend built its side (multipart
pings, `selfie_0..N` batch, 20-per-batch cap), but Android and iOS do not
allow silently capturing a camera photo from a background service. That is
still true with our foreground service, which keeps the process alive but
grants no silent camera access. A selfie could therefore only attach when the
employee happened to have the app open at the 30-minute mark, leaving
`selfie_url` null on the large majority of pings — and a reviewer would
reasonably read a missing photo as suspicious rather than as normal.

Tracking rows continue to reuse the punch-in selfie, which is honest about
what it is. If proving presence mid-shift becomes a requirement, the workable
design is a **prompted** photo check (notification → employee taps → camera),
not a silent capture. That is a product decision, not an implementation gap.

Backend detail: [`backend-remaining-work.md`](backend-remaining-work.md).
