# Geofence Live Dashboard - Mobile API Documentation

**Base URL:** `https://hrms.mecpl.in/api`  
**Auth:** Bearer Token (Sanctum) — `Authorization: Bearer {token}`  
**Content-Type:** `application/json`  
**Access:** ADMIN and DIRECTOR roles only

---

## Overview

The Geofence Live Dashboard API provides real-time visibility into employee geofence attendance sessions. It mirrors the web dashboard at `/attendance/geofence-map` and includes:

- **Live employee locations** with inside/outside geofence status
- **Summary counts** (total today, active now, completed, outside fence)
- **Branch geofence circles** (center coordinates + radius)
- **Session route trails** (punch-in → location pings → punch-out)

---

## Authentication

All endpoints require a valid Sanctum Bearer token from an employee with **ADMIN** or **DIRECTOR** role.

### Login

**Endpoint:** `POST /api/check_login_api`

**Request Body:**
```json
{
    "emp_code": "1234",
    "password": "your_password",
    "device_name": "Samsung Galaxy S24",
    "os_version": "Android 14",
    "app_version": "1.0.0",
    "fcm_token": "firebase_token_here"
}
```

**Response (200):**
```json
{
    "status": true,
    "message": "Login successful",
    "token": "1|abc123xyz456..."
}
```

Use the token in all subsequent requests:
```
Authorization: Bearer 1|abc123xyz456...
```

---

## Endpoints

### 1. Geofence Live Dashboard Data

Fetches all employee attendance sessions for a given date, their current locations, inside/outside status, and branch geofence definitions.

**Endpoint:** `GET /api/attendance/geofence-live`

**Parameters (query string, all optional):**

| Parameter   | Type   | Default       | Description                              |
|-------------|--------|---------------|------------------------------------------|
| `date`      | string | Today (IST)   | Date in `YYYY-MM-DD` format              |
| `branch_id` | int    | All branches  | Filter employees by specific branch ID   |

**Example Request:**
```
GET /api/attendance/geofence-live?date=2026-09-19&branch_id=5
Authorization: Bearer {token}
```

**Response (200 - Success):**
```json
{
    "status": true,
    "message": "Geofence live dashboard data.",
    "data": {
        "date": "2026-09-19",
        "summary": {
            "total_today": 5,
            "active_now": 5,
            "completed": 0,
            "outside_fence": 3
        },
        "employees": [
            {
                "session_id": 1234,
                "emp_id": 56,
                "emp_name": "AKSHAY KUMAR GAIKWAD",
                "emp_code": "11230",
                "emp_image_url": "https://hrms.mecpl.in/files/employee/photo.jpg",
                "department": "SALES",
                "branch_name": "HEAD OFFICE",
                "latitude": 18.5912,
                "longitude": 73.7389,
                "inside_geofence": true,
                "captured_at": {
                    "iso": "2026-09-19T09:45:00+05:30",
                    "time": "09:45 AM",
                    "date": "19 Sep 2026",
                    "full": "19 Sep 2026, 09:45 AM"
                },
                "started_at": {
                    "iso": "2026-09-19T08:45:00+05:30",
                    "time": "08:45 AM",
                    "date": "19 Sep 2026",
                    "full": "19 Sep 2026, 08:45 AM"
                },
                "ended_at": null,
                "duration_seconds": 3600,
                "ping_count": 12,
                "battery_pct": 72,
                "distance_m": 15,
                "status": "active",
                "shift_end_time": null,
                "punch_in_selfie": "https://hrms.mecpl.in/storage/attendance/selfie_in.jpg",
                "punch_out_selfie": null
            }
        ],
        "branches": [
            {
                "id": 5,
                "branch_name": "HEAD OFFICE",
                "latitude": 18.5913,
                "longitude": 73.7390,
                "geofence_radius_m": 200
            }
        ]
    }
}
```

---

### 2. Session Timeline / Route Trail

Fetches the complete movement trail for a specific employee session — punch-in point, all location pings in chronological order, and punch-out point. Use this to draw the route on a map.

**Endpoint:** `GET /api/attendance/geofence-timeline`

**Parameters (query string):**

| Parameter    | Type | Required | Description                       |
|--------------|------|----------|-----------------------------------|
| `session_id` | int  | Yes      | The attendance session ID         |

**Example Request:**
```
GET /api/attendance/geofence-timeline?session_id=1234
Authorization: Bearer {token}
```

