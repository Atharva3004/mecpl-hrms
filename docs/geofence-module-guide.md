# Geofence Attendance Module — Flutter Developer Guide

> **Version:** 2.0  
> **Last Updated:** 2026-08-31  
> **Base URL:** `{{BASE_URL}}` (replace with your server URL, e.g. `https://yourdomain.com`)  
> **Auth:** All APIs require `Authorization: Bearer <token>` header  
> **Timezone:** Server uses `Asia/Kolkata` (IST). All dates/times are IST.

---

## Table of Contents

1. [Module Overview](#1-module-overview)
2. [Database Schema](#2-database-schema)
3. [API Reference](#3-api-reference)
4. [Step-by-Step Flutter Integration Flow](#4-step-by-step-flutter-integration-flow)
5. [Error Codes & Handling](#5-error-codes--handling)
6. [Notes & Caveats](#6-notes--caveats)

---

## 1. Module Overview

### What It Does

GPS-based attendance tracking. Employees punch in/out using a **selfie + GPS location** from the Flutter app. The system:

- Records punch-in and punch-out with GPS coordinates and a selfie photo
- Calculates whether the employee is **inside or outside** the branch's geofence radius (Haversine formula)
- Tracks employee location via **periodic pings** every 30 minutes during an active session
- Supports **offline mode** — pings are queued and batch-synced when connectivity resumes
- **Does NOT block** out-of-fence punches — only **flags** them for admin review

### Architecture

```
┌──────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Flutter App  │────>│   Laravel APIs   │────>│    Database      │
│              │     │                  │     │                 │
│ - Selfie     │     │ - Punch In/Out   │     │ - sessions      │
│ - GPS        │     │ - Location Pings │     │ - punches       │
│ - Battery %  │     │ - Geofence Check │     │ - location_pings│
│ - Offline Q  │     │ - Haversine Calc │     │ - branches      │
└──────────────┘     └──────────────────┘     └─────────────────┘
```

### Key Business Rules

| Rule | Description |
|------|-------------|
| **One cycle per day** | Employee can punch-in and punch-out once per calendar day (IST). After punch-out, next punch-in is blocked until IST midnight. |
| **Geofence = tracking only** | Out-of-fence punches are **allowed** but flagged. Admin sees who is outside on the live dashboard. |
| **Geofence must be enabled** | Employee's `geofence_attendance` flag must be `Yes` to punch. Otherwise → 403. |
| **Branch must have coordinates** | If branch has no lat/lng/radius, all punches are marked `inside_geofence: true` by default. |
| **Selfie required** | Both punch-in and punch-out require a selfie photo (JPG/PNG, max 2MB). |
| **Location pings** | Send GPS pings every 30 minutes while a session is active. |
| **Offline sync** | Queue pings locally and batch-sync when online (max 100 per batch, 20 if images attached). |

---

## 2. Database Schema

### 2.1 `branches` table (geofence config)

| Column | Type | Description |
|--------|------|-------------|
| `latitude` | decimal(10,7) | Branch center latitude. Nullable. |
| `longitude` | decimal(10,7) | Branch center longitude. Nullable. |
| `geofence_radius_m` | smallint unsigned | Geofence radius in meters. Nullable. |

> A branch has a valid geofence only when all three fields are non-null and `geofence_radius_m > 0`.

### 2.2 `emp_company_details` table

| Column | Type | Description |
|--------|------|-------------|
| `geofence_attendance` | enum('Yes','No') | Whether this employee uses geofence attendance. Default: `No`. |

### 2.3 `attendance_sessions` table

| Column | Type | Description |
|--------|------|-------------|
| `id` | bigint | Primary key |
| `employee_id` | int | FK to employees |
| `branch_id` | int | FK to branches |
| `date` | date | Session date (IST) |
| `punch_in_id` | bigint | FK to attendance_punches (the IN punch) |
| `punch_out_id` | bigint | FK to attendance_punches (the OUT punch). Null while active. |
| `started_at` | datetime | When session started |
| `ended_at` | datetime | When session ended. Null while active. |
| `duration_seconds` | int | Total work duration in seconds. Set on punch-out. |
| `ping_count` | int | Number of location pings received during session |
| `status` | enum | `active`, `closed`, `force_closed` |

### 2.4 `attendance_punches` table

| Column | Type | Description |
|--------|------|-------------|
| `id` | bigint | Primary key |
| `employee_id` | int | FK to employees |
| `branch_id` | int | FK to branches |
| `session_id` | bigint | FK to attendance_sessions |
| `type` | enum('in','out') | Punch type |
| `punched_at` | datetime | Server timestamp of the punch |
| `client_captured_at` | datetime | Client-side timestamp (from Flutter app) |
| `latitude` | decimal(10,7) | GPS latitude at punch time |
| `longitude` | decimal(10,7) | GPS longitude at punch time |
| `accuracy_m` | decimal(8,2) | GPS accuracy in meters |
| `address` | varchar(500) | Reverse-geocoded address (optional) |
| `inside_geofence` | boolean | Whether employee was inside geofence radius |
| `distance_m` | int | Distance from branch center in meters |
| `selfie_path` | varchar | Path to stored selfie image |
| `device_info` | JSON | Device metadata (optional) |
| `is_first_of_day` | boolean | First punch-in of the day |
| `is_last_of_day` | boolean | Last punch-out of the day |

### 2.5 `attendance_location_pings` table

| Column | Type | Description |
|--------|------|-------------|
| `id` | bigint | Primary key |
| `session_id` | bigint | FK to attendance_sessions |
| `employee_id` | int | FK to employees |
| `latitude` | decimal(10,7) | GPS latitude |
| `longitude` | decimal(10,7) | GPS longitude |
| `accuracy_m` | decimal(8,2) | GPS accuracy in meters |
| `address` | varchar(500) | Reverse-geocoded address (optional) |
| `inside_geofence` | boolean | Whether inside geofence radius |
| `distance_m` | int | Distance from branch center |
| `battery_pct` | tinyint | Device battery percentage (0-100) |
| `captured_at` | datetime | When the ping was captured on device |
| `received_at` | datetime | When server received the ping |
| `is_queued` | boolean | `true` if this was synced from offline queue |
| `selfie_path` | varchar | Optional selfie with ping |

---

## 3. API Reference

### 3.1 Get Geofence Config

Returns the employee's branch geofence configuration. Call on app launch.

```
GET {{BASE_URL}}/api/me/geofence
```

**Headers:**
```
Authorization: Bearer <token>
Accept: application/json
```

**Success Response (200):**
```json
{
    "status": true,
    "data": {
        "branch_id": 5,
        "branch_name": "Mumbai Office",
        "latitude": 19.076,
        "longitude": 72.8777,
        "radius_m": 200,
        "geofence_attendance": "Yes"
    }
}
```

> **Note:** The radius field is `radius_m` (not `geofence_radius_m`). The response is a flat `data{}` object (not a `branch{}` envelope).

**Error Responses:**

| Code | Scenario |
|------|----------|
| 404 | Employee has no branch assigned |
| 401 | Invalid/expired token |

**Flutter Usage:**
- Call on app start and cache the result
- If `geofence_attendance` is `"No"`, hide all geofence UI
- Use `latitude`, `longitude`, `radius_m` to draw the geofence circle on the map

---

### 3.2 Punch In

Creates a new attendance session. Requires selfie + GPS.

```
POST {{BASE_URL}}/api/attendance/punch-in
```

**Headers:**
```
Authorization: Bearer <token>
Accept: application/json
Content-Type: multipart/form-data
```

**Request Body (multipart/form-data):**

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `selfie` | file | Yes | JPG/JPEG/PNG, max 2MB |
| `latitude` | number | Yes | Between -90 and 90 |
| `longitude` | number | Yes | Between -180 and 180 |
| `accuracy_m` | number | No | Min 0, max 10000 |
| `address` | string | No | Max 500 chars |
| `client_captured_at` | datetime | Yes | ISO 8601 (e.g. `2026-08-29T09:30:00+05:30`) |
| `device_info` | JSON string | No | Valid JSON (e.g. `{"model":"Pixel 7","os":"Android 14"}`) |

**Success Response (200):**
```json
{
    "status": true,
    "message": "Punch-in recorded.",
    "data": {
        "session_id": 142,
        "punch_id": 283,
        "server_time": "2026-08-29T15:00:15+05:30",
        "is_first_of_day": true,
        "geofence": {
            "inside": true,
            "distance_m": 45,
            "radius_m": 200
        }
    }
}
```

> **IMPORTANT:** Save the `session_id` — it is required for all subsequent calls (pings and punch-out).

**Error Responses:**

| HTTP | Error Code | Scenario |
|------|------------|----------|
| 403 | `GEOFENCE_NOT_ENABLED` | Employee's `geofence_attendance` is not `Yes` |
| 409 | `SESSION_ALREADY_OPEN` | Employee already has an active session |
| 409 | `ALREADY_PUNCHED_TODAY` | Employee already completed a punch cycle today (IST) |
| 422 | — | Validation error (missing selfie, invalid GPS, etc.) |
| 429 | — | Rate limited (max 6 requests/minute) |

**Error Examples:**
```json
{
    "status": false,
    "error_code": "SESSION_ALREADY_OPEN",
    "message": "You already have an open session.",
    "data": {
        "session_id": 142,
        "started_at": "2026-08-29T15:00:15.000000Z"
    }
}
```

```json
{
    "status": false,
    "error_code": "ALREADY_PUNCHED_TODAY",
    "message": "You have already completed today's punch-in and punch-out.",
    "data": {
        "session_id": 140,
        "started_at": "2026-08-29T09:00:00.000000Z",
        "ended_at": "2026-08-29T18:00:00.000000Z",
        "duration_seconds": 32400
    }
}
```

```json
{
    "status": false,
    "error_code": "GEOFENCE_NOT_ENABLED",
    "message": "Geofence attendance is not enabled for your account."
}
```

---

### 3.3 Punch Out

Closes the active session. Requires the `session_id` from punch-in.

```
POST {{BASE_URL}}/api/attendance/punch-out
```

**Headers:**
```
Authorization: Bearer <token>
Accept: application/json
Content-Type: multipart/form-data
```

**Request Body (multipart/form-data):**

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `session_id` | integer | Yes | Must exist in attendance_sessions |
| `selfie` | file | Yes | JPG/JPEG/PNG, max 2MB |
| `latitude` | number | Yes | Between -90 and 90 |
| `longitude` | number | Yes | Between -180 and 180 |
| `accuracy_m` | number | No | Min 0, max 10000 |
| `address` | string | No | Max 500 chars |
| `client_captured_at` | datetime | Yes | ISO 8601 format |
| `device_info` | JSON string | No | Valid JSON |

**Success Response (200):**
```json
{
    "status": true,
    "message": "Punch-out recorded.",
    "data": {
        "session_id": 142,
        "punch_id": 284,
        "duration_seconds": 32400,
        "ping_count": 18,
        "is_last_of_day": true,
        "geofence": {
            "inside": true,
            "distance_m": 30,
            "radius_m": 200
        }
    }
}
```

**Error Responses:**

| HTTP | Scenario |
|------|----------|
| 404 | Session not found or does not belong to this employee |
| 409 | Session is not active (already closed) |
| 422 | Validation error |
| 429 | Rate limited (max 6 requests/minute) |

---

### 3.4 Location Ping (Single)

Sends a single GPS location ping during an active session. Call every **30 minutes**.

```
POST {{BASE_URL}}/api/attendance/location-ping
```

**Headers:**
```
Authorization: Bearer <token>
Accept: application/json
Content-Type: multipart/form-data
```

> **Note:** This endpoint also accepts `Content-Type: application/json` when no selfie file is attached.

**Request Body:**

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `session_id` | integer | Yes | Must exist in attendance_sessions |
| `latitude` | number | Yes | Between -90 and 90 |
| `longitude` | number | Yes | Between -180 and 180 |
| `accuracy_m` | number | No | Min 0, max 10000 |
| `address` | string | No | Max 500 chars |
| `battery_pct` | integer | No | Between 0 and 100. `null` is accepted. |
| `captured_at` | datetime | Yes | ISO 8601 format |
| `selfie` | file | No | JPG/JPEG/PNG, max 2MB (optional periodic selfie) |

**Success Response (200):**
```json
{
    "status": true,
    "data": {
        "ping_id": 567,
        "selfie_url": null
    }
}
```

**Error Responses:**

| HTTP | Scenario |
|------|----------|
| 404 | Session not found or doesn't belong to employee |
| 409 | Session is not active |
| 422 | Validation error |
| 429 | Rate limited (max 30 requests/minute) |

---

### 3.5 Location Ping Batch (Offline Sync)

Sends multiple queued pings at once when the device comes back online.

```
POST {{BASE_URL}}/api/attendance/location-ping/batch
```

**Headers:**
```
Authorization: Bearer <token>
Accept: application/json
Content-Type: multipart/form-data
```

> **Note:** This endpoint also accepts `Content-Type: application/json` when no selfie files are attached. Extra keys like `is_queued` in the pings array are silently ignored.

**Request Body:**

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `pings` | JSON string or array | Yes | Min 1, max 100 items (max 20 if selfies attached) |
| `selfie_0`, `selfie_1`, ... | file | No | JPG/JPEG/PNG, max 2MB each. Index matches ping array index. |

**Pings Array Structure:**
```json
[
    {
        "session_id": 142,
        "latitude": 19.0760,
        "longitude": 72.8777,
        "accuracy_m": 15.5,
        "address": "Andheri East, Mumbai",
        "battery_pct": 85,
        "captured_at": "2026-08-29T10:00:00+05:30"
    },
    {
        "session_id": 142,
        "latitude": 19.0762,
        "longitude": 72.8779,
        "accuracy_m": 12.0,
        "battery_pct": 82,
        "captured_at": "2026-08-29T10:30:00+05:30"
    }
]
```

**Success Response (200):**
```json
{
    "status": true,
    "data": {
        "accepted": 2,
        "rejected": [],
        "ping_ids": [568, 569],
        "selfie_urls": [null, null]
    }
}
```

**Partial Success (some pings rejected):**
```json
{
    "status": true,
    "data": {
        "accepted": 1,
        "rejected": [
            { "index": 1, "reason": "SESSION_NOT_ACTIVE" }
        ],
        "ping_ids": [568],
        "selfie_urls": [null]
    }
}
```

**Error Responses:**

| HTTP | Scenario |
|------|----------|
| 422 | Validation error (invalid JSON, exceeds max items) |
| 429 | Rate limited (max 30 requests/minute) |

**Flutter Notes:**
- Send `pings` as a JSON string in multipart form, or as a JSON array in a JSON body
- Attach selfie files as `selfie_0`, `selfie_1`, etc. — index matches the ping array index
- Max 20 pings per batch with selfies; max 100 without
- On success, remove accepted pings from the offline queue
- Retry rejected pings only if the reason is transient (network error), not for `SESSION_NOT_ACTIVE`

---

### 3.6 Get Today's Summary

Returns today's attendance data — active session, all punches, and total work time.

```
GET {{BASE_URL}}/api/attendance/today
```

**Headers:**
```
Authorization: Bearer <token>
Accept: application/json
```

**Success Response (200):**
```json
{
    "status": true,
    "data": {
        "active_session": {
            "session_id": 142,
            "started_at": "2026-08-29T15:00:15+05:30",
            "ping_count": 5,
            "last_ping": {
                "latitude": 19.0761,
                "longitude": 72.8778,
                "captured_at": "2026-08-29T17:30:00+05:30"
            }
        },
        "punches": [
            {
                "session_id": 142,
                "type": "in",
                "punched_at": "2026-08-29T15:00:15+05:30",
                "latitude": 19.076,
                "longitude": 72.8777,
                "accuracy_m": 15.5,
                "address": "Andheri East, Mumbai",
                "selfie_url": "https://yourdomain.com/storage/attendance/2026/08/123_1724920215.jpg",
                "inside_geofence": true,
                "distance_m": 45
            }
        ],
        "total_seconds": 0
    }
}
```

> `total_seconds` only counts **closed** sessions. While a session is active, calculate elapsed time client-side using `active_session.started_at`.

**When no activity today:**
```json
{
    "status": true,
    "data": {
        "active_session": null,
        "punches": [],
        "total_seconds": 0
    }
}
```

**Important fields in `punches[]`:**
- `session_id` — use this to call `/session/{id}/timeline` for the ping trail
- `latitude`, `longitude` — **required** for map rendering. If these are null, the punch cannot be plotted.

---

### 3.7 Get History

Returns sessions and pings for a specific date.

```
GET {{BASE_URL}}/api/attendance/history?date=2026-08-28
```

**Query Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `date` | string | Yes | Format: `YYYY-MM-DD` (IST calendar date) |
| `user_id` | integer | No | Admin only — view another employee's history |

**Success Response (200):**
```json
{
    "status": true,
    "data": {
        "date": "2026-08-28",
        "total_seconds": 32400,
        "sessions": [
            {
                "session_id": 140,
                "started_at": "2026-08-28T09:15:00+05:30",
                "ended_at": "2026-08-28T18:15:00+05:30",
                "duration_seconds": 32400,
                "status": "closed",
                "punches": [
                    {
                        "session_id": 140,
                        "type": "in",
                        "punched_at": "2026-08-28T09:15:00+05:30",
                        "latitude": 19.076,
                        "longitude": 72.8777,
                        "accuracy_m": 12.3,
                        "address": "Andheri East, Mumbai",
                        "selfie_url": "https://yourdomain.com/storage/attendance/2026/08/123_xxx.jpg",
                        "inside_geofence": true,
                        "distance_m": 30
                    },
                    {
                        "session_id": 140,
                        "type": "out",
                        "punched_at": "2026-08-28T18:15:00+05:30",
                        "latitude": 19.0758,
                        "longitude": 72.8775,
                        "accuracy_m": 10.1,
                        "address": "Andheri East, Mumbai",
                        "selfie_url": "https://yourdomain.com/storage/attendance/2026/08/123_xxx.jpg",
                        "inside_geofence": true,
                        "distance_m": 25
                    }
                ],
                "pings": [
                    {
                        "latitude": 19.076,
                        "longitude": 72.8777,
                        "captured_at": "2026-08-28T09:45:00+05:30",
                        "inside_geofence": true,
                        "accuracy_m": 14.0,
                        "selfie_url": null
                    }
                ]
            }
        ]
    }
}
```

> `total_seconds` is the sum of `duration_seconds` across all **closed** sessions for the day.

---

### 3.8 Get Session Timeline

Returns the full movement trail for a session — punch-in, all pings, punch-out. Use this to draw a polyline on the map.

```
GET {{BASE_URL}}/api/attendance/session/{session_id}/timeline
```

**Success Response (200):**
```json
{
    "status": true,
    "data": {
        "session": {
            "id": 142,
            "employee_id": 123,
            "started_at": "2026-08-29T15:00:15+05:30",
            "ended_at": "2026-08-29T23:30:15+05:30",
            "status": "closed"
        },
        "punch_in": {
            "latitude": 19.076,
            "longitude": 72.8777,
            "punched_at": "2026-08-29T15:00:15+05:30",
            "selfie_url": "https://yourdomain.com/storage/attendance/2026/08/123_xxx.jpg",
            "inside_geofence": true
        },
        "punch_out": {
            "latitude": 19.0758,
            "longitude": 72.8775,
            "punched_at": "2026-08-29T23:30:15+05:30",
            "selfie_url": "https://yourdomain.com/storage/attendance/2026/08/123_xxx.jpg",
            "inside_geofence": true
        },
        "pings": [
            {
                "latitude": 19.0761,
                "longitude": 72.8778,
                "captured_at": "2026-08-29T15:30:00+05:30",
                "inside_geofence": true,
                "accuracy_m": 14.0,
                "selfie_url": null
            }
        ]
    }
}
```

**Access Control:**
- Employee: can view own sessions only
- Admin: can view any employee's sessions

**How to use for map:**
1. Plot `punch_in` as a green marker
2. Plot each `pings[]` item as a blue dot
3. Plot `punch_out` as a red marker
4. Draw a polyline connecting all points in order

---

### 3.9 Live Sessions (Admin Only)

Returns all currently active sessions across the organization.

```
GET {{BASE_URL}}/api/attendance/live
```

**Query Parameters:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `branch_id` | integer | No | Filter by branch |
| `limit` | integer | No | Max results (default: 100) |

**Success Response (200):**
```json
{
    "status": true,
    "data": [
        {
            "session_id": 142,
            "employee": {
                "id": 123,
                "emp_name": "Rajesh Kumar",
                "emp_code": "EMP001"
            },
            "branch": {
                "id": 5,
                "branch_name": "Mumbai Office"
            },
            "started_at": "2026-08-29T15:00:15+05:30",
            "ping_count": 5,
            "last_ping": {
                "latitude": 19.0761,
                "longitude": 72.8778,
                "inside_geofence": true,
                "captured_at": "2026-08-29T17:30:00+05:30"
            }
        }
    ]
}
```

**Error Responses:**

| HTTP | Scenario |
|------|----------|
| 403 | Not an admin user |

---

## 4. Step-by-Step Flutter Integration Flow

### 4.1 Complete Lifecycle

```
APP LAUNCH
    │
    v
GET /api/me/geofence
    │                    │
    geofence_attendance  geofence_attendance
       = "Yes"              = "No"
    │                        │
    v                        v
Show Punch UI          Hide Geofence UI
    │
    v
GET /api/attendance/today
    │                    │
    active_session       no active_session
    exists                   │
    │                        v
    │                  Show "Punch In" button
    │                        │
    │               [User taps Punch In]
    │                        │
    │                  1. Capture selfie
    │                  2. Get GPS location
    │                  3. POST /api/attendance/punch-in
    │                        │
    │                  Save session_id locally
    │                        │
    v                        v
┌────── ACTIVE SESSION ──────┐
│                            │
│  Show "Punch Out" button   │
│  Start 30-min ping timer   │
│         │                  │
│  [Every 30 min]            │
│         │                  │
│   POST /location-ping      │
│   (or queue if offline)    │
│         │                  │
│  [User taps Punch Out]     │
│         │                  │
│   1. Sync queued pings     │
│   2. Capture selfie        │
│   3. POST /punch-out       │
│         │                  │
└────── SESSION CLOSED ──────┘
         │
   Show summary:
   duration, ping_count
```

### 4.2 Step-by-Step Implementation

#### Step 1: Check Geofence Config (App Launch)

```dart
// Call GET /api/me/geofence
// Cache the response
// If geofence_attendance == "Yes":
//   - Store branch lat/lng/radius_m locally
//   - Enable geofence features
// If geofence_attendance == "No":
//   - Disable/hide all geofence UI
```

#### Step 2: Check Today's Status

```dart
// Call GET /api/attendance/today
// If active_session != null:
//   - Resume tracking (show punch-out button, restart ping timer)
//   - Use active_session.session_id
// If active_session == null && punches is empty:
//   - Show "Punch In" button
// If active_session == null && punches has in+out:
//   - Show "Already completed today" with total_seconds summary
// IMPORTANT: Use punches[].session_id to call /session/{id}/timeline
```

#### Step 3: Punch In

```dart
// 1. Disable punch button immediately (prevent double-tap)
// 2. Request camera permission, capture selfie (front camera)
// 3. Request location permission, get current GPS
// 4. POST /api/attendance/punch-in with:
//    - selfie file
//    - latitude, longitude, accuracy_m
//    - client_captured_at (ISO 8601 with timezone)
//    - device_info (optional JSON)
// 5. On success: save session_id, start background ping timer
// 6. On error: show message based on error_code, re-enable button
```

#### Step 4: Background Location Pings

```dart
// Every 30 minutes while session is active:
// 1. Get current GPS location
// 2. Get battery percentage
// 3. If ONLINE:
//    - POST /api/attendance/location-ping
// 4. If OFFLINE:
//    - Queue ping locally with captured_at timestamp
//    - When online: POST /api/attendance/location-ping/batch
```

#### Step 5: Offline Queue Management

```dart
// Store queued pings in local DB (SQLite/Hive):
// {
//   session_id: int,
//   latitude: double,
//   longitude: double,
//   accuracy_m: double,
//   battery_pct: int,
//   captured_at: String (ISO 8601),
//   address: String? (optional)
// }
//
// When connectivity resumes:
// 1. Collect all queued pings (max 100 per batch)
// 2. POST /api/attendance/location-ping/batch
// 3. Remove accepted pings from local queue
// 4. Keep rejected pings only if reason is transient
```

#### Step 6: Punch Out

```dart
// 1. First, sync any queued offline pings (batch endpoint)
// 2. Capture selfie (front camera)
// 3. Get current GPS location
// 4. POST /api/attendance/punch-out with:
//    - session_id
//    - selfie file
//    - latitude, longitude, accuracy_m
//    - client_captured_at
// 5. On success:
//    - Stop ping timer
//    - Clear local session data
//    - Show duration summary (duration_seconds)
```

### 4.3 Selfie Requirements

| Requirement | Detail |
|-------------|--------|
| Camera | Front-facing (selfie) camera |
| Format | JPG or PNG |
| Max size | 2 MB (2048 KB) |
| Compression | Compress to ~80% quality before upload |
| Resolution | Reasonable (e.g. 640x480 to 1280x960) |

### 4.4 GPS Requirements

| Requirement | Detail |
|-------------|--------|
| Accuracy | Should be < 100m. Send `accuracy_m` so backend can track quality. |
| Timeout | Set a GPS timeout (e.g. 30 seconds). Show error if not obtained. |
| Permissions | `ACCESS_FINE_LOCATION` (Android) / `whenInUse` + `always` (iOS) |
| Background | **Must request "Allow all the time"** for background pings to work |

### 4.5 Recommended Ping Interval

- **Default:** Every 30 minutes
- **Implementation:** Use `WorkManager` (Android) / `BGTaskScheduler` (iOS)
- **Battery-aware:** If `battery_pct` < 15%, consider reducing frequency or notifying user
- **Foreground service:** Recommended for OEM battery-manager survival on Android

---

## 5. Error Codes & Handling

### Error Response Format

All error responses follow this structure:

```json
{
    "status": false,
    "error_code": "ERROR_CODE",
    "message": "Human-readable message"
}
```

> **Key name is `error_code`** (not `code`).

### Complete Error Code Table

| Error Code | HTTP | Endpoint | Flutter Action |
|------------|------|----------|----------------|
| `GEOFENCE_NOT_ENABLED` | 403 | punch-in | Show "Geofence attendance is not enabled for your account." Hide punch UI. |
| `SESSION_ALREADY_OPEN` | 409 | punch-in | Response includes `data.session_id`. Resume that session — show punch-out and restart pings. |
| `ALREADY_PUNCHED_TODAY` | 409 | punch-in | Show "You have already completed your attendance for today." Show summary from `data`. |
| Session not found | 404 | punch-out, ping | Clear local session_id. Call `GET /today` to check actual state. |
| Session not active | 409 | punch-out, ping | Session was already closed (possibly by admin). Clear local session. Refresh status. |
| Validation error | 422 | all | Parse `errors` object. Show specific field errors. |
| Rate limited | 429 | all | Retry after delay with exponential backoff. For pings, queue and retry later. |
| Unauthorized | 401 | all | Token expired. Redirect to login screen. |

### Rate Limits

| Endpoint | Limit |
|----------|-------|
| Punch In / Punch Out | 6 requests per minute |
| Location Ping (single) | 30 requests per minute |
| Location Ping (batch) | 30 requests per minute |

---

## 6. Notes & Caveats

### 6.1 Geofence is Track-Only

Out-of-fence punches are **allowed and recorded** — they are flagged with `inside_geofence: false` and `distance_m` for admin review but **not blocked**. The app should show the user whether they are inside/outside, but should **not** block the punch action.

### 6.2 No Geofence Check on Punch-Out

The punch-out endpoint does **not** verify if `geofence_attendance` is still enabled. If an admin disables geofence mid-session, the employee can still punch out. This is intentional — avoids stranding an open session.

### 6.3 Selfie Storage

- Selfies are stored at `storage/app/public/attendance/{YYYY}/{MM}/{emp_id}_{timestamp}.jpg`
- Served via the `public/storage` symlink (`php artisan storage:link` must be run on server)
- URLs are in format: `https://domain.com/storage/attendance/2026/08/123_xxx.jpg`
- If a selfie URL returns 404, the file is missing on disk (not a code issue)

### 6.4 Timezone

- Server timezone is `Asia/Kolkata` (IST). All `now()` calls return IST.
- The `date` column in sessions stores the IST calendar date.
- `ALREADY_PUNCHED_TODAY` and `/today` both use the same IST boundary — no timezone mismatch.
- `client_captured_at`: send in any format Laravel can parse (UTC with `Z` or IST with `+05:30` — both work).

### 6.5 Concurrent Punch-In Protection

The active-session check runs inside a database transaction with `lockForUpdate()`. Two concurrent punch-in requests (double-tap, multi-device) will serialize — the second sees the session created by the first and receives `SESSION_ALREADY_OPEN`.

**Flutter side:** Still disable the button on first tap as a UX safeguard.

### 6.6 Geofence Distance Calculation

The backend uses the **Haversine formula** (great-circle distance):

```
distance = haversine(branch.lat, branch.lng, punch.lat, punch.lng)
inside_geofence = (distance <= branch.geofence_radius_m)
```

Distance is always stored in `distance_m` regardless of inside/outside status.

---

## Appendix: Quick Reference

### All API Endpoints

| Method | Endpoint | Purpose | Auth |
|--------|----------|---------|------|
| GET | `/api/me/geofence` | Get geofence config | Employee |
| POST | `/api/attendance/punch-in` | Start session (multipart) | Employee |
| POST | `/api/attendance/punch-out` | End session (multipart) | Employee |
| POST | `/api/attendance/location-ping` | Send GPS ping (multipart or JSON) | Employee |
| POST | `/api/attendance/location-ping/batch` | Batch sync pings (multipart or JSON) | Employee |
| GET | `/api/attendance/today` | Today's summary | Employee |
| GET | `/api/attendance/history?date=YYYY-MM-DD` | History for date | Employee/Admin |
| GET | `/api/attendance/session/{id}/timeline` | Session movement trail | Employee/Admin |
| GET | `/api/attendance/live` | All active sessions | Admin only |

### Data Types in JSON Responses

All numeric fields are serialized as JSON numbers (not strings):
- `latitude`, `longitude`, `accuracy_m` → `float`
- `distance_m`, `geofence_radius_m`, `radius_m`, `battery_pct`, `ping_count`, `duration_seconds`, `total_seconds` → `integer`
- `inside_geofence`, `is_first_of_day`, `is_last_of_day` → `boolean`
