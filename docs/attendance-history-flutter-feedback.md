# `/attendance/history` Integration — Flutter Feedback

**From:** Flutter developer
**To:** Backend developer
**Date:** 2026-06-03
**Re:** `attendance-history-backend-response.md` (history endpoint live)

---

## Summary

The history endpoint is wired into the app and verified working — it returns the
exact spec shape `{ status, data: { date, total_seconds, sessions[] } }`, and the
empty-day case (`sessions: []` → "No records for this date") renders correctly.

Two issues came up while testing against live data. **Issue 1** is specific to the
history endpoint; **Issue 2** is a wider auth/token problem that is logging users
out across the whole app.

---

## Issue 1 — Active sessions are NOT returned by `/attendance/history`

Your response confirmed (Behavior #2):

> *"Active session on today's date: included with `ended_at: null`, `status: "active"`."*

But this isn't happening in practice.

### Evidence

`GET /api/attendance/today` (user 77, admin) returns an **active session**:

```json
{
  "active_session": {
    "session_id": 2,
    "started_at": "2026-05-28T12:22:17+05:30",
    "ping_count": 161,
    "last_ping": { "latitude": 18.5743221, "longitude": 73.7736486, "captured_at": "2026-05-28T06:52:16+05:30" }
  },
  "punches": [],
  "total_seconds": 0
}
```

(Also observed as `session_id: 7, started_at: 2026-06-02T13:02:20+05:30` for user 1822.)

But `GET /api/attendance/history?date=2026-05-28` for the **same user** returns:

```json
{ "status": true, "data": { "date": "2026-05-28", "total_seconds": 0, "sessions": [] } }
```

So a session that clearly exists (161 pings, started 28-May) does **not** appear in
that date's history. Any day with an unclosed session shows blank in the app.

### Request

1. Include **open/active** sessions in `/attendance/history`, keyed by the calendar
   date of `started_at` (IST), with `ended_at: null` / `status: "active"` — as the
   spec promised.
2. Confirm: does history require a **closed** session or a non-empty `punches[]`? In
   the case above `punches: []` but pings exist — we'd still want the session
   returned so its pings show on the timeline.

---

## Issue 2 — Tokens are being revoked → constant "session expired"

The app logs the user out whenever any API call returns **401**. We're seeing tokens
die in two distinct ways:

### (a) Single-session-per-employee

Logging the same employee in on a second device (or a re-login) revokes the first
token. Confirmed:

- Token `285` returned **200** on its first call, then **401** on **every** endpoint
  (including `/attendance/today`) after a new login for the same employee.
- Two devices with the same account then keep knocking each other out — whoever logs
  in last survives; the other shows "session expired."

### (b) Possible short token TTL

Even on a **single device with no other login**, the token works right after login
but `/validate-token` returns **401** a while later, forcing re-login.

### Please confirm / adjust

1. Is **single-session-per-employee** intended? If users should stay logged in on
   more than one device, `check_login_api` should **not** delete existing tokens (or
   the per-user token limit should be raised).
2. Check `config/sanctum.php` → `expiration` (and any per-token `expires_at` or a
   scheduled job pruning `personal_access_tokens`). We need tokens valid for at least
   a full work day — ideally `expiration => null` or a long value.

A quick answer on **expected token lifetime** + **whether multi-device login is
allowed** will let us set the app's auth behavior correctly.

---

## What's already done on the Flutter side

- Past-date history wired to `GET /attendance/history?date=<selected>` (+ admin `user_id`).
- Parses `sessions[] → punches[] + pings[]`; toggle OFF = punches only, ON = punches + pings.
- Shows `total_seconds` as the day's total; empty `sessions[]` → "No records for this date".
- No date cap in the picker (per "no retention limit").

Thanks!
