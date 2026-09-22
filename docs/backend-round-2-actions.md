# Backend — Round 2 Actions

**Date:** 2026-08-29
**From:** Mobile (Flutter) team
**To:** Backend team
**Re:** your `docs/backend-response-to-flutter.md`

---

## 0. Where we stand

Thanks — B1, B2, B3 and B8 are the right fixes, and C1–C4 answered cleanly.
Two of your pushbacks are correct and we've accepted them (details in §1).

**We are not asking for new features here.** What's left is: confirm the
deploy, run four queries only you can run, and correct three places where the
guide now contradicts the shipped behaviour.

| # | Action | Priority | Owner |
|---|---|---|---|
| **1** | Confirm the 4 fixes are **deployed to production**, not just merged | 🔴 blocking | backend |
| **2** | Run `pings_last_24h` + share ping error logs | 🔴 blocking | backend |
| **3** | Run the branch geofence audit | 🔴 blocking | backend |
| **4** | Run the bad-rows count, backfill if non-zero | 🟠 | backend |
| **5** | Fix `code` → `error_code` in the guide (§3.2, §5) | 🟠 | backend |
| **6** | Update the `/today` example in the guide (§3.6) | 🟠 | backend |
| **7** | Resolve the §6.3 timezone contradiction | 🟠 | backend |
| **8** | Add the unique constraint on active sessions | 🟡 | backend |
| **9** | Admin check on `getEmployeesByBranch()` — **security** | 🟠 | backend |
| **10** | Fix `selfie_*` validation — **security** | 🟠 | backend |
| **11** | Batch filename collision, N+1 on admin dashboard | 🟡 | backend |

---

## 1. Settled — no further debate needed

### 1.1 `session_id` on `/today` — you were right, and B1 already fixed it

You said `session_id` was always present on `/today` punches and suspected
our parsing. We checked: our parser **does** read `punches[].session_id`
correctly. The problem was one line further down — we only keep the punch
record when `latitude` and `longitude` are both present:

```dart
final sid = _asInt(map['session_id']);          // read correctly
...
if (dt != null && lat != null && lng != null) { // but the record is only kept here
  records.add(LocalPunchRecord(..., sessionId: sid));
}
```

No coordinates → the whole record was discarded → the session id went with it
→ the timeline was never fetched → **that** is why pings never appeared.

**So the missing GPS fields (B1) were the real cause, and your B1 fix
resolves both symptoms.** B2-on-`/today` was our misdiagnosis. Apologies for
the noise — it came from your §3.6 example, which omits `session_id`
(see action 6).

### 1.2 `error_code` vs `code` — accepted, no app change needed

We've made our client read `code ?? error_code`, so we're correct either way
and this can't bite us again. Use `error_code` as you prefer.

The only thing needed is the doc fix in action 5 — we raised this **because
your guide says `code`**, not from guesswork.

### 1.3 C1–C4 — all good, nothing to do

| | Answer | Our takeaway |
|---|---|---|
| C1 | JSON accepted on both ping endpoints | We keep posting JSON — no rewrite needed |
| C2 | `is_queued` ignored | We'll drop it eventually; no urgency |
| C3 | Session owner gets 200 on timeline | Rules out a 403 masquerading as "no pings" |
| C4 | `battery_pct: null` accepted | Our pings aren't being 422'd on this |

---

## 2. 🔴 Action 1 — Confirm the fixes are deployed

Your doc says the four fixes are done. We can't verify from outside — every
endpoint returns `401` to an unauthenticated probe whether or not the fix is
live.

**Please confirm:** are B1, B2, B3 and B8 deployed to `hrms.mecpl.in`, or
only merged to a branch? If deployed, what time? We want to re-test against
the right build rather than chase a ghost.

Quickest proof, with any employee token:

```bash
curl -s -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" \
  "https://hrms.mecpl.in/api/attendance/today" \
  | jq '.data.punches[0] | {session_id, latitude, longitude, accuracy_m, address}'
```