**Response (200 - Success):**
```json
{
    "status": true,
    "message": "Session timeline data.",
    "data": {
        "points": [
            {
                "type": "punch_in",
                "latitude": 18.5912,
                "longitude": 73.7389,
                "time": "2026-09-19T08:45:00+05:30"
            },
            {
                "type": "ping",
                "latitude": 18.5915,
                "longitude": 73.7392,
                "time": "2026-09-19T09:00:00+05:30",
                "battery_pct": 85,
                "distance_m": 25
            },
            {
                "type": "ping",
                "latitude": 18.5910,
                "longitude": 73.7388,
                "time": "2026-09-19T09:15:00+05:30",
                "battery_pct": 82,
                "distance_m": 12
            },
            {
                "type": "punch_out",
                "latitude": 18.5913,
                "longitude": 73.7390,
                "time": "2026-09-19T18:00:00+05:30"
            }
        ]
    }
}
```

---

## Error Responses

All errors follow the same format:

```json
{
    "status": false,
    "message": "Error description"
}
```

| HTTP Code | Message                              | When                                          |
|-----------|--------------------------------------|-----------------------------------------------|
| 401       | `Unauthenticated.`                   | Missing or invalid Bearer token               |
| 403       | `Admin or Director access required.` | User role is not ADMIN or DIRECTOR            |
| 404       | `Session not found.`                 | Invalid `session_id` in timeline request      |
| 422       | Validation error object              | Invalid `date` format or `session_id` missing |

**422 Validation Error Example:**
```json
{
    "message": "The date field must match the format Y-m-d.",
    "errors": {
        "date": ["The date field must match the format Y-m-d."]
    }
}
```

---

## Field Reference

### Employee Object

| Field              | Type         | Nullable | Description                                                                |
|--------------------|--------------|----------|----------------------------------------------------------------------------|
| `session_id`       | int          | No       | Unique attendance session ID                                               |
| `emp_id`           | int          | Yes      | Employee ID                                                                |
| `emp_name`         | string       | No       | Full name (defaults to "Unknown")                                          |
| `emp_code`         | string       | No       | Employee code (e.g., "11230")                                              |
| `emp_image_url`    | string\|null | Yes      | Full URL to employee profile photo                                         |
| `department`       | string       | No       | Department name (defaults to "-")                                          |
| `branch_name`      | string       | No       | Branch where session is active                                             |
| `latitude`         | float\|null  | Yes      | Last known latitude (from latest ping or punch-in)                         |
| `longitude`        | float\|null  | Yes      | Last known longitude                                                       |
| `inside_geofence`  | bool\|null   | Yes      | `true` = inside fence, `false` = outside, `null` = no location data        |
| `captured_at`      | object\|null | Yes      | Timestamp of last location update (IST formatted — see Time Object below)  |
| `started_at`       | object\|null | Yes      | Punch-in time (IST formatted)                                              |
| `ended_at`         | object\|null | Yes      | Punch-out time, `null` if session still active (IST formatted)             |
| `duration_seconds` | int\|null    | Yes      | Session duration in seconds                                                |
| `ping_count`       | int          | No       | Number of location pings received                                          |
| `battery_pct`      | int\|null    | Yes      | Last known device battery percentage                                       |
| `distance_m`       | int\|null    | Yes      | Distance from geofence center in meters                                    |
| `status`           | string       | No       | `"active"`, `"closed"`, or `"force_closed"`                                |
| `shift_end_time`   | object\|null | Yes      | Set only for force_closed sessions without punch-out (shift end as IST)    |
| `punch_in_selfie`  | string\|null | Yes      | Full URL to punch-in selfie image                                          |
| `punch_out_selfie` | string\|null | Yes      | Full URL to punch-out selfie image                                         |

### Time Object (IST Formatted)

Timestamps are returned as objects with multiple formats for convenience:

```json
{
    "iso": "2026-09-19T09:45:00+05:30",
    "time": "09:45 AM",
    "date": "19 Sep 2026",
    "full": "19 Sep 2026, 09:45 AM"
}
```

| Field  | Format              | Use Case                      |
|--------|---------------------|-------------------------------|
| `iso`  | ISO 8601 with +05:30| Parsing / sorting in code     |
| `time` | `hh:mm AM/PM`       | Display "First seen" / "Last seen" |
| `date` | `dd MMM YYYY`       | Display date labels           |
| `full` | `dd MMM YYYY, hh:mm AM/PM` | Full timestamp display  |

### Summary Object

| Field           | Type | Description                                                     |
|-----------------|------|-----------------------------------------------------------------|
| `total_today`   | int  | Total employees with sessions today                             |
| `active_now`    | int  | Employees with `status = "active"` (currently working)          |
| `completed`     | int  | Employees with `status = "closed"` or `"force_closed"`          |
| `outside_fence` | int  | Active employees whose last location is **outside** the geofence|

