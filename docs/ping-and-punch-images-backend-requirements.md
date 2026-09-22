# Location-Ping & Punch Images — Backend Requirements

**From:** Mobile app (Flutter)
**To:** Backend team
**Goal:** Store an image with **every location ping** (the 30‑minute intermediate tracking points), in addition to the punch‑in / punch‑out selfies that already work, and return the image URLs so the app can display them on the timeline.

---

## 0. TL;DR — what I need

| # | Change | Endpoint | Priority |
|---|--------|----------|----------|
| 1 | Accept an image file on a single ping | `POST /attendance/location-ping` | **Must** |
| 2 | Accept images on the offline batch | `POST /attendance/location-ping/batch` | **Must** |
| 3 | Return the ping's image URL in responses | ping responses + `/session/{id}/timeline` + `/attendance/today` | **Must** |
| 4 | Define a storage path for ping images | (storage) | Must |
| 5 | Keep the image **optional** on pings | both ping endpoints | **Must** (see §6 caveat) |
| 6 | Standardise field naming (`selfie` / `selfie_url`) | all | Should |

Punch‑in / punch‑out images already do all of this — I'm asking you to extend the **same pattern** to pings.

---

## 1. Current state (so we're aligned)

What works today (per the API reference):

- **Punch‑in** (`POST /attendance/punch-in`) and **punch‑out** (`POST /attendance/punch-out`)
  accept a `selfie` file (multipart, JPG/PNG, max 2 MB), store it, and return `selfie_url`.
  Stored at `…/storage/attendance/{YYYY}/{MM}/{employee_id}_{unix}.jpg`.

What does **not** work today:

- **Location ping** (`POST /attendance/location-ping`) is `application/json` only — **no image field**.
- **Location ping batch** (`POST /attendance/location-ping/batch`) — **no image field**.
- **Session timeline** `pings[]` and **today** `punches[]`/pings — **no image URL** on ping objects.

So ping images are currently impossible end‑to‑end: can't upload, can't store, can't read back.

---

## 2. Requirement A — single ping with image

**Change `POST /attendance/location-ping` from JSON to `multipart/form-data`** (or accept both, with multipart when an image is present).

### Request fields

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `session_id` | Integer | Yes | unchanged |
| `latitude` | Number | Yes | unchanged |
| `longitude` | Number | Yes | unchanged |
| `accuracy_m` | Number | No | unchanged |
| `address` | String | No | unchanged |
| `battery_pct` | Integer | No | unchanged |
| `captured_at` | DateTime (ISO‑8601 + TZ) | Yes | unchanged |
| **`selfie`** | **File** | **No** | **NEW** — JPG/JPEG/PNG, max 2 MB. Optional (see §6). |

### Success response (add `selfie_url`)

```json
{
  "status": true,
  "data": {
    "ping_id": 12,
    "selfie_url": "https://hrms.mecpl.in/storage/attendance/pings/2026/06/123_45_12_1748764800.jpg"
  }
}
```

`selfie_url` should be `null` when no image was sent.

---

## 3. Requirement B — batch (offline sync) with images

The app queues pings while offline and flushes them when connectivity returns. Those queued pings may each have a **local image file** that also needs uploading. JSON can't carry binary, so:

**Use `multipart/form-data` for the batch when images are present:**

- One text field `pings` = the JSON array (same shape as today).
- For each ping that has an image, attach a file named **`selfie_{index}`**, where `{index}` is that ping's 0‑based position in the `pings` array.

### Example (multipart parts)

```
pings        = [
  { "session_id":1, "latitude":18.5741, "longitude":73.7736, "battery_pct":80, "captured_at":"2026-06-01T10:00:00+05:30" },
  { "session_id":1, "latitude":18.5742, "longitude":73.7737, "battery_pct":75, "captured_at":"2026-06-01T10:30:00+05:30" },
  { "session_id":1, "latitude":18.5739, "longitude":73.7734, "captured_at":"2026-06-01T11:00:00+05:30" }
]
selfie_0     = <binary jpg for pings[0]>
selfie_2     = <binary jpg for pings[2]>     // pings[1] had no image → no file
```

### Success response (return a URL per accepted ping)

```json
{
  "status": true,
  "data": {
    "accepted": 3,
    "rejected": [],
    "ping_ids":   [12, 13, 14],
    "selfie_urls": [
      "https://hrms.mecpl.in/storage/attendance/pings/2026/06/123_1_12_...jpg",
      null,
      "https://hrms.mecpl.in/storage/attendance/pings/2026/06/123_1_14_...jpg"
    ]
  }
}
```