All five non-null after a punch-in = deployed. Paste us that output.

---

## 3. 🔴 Action 2 — The ping count (asked twice, still outstanding)

This is the **single most valuable unknown in the whole investigation** and
only you can run it.

```sql
SELECT COUNT(*) AS pings_last_24h
FROM attendance_location_pings
WHERE captured_at > NOW() - INTERVAL 1 DAY;
```

It splits the remaining problem cleanly:

- **0 rows** → pings never reach you. That's our bug (we never requested
  Android background location — now fixed, pending device testing). You can
  close your side.
- **rows exist** → pings are stored and the display problem is downstream.

Also please share, for the last 24h:
- any **409** on `/attendance/location-ping` (session closed under a live
  device — tells us whether a job force-closes sessions)
- any **422** (validation rejecting our payload shape)
- any **429** (rate limiting on batch flush)

Even "zero of all three" is a useful answer.

---

## 4. 🔴 Action 3 — Branch geofence audit

You assigned this to Omkar, but he has no production DB access — this needs
to come from your side.

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

**Why this is blocking, not busywork:** a branch missing any of the three
values has no enforceable fence. The app will draw no circle and show a
neutral (neither inside nor outside) state, and **no amount of app-side work
changes that** — it needs someone to enter the coordinates.

We also can't tell a "branch not configured" state apart from "something is
still broken" until we know which branches are actually set up. If branches
are unconfigured, please flag who owns entering that data — it's an
admin/data task, not a code task, and it will otherwise sit unowned.

---

## 5. 🟠 Action 4 — Bad-rows count and backfill

Your B3 fix stops *new* bad rows. Existing ones are still wrong on the admin
dashboard. Your own query:

```sql
SELECT COUNT(*) AS bad_rows
FROM attendance_punches p
JOIN branches b ON b.id = p.branch_id
WHERE p.inside_geofence = 0
  AND (b.latitude IS NULL OR b.longitude IS NULL
       OR b.geofence_radius_m IS NULL OR b.geofence_radius_m = 0);
```

If non-zero, apply the `UPDATE` you already drafted. These are punches
flagged "outside the fence" at branches that never had a fence — they're
showing as false violations for admin review right now.

**Take a backup before the UPDATE.** It has no `LIMIT` and touches
historical attendance data.

---

## 6. 🟠 Actions 5–7 — The guide now contradicts the shipped behaviour

`docs/geofence-module-guide.md` v1.0 is the document we build against. Three
places are now wrong, and each one cost us a round trip:

### Action 5 — `code` → `error_code`

**§3.2**, example error response:
```json
{ "status": false, "code": "SESSION_ALREADY_OPEN", ... }
```

**§5**, "Error Response Format" — the canonical template:
```json
{ "status": false, "code": "ERROR_CODE", "message": "..." }
```

Both say `code`. Your reply says `error_code` and "we will not rename it" —
fine, but the guide has to match, or the next reader repeats our mistake.

### Action 6 — `/today` example (§3.6)

The `punches[]` example still shows the old shape with no `session_id`, no
`latitude`, no `longitude`. That example is exactly what we implemented
against, and it is why we filed B1 and B2. Please update it to the shipped
response.

### Action 7 — Resolve the §6.3 timezone contradiction

Your guide, §6.3, listed under **High** severity:

> The "already punched today" check uses `Carbon::now('Asia/Kolkata')` (IST),
> but session `date` is stored using `now()->toDateString()` (server
> timezone, likely UTC). The `today()` endpoint also uses server timezone.
> **Impact:** Between 00:00 UTC and 05:30 UTC … an employee who punched
> yesterday (IST) being incorrectly blocked today.

Your reply says `config/app.php` is `Asia/Kolkata`, so `now()` returns IST
and no window exists.

Both cannot be true. Either:
- **§6.3 was a false alarm** → delete it from the guide, or
- **the timezone was changed since** → note that, and tell us whether rows
  written *before* the change hold UTC dates (which would make historical
  `/history?date=` queries off by a day for those rows)