### Branch Object

| Field              | Type  | Description                          |
|--------------------|-------|--------------------------------------|
| `id`               | int   | Branch ID (use for filtering)        |
| `branch_name`      | string| Branch display name                  |
| `latitude`         | float | Geofence center latitude             |
| `longitude`        | float | Geofence center longitude            |
| `geofence_radius_m`| int   | Geofence radius in meters            |

### Timeline Point Object

| Field         | Type        | Description                                     |
|---------------|-------------|-------------------------------------------------|
| `type`        | string      | `"punch_in"`, `"ping"`, or `"punch_out"`        |
| `latitude`    | float       | Point latitude                                  |
| `longitude`   | float       | Point longitude                                 |
| `time`        | string      | ISO 8601 timestamp in IST (`+05:30`)            |
| `battery_pct` | int\|null   | Battery % (only on `"ping"` type)               |
| `distance_m`  | int\|null   | Distance from geofence center (only on `"ping"`)  |

---

## Data Flow & Integration Guide

### Dashboard Screen Flow

```
1. App opens Geofence Live Dashboard screen
                    |
2. GET /api/attendance/geofence-live
   (optional: ?branch_id=X&date=YYYY-MM-DD)
                    |
3. Parse response:
   - Display summary cards (total_today, active_now, completed, outside_fence)
   - Render employee list (left panel)
   - Plot employee markers on map using latitude/longitude
   - Draw geofence circles using branches[].latitude, longitude, geofence_radius_m
                    |
4. Auto-refresh every 60 seconds (same GET request)
                    |
5. User taps employee → "Show Route"
                    |
6. GET /api/attendance/geofence-timeline?session_id={session_id}
                    |
7. Draw route on map:
   - Green marker = punch_in point
   - Blue markers = ping points
   - Red marker = punch_out point
   - Polyline connecting all points in order
```

### Employee Status Mapping

| Status         | Meaning                                      | UI Treatment                    |
|----------------|----------------------------------------------|---------------------------------|
| `active`       | Employee is currently working, session open  | Green dot, show in "Active" tab |
| `closed`       | Employee punched out normally                | Grey dot, show in "Completed" tab |
| `force_closed` | Session auto-closed by system (shift ended)  | Grey dot, show in "Completed" tab |

### Inside/Outside Geofence Display

| `inside_geofence` | Label     | Color  | Map Marker Border |
|--------------------|-----------|--------|-------------------|
| `true`             | "Inside"  | Green  | Green border      |
| `false`            | "Outside" | Red    | Red border        |
| `null`             | "Unknown" | Grey   | Grey border       |

### Client-Side Search

The API returns **all employees** for the selected branch/date. Implement search filtering locally in Flutter by matching against `emp_name` and `emp_code` fields.

### Branch Filter

To populate the branch dropdown:
- Use the `branches` array from the geofence-live response
- Each branch has `id` and `branch_name`
- Pass selected `branch_id` as query parameter to filter results
- Omit `branch_id` to show all branches

### Image URLs

- **Employee photo** (`emp_image_url`): Full URL, can be `null` — show initials avatar as fallback
- **Punch selfies** (`punch_in_selfie`, `punch_out_selfie`): Full URL, can be `null` — hide if null
- All URLs are absolute and ready to use directly in `Image.network()` or `CachedNetworkImage`

### Refresh Strategy

- Auto-refresh every **60 seconds** (same as web version)
- Show a countdown timer in the UI
- Provide a manual "Refresh" button
- On refresh, call the same `geofence-live` endpoint with current filters

### Duration Display

Convert `duration_seconds` to human-readable format:
```
duration_seconds = 5400
→ "1h 30m"

duration_seconds = 28800
→ "8h 00m"
```

### Force-Closed Sessions

When `status = "force_closed"` and `shift_end_time` is not null:
- The session was auto-closed because the employee's shift ended
- `ended_at` will show the shift end time (not an actual punch-out)
- `punch_out_selfie` will be `null` (no physical punch-out happened)
- Display this differently in UI (e.g., "Auto-closed at {shift_end_time.time}")

---

## Quick Reference

| Action                     | Method | Endpoint                              | Key Params              |
|----------------------------|--------|---------------------------------------|-------------------------|
| Get live dashboard data    | GET    | `/api/attendance/geofence-live`       | `date`, `branch_id`    |
| Get employee route trail   | GET    | `/api/attendance/geofence-timeline`   | `session_id` (required)|