`ping_ids[i]`, `selfie_urls[i]` align with `pings[i]`.

> **Payload‑size note:** with images, a 100‑ping batch could be very large. Please **cap the batch to ~20 pings when images are attached** (return `422` / a clear error if exceeded) so the app can chunk it. Confirm the cap you want.

---

## 4. Requirement C — return ping image URL when reading back

So the app can show the photo on the trail:

- **`GET /attendance/session/{id}/timeline`** → add `selfie_url` to **each object in `pings[]`**:

```json
"pings": [
  {
    "latitude": 18.5740,
    "longitude": 73.7735,
    "captured_at": "2026-06-01T09:30:00+05:30",
    "inside_geofence": true,
    "accuracy_m": 10.0,
    "selfie_url": "https://hrms.mecpl.in/storage/attendance/pings/2026/06/123_1_12_...jpg"
  }
]
```

- **`GET /attendance/today`** → if pings are ever surfaced here, include `selfie_url` the same way. (Punch objects already have `selfie_url`.)
- `selfie_url` = `null` when that ping has no image.

---

## 5. Requirement D — storage convention

Keep it parallel to the existing selfie path, in its own `pings` subfolder so punch vs ping images are easy to tell apart:

```
https://hrms.mecpl.in/storage/attendance/pings/{YYYY}/{MM}/{employee_id}_{session_id}_{ping_id}_{unix_timestamp}.jpg
```

- Same accepted formats (JPG/JPEG/PNG) and **2 MB** limit as punch selfies.
- Return the **full public URL** (not a relative path), same as `selfie_url` today.

---

## 6. ⚠️ Critical caveat — auto‑capturing a ping image isn't always possible

This is a **product decision the backend/PM side must make**, because it changes the contract:

- The 30‑minute pings fire from a **background task** (Workmanager), often while the app is **killed or backgrounded**.
- **Android and iOS do not allow silently taking a camera/selfie photo from the background** without a visible foreground UI. So the app frequently **cannot** capture a fresh selfie at ping time.

Because of that, the image **must be optional** on pings (Requirements A & B already mark it optional). Please decide what a ping with no image means and confirm:

1. **Optional, skip when unavailable** (recommended) — most background pings will have `selfie_url = null`; only foreground/app‑open pings carry a photo.
2. **Reuse last image** — backend or app attaches the most recent punch/ping selfie. (Misleading — not recommended.)
3. **Require image** — only viable if pings happen with the app in foreground / a persistent foreground service prompts capture. This will drastically reduce ping frequency. Not recommended for true background tracking.

👉 **My recommendation: Option 1.** Build the endpoints to accept an optional image; the app sends one whenever it legitimately has it and omits it otherwise.

---

## 7. Field‑naming / consistency asks

- Use **`selfie`** (request file) and **`selfie_url`** (response) on pings — identical to punch‑in/out — so the app has one code path. If you'd rather use `image` / `image_url`, that's fine, just tell me and keep it **consistent across all three** endpoints (single, batch, timeline).
- Keep rate limits as documented (ping 30/min, batch 30/min) unless images force a change — if so, tell me the new limits.
- Error format unchanged (`{ status:false, message }`, `422` with `errors{}` for validation).

---

## 8. Open questions for backend (please answer)

1. Field name: **`selfie` / `selfie_url`** (match punch) or `image` / `image_url`? 
2. Batch‑with‑images **max count** (I suggested 20)?
3. Confirm storage path in §5 (or give the one you'll use).
4. Confirm pings keep the **2 MB** / JPG‑PNG limits.
5. Confirm the **ping image is OPTIONAL** (§6, Option 1) — or state the chosen option.
6. Will `/attendance/today` ever return pings? If yes, will they carry `selfie_url`?
7. Any change to rate limits once multipart/images are allowed?

---

## 9. What the app will do once this is ready

- Send `selfie` on `POST /attendance/location-ping` whenever an image is available at capture time.
- Queue `{ping + local image path}` offline, then flush via the multipart batch (chunked to your cap).
- Read `selfie_url` from `pings[]` in the session timeline and show the thumbnail on each tracking row (today it falls back to a map‑pin icon because pings have no image).
- Treat `selfie_url: null` gracefully (keep the map‑pin placeholder).

No app‑side blocker except your answers in §8 — once the endpoints accept/return the image fields above, I'll wire it in.