We're not chasing this further — we just need it off the open-P0 list one way
or the other.

> One thing worth a look either way: with `config/app.php` set to
> `Asia/Kolkata`, Eloquent writes IST, but any **raw SQL** using `NOW()` uses
> the **MySQL session timezone**, which is usually the server's. If your
> purge job or any reporting query mixes the two, they'll disagree. Your
> `pings_last_24h` query above uses `NOW()` — worth confirming they match.

---

## 7. 🟠 Actions 9–10 — Two security items (independent of us)

These are from your own §6. **Neither is blocked by anything on our side, and
neither should wait for the geofence work.**

### Action 9 — §6.6 `getEmployeesByBranch()` has no admin check

Any authenticated user — any employee — can enumerate every employee in any
branch, with their employee codes and geofence status. That is an
authorization hole open in production today. Please add the role check.

### Action 10 — §6.4 `selfie_*` validation never runs

```php
'selfie_*' => 'nullable|file|mimes:jpg,jpeg,png|max:2048'
```

Laravel does not support glob keys, so `selfie_0`, `selfie_1` … are
**completely unvalidated** — any file type, any size, written to a
public storage path. Needs an explicit loop over the indices, or
`Rule::forEach`.

This also blocks ping-selfie support: we won't start sending images until the
uploads are validated.

---

## 8. 🟡 Actions 8, 11 — Lower priority

### Action 8 — Unique constraint on active sessions

You deferred this, saying `lockForUpdate()` is sufficient. Mostly true, with
one caveat: when the `SELECT … WHERE employee_id = ? AND status = 'active'`
matches **no rows**, `lockForUpdate()` only blocks a concurrent insert
through InnoDB **gap locking**, which requires a suitable index on
`(employee_id, status)` and REPEATABLE READ isolation.

If that index doesn't exist, two concurrent punch-ins can still both pass.
Please confirm the index exists — and keep the constraint on the roadmap,
since it's the only guarantee that survives a future refactor of the
controller.

Check for existing duplicates before adding it:

```sql
SELECT employee_id, COUNT(*) AS open_sessions
FROM attendance_sessions
WHERE status = 'active'
GROUP BY employee_id
HAVING COUNT(*) > 1;
```

### Action 11 — §6.5 and §6.10

- **§6.5** batch selfie filename collision (1-second timestamp resolution —
  the 2nd image overwrites the 1st). Blocks ping selfies; add the ping index
  or a random suffix.
- **§6.10** N+1 on `live()` and `getGeofenceMapData()`. Admin dashboard
  performance only.

---

## 9. What we've fixed on our side

Shipped, compile-verified, **pending device testing**:

- Parse the `branch{}` envelope and `geofence_radius_m` from `/me/geofence` —
  we were reading a flat `branch_id` that doesn't exist in your payload, and
  the resulting cast exception was silently discarding **every** geofence
  response. This is why distances were measured against a hard-coded office
  and every inside/outside ribbon rendered neutral.
- Read `code ?? error_code` on error responses
- Handle 403 `GEOFENCE_NOT_ENABLED` — hides the punch button instead of
  letting the user retry into the same error
- Request Android "Allow all the time" location as a second, explicit step —
  without it our background ping could never get a GPS fix. **Most likely
  why no pings reached you.**
- Tolerant numeric parsing so a string-formatted decimal can't blank the
  timeline

Still on our list: migrating the map off the hard-coded office, sending a
ping at punch-in, a foreground service for OEM battery-manager survival, and
populating `battery_pct`.

---

## 10. What we need back — short version

1. Are B1/B2/B3/B8 **deployed** to `hrms.mecpl.in`? (+ the `curl` output from §2)
2. `pings_last_24h` count + any 409/422/429 on the ping endpoint
3. Branch audit output (both queries in §4)
4. `bad_rows` count from §5
5. Confirm the index behind `lockForUpdate()` exists (§8)

Items 1–3 are what unblock our end-to-end testing. The rest can follow.
