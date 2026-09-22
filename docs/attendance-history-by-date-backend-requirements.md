# Past-Date Attendance History — Backend Requirements

**From:** Mobile app (Flutter)
**To:** Backend team
**Goal:** Let the app show **punches + tracking pings for any past date**, not just today. Right now the app can only call `/attendance/today` (today) and `/session/{id}/timeline` (one session, if the id is already known) — so there is **no way to browse a previous day**. The data is already stored; we just need an endpoint to read it by date.

---

## 0. TL;DR — what I need

**One new endpoint:**

```
GET /api/attendance/history?date=YYYY-MM-DD
```

Returns every session for that calendar day (IST), each with its punches **and** location pings, so the app can render the same timeline it already shows for today.

That's it. No other endpoints need to change.

---

## 1. Why the app can't do this today

- `GET /attendance/today` → today only.
- `GET /attendance/session/{id}/timeline` → needs a `session_id` the app has no way to discover for a past day.
- There is **no** "list my sessions" or "history by date" endpoint.

So the app blocks past dates with a "not available yet" message. Once the endpoint below exists, I'll replace that block with a real fetch.

---

## 2. The endpoint

### Request

```
GET /api/attendance/history?date=2026-05-28
Authorization: Bearer <token>
Accept: application/json
```

| Query param | Type | Required | Notes |
|-------------|------|----------|-------|
| `date` | String `YYYY-MM-DD` | Yes | The calendar day (IST) to fetch. |
| `user_id` | Integer | No | **Admin only** — fetch another employee's history. Ignored / forbidden for non-admins (same rule as `/attendance/live` & session timeline). |

### Response (200)

```json
{
  "status": true,
  "data": {
    "date": "2026-05-28",
    "total_seconds": 32400,
    "sessions": [
      {
        "session_id": 5,
        "started_at": "2026-05-28T09:00:05+05:30",
        "ended_at":   "2026-05-28T18:00:10+05:30",
        "duration_seconds": 32400,
        "status": "closed",
        "punches": [
          {
            "type": "in",
            "punched_at": "2026-05-28T09:00:05+05:30",
            "latitude": 18.5743404,
            "longitude": 73.7736299,
            "selfie_url": "https://hrms.mecpl.in/storage/attendance/2026/05/123_1748400005.jpg",
            "inside_geofence": true,
            "distance_m": 15
          },
          {
            "type": "out",
            "punched_at": "2026-05-28T18:00:10+05:30",
            "latitude": 18.5743404,
            "longitude": 73.7736299,
            "selfie_url": "https://hrms.mecpl.in/storage/attendance/2026/05/123_1748433610.jpg",
            "inside_geofence": true,
            "distance_m": 20
          }
        ],
        "pings": [
          {
            "latitude": 18.5740,
            "longitude": 73.7735,
            "captured_at": "2026-05-28T09:30:00+05:30",
            "inside_geofence": true,
            "accuracy_m": 10.0,
            "selfie_url": null
          },
          {
            "latitude": 18.5741,
            "longitude": 73.7736,
            "captured_at": "2026-05-28T10:00:00+05:30",
            "inside_geofence": true,
            "accuracy_m": 12.0,
            "selfie_url": null
          }
        ]
      }
    ]
  }
}
```

### Empty day (no attendance that date) — still 200

```json
{
  "status": true,
  "data": { "date": "2026-05-28", "total_seconds": 0, "sessions": [] }
}
```

> Please return **200 with an empty `sessions` array** for a day with no data — not a 404 — so the app can show a clean "no records for this date" state.

---

## 3. Field rules (keep these identical to existing endpoints)

So the app reuses its current parsing with zero special-casing:

- **Punch object** = exactly the shape `/attendance/today` `punches[]` uses today: `type` (`in`/`out`), `punched_at`, `latitude`, `longitude`, `selfie_url`, `inside_geofence`, `distance_m`.
- **Ping object** = exactly the shape `/session/{id}/timeline` `pings[]` uses today: `latitude`, `longitude`, `captured_at`, `inside_geofence`, `accuracy_m`, `selfie_url` (your new field — `null` when no image).
- All timestamps **ISO-8601 with +05:30** (same as everywhere else).
- `latitude` / `longitude` must be present on every punch and ping (the app drops points with missing coords).

---

## 4. Behavior / edge cases — please confirm

1. **Multiple sessions per day:** include them all in `sessions[]`, ordered by `started_at` ascending.
2. **Active session on `date == today`:** include it with `ended_at: null`, `status: "active"` (so the same endpoint can also serve "today" if we ever switch to it). Not required, but nice.
3. **`distance_m` on pings?** Optional — include if you have it; the app can compute locally otherwise.
4. **How far back?** Any retention limit on history (e.g. 90 days)? Tell me so the date picker can cap its earliest selectable date.
5. **Auth:** non-admin can only fetch their own history; admin may pass `user_id`. Confirm.
6. **Pagination:** a single day is small (a few punches + ≤ ~20 pings), so I assume **no pagination** needed. Confirm.

---

## 5. Open questions for backend

1. Endpoint path OK as `GET /attendance/history?date=YYYY-MM-DD`? (Or do you prefer `/attendance/sessions?date=`?)
2. Confirm response shape in §2 (sessions → punches + pings).
3. Retention window for history (§4.4)?
4. Admin `user_id` param supported (§4.5)?
5. Rate limit for this endpoint?

---

## 6. What the app will do once this ships

- Replace the **"Past-date history is not available yet."** block with a real call to `GET /attendance/history?date=<selected>`.
- **Tracking toggle OFF** → show that day's punch-in / punch-out rows (flatten `sessions[].punches`).
- **Tracking toggle ON** → show the full trail (flatten `sessions[].punches` + `sessions[].pings`), same row UI as today.
- Date picker already lets the user pick any past date (`firstDate = AppConstants.appStartDate`); I'll cap `firstDate` to your retention window if you set one.

No app-side blocker except this endpoint — once it returns the shape in §2, I'll wire it in and past-date punches **and** tracking points will appear.
