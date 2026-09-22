# Geofencing & Mobile Attendance - API Reference

**Base URL:** `https://hrms.mecpl.in/api`  
**Auth:** All endpoints require `Authorization: Bearer <sanctum_token>` header  
**Accept Header:** `Accept: application/json` (required on all requests)

---

## 1. Login (Get Token)

```
POST /api/check_login_api
Content-Type: application/json
```

**Request Body:**
```json
{
    "emp_code": "1104",
    "password": "your_password"
}
```

**Success Response (200):**
```json
{
    "status": true,
    "message": "Login successful",
    "token": "1|abc123xyz456...",
    "user": {
        "name": "John Doe",
        "email": "john@mecpl.in",
        "mobile": "9876543210",
        "emp_code": "1104",
        "designation": "Software Engineer",
        "department": "IT",
        "user_id": 123,
        "role": "ADMIN",
        "branch_id": 12
    }
}
```

**Error Responses:**
| Code | Condition |
|------|-----------|
| 401 | Invalid credentials |
| 403 | Login not allowed for this employee |
| 410 | Account deleted |
| 423 | Password reset required (`force_reset: true`) |

> Save the `token` value. Use it as `Authorization: Bearer <token>` for all APIs below.

---

## 2. Get My Geofence

Fetches the geofence config for the employee's assigned branch. Call this on app launch to configure the geofence circle.

```
GET /api/me/geofence
Authorization: Bearer <token>
Accept: application/json
```

**No request body needed.**

**Success Response (200):**
```json
{
    "status": true,
    "data": {
        "branch_id": 12,
        "branch_name": "HEAD OFFICE",
        "latitude": 18.5743404,
        "longitude": 73.7736299,
        "radius_m": 200
    }
}
```

**Error Responses:**
| Code | Message | Meaning |
|------|---------|---------|
| 404 | No branch assigned to this employee | Employee has no branch in emp_company_details |

**Notes:**
- `radius_m` can be `null` if admin hasn't configured geofence for this branch
- If `radius_m` is null, treat as "no geofence" (all punches will be marked inside)

---

## 3. Punch In

Records a punch-in with GPS + selfie. Creates a new attendance session.

```
POST /api/attendance/punch-in
Authorization: Bearer <token>
Accept: application/json
Content-Type: multipart/form-data
```

**Request Fields (multipart/form-data):**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `selfie` | File | Yes | JPG/JPEG/PNG image, max 2MB |
| `latitude` | Number | Yes | GPS latitude (-90 to 90) |
| `longitude` | Number | Yes | GPS longitude (-180 to 180) |
| `accuracy_m` | Number | No | GPS accuracy in meters |
| `address` | String | No | Reverse-geocoded address, max 500 chars |
| `client_captured_at` | DateTime | Yes | ISO 8601 timestamp from device clock |
| `device_info` | JSON String | No | Device metadata as JSON string |

**Example Request (Dart):**
```dart
var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/attendance/punch-in'));
request.headers['Authorization'] = 'Bearer $token';
request.headers['Accept'] = 'application/json';

request.files.add(await http.MultipartFile.fromPath('selfie', selfieFile.path));
request.fields['latitude'] = '18.5743404';
request.fields['longitude'] = '73.7736299';
request.fields['accuracy_m'] = '8.5';
request.fields['address'] = 'Pune HQ, Hinjewadi';
request.fields['client_captured_at'] = '2026-04-21T09:00:00+05:30';
request.fields['device_info'] = jsonEncode({
    "platform": "android",
    "model": "Pixel 7",
    "os_version": "14",
    "app_version": "1.0.0",
    "battery_pct": 85
});
```

**Success Response (200):**
```json
{
    "status": true,
    "message": "Punch-in recorded.",
    "data": {
        "session_id": 1,
        "punch_id": 1,
        "server_time": "2026-04-21T09:00:05+05:30",
        "is_first_of_day": true,
        "geofence": {
            "inside": true,
            "distance_m": 15,
            "radius_m": 200
        }
    }
}
```

**Error Responses:**
| Code | error_code | Message | Action |
|------|------------|---------|--------|
| 409 | SESSION_ALREADY_OPEN | You already have an open session | Show existing `session_id` and `started_at` from response `data` |
| 422 | - | No branch assigned | Employee has no branch |
| 422 | - | Validation error | Check selfie format/size, lat/lng range |
| 429 | - | Too Many Requests | Rate limited (max 6/minute) |

> **IMPORTANT:** Save `data.session_id` from the response. You need it for location pings and punch-out.

> **Note:** Out-of-fence punches are NOT rejected. They return `inside: false` with the actual `distance_m`. The backend flags them for admin review.

---

## 4. Location Ping (Single)

Send GPS location during an active session. The app should send this every 30 minutes.

```
POST /api/attendance/location-ping
Authorization: Bearer <token>
Accept: application/json
Content-Type: application/json
```

**Request Body:**
```json
{
    "session_id": 1,
    "latitude": 18.5740,
    "longitude": 73.7735,
    "accuracy_m": 10.0,
    "address": "Near Pune HQ",
    "battery_pct": 85,
    "captured_at": "2026-04-21T09:30:00+05:30"
}
```

**Field Details:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `session_id` | Integer | Yes | From punch-in response |
| `latitude` | Number | Yes | GPS latitude (-90 to 90) |
| `longitude` | Number | Yes | GPS longitude (-180 to 180) |
| `accuracy_m` | Number | No | GPS accuracy in meters |
| `address` | String | No | Reverse-geocoded address, max 500 chars |
| `battery_pct` | Integer | No | Battery percentage (0-100) |
| `captured_at` | DateTime | Yes | ISO 8601 timestamp when location was captured |

**Success Response (200):**
```json
{
    "status": true,
    "data": {
        "ping_id": 1
    }
}
```

**Error Responses:**
| Code | Message | Meaning |
|------|---------|---------|
| 404 | Session not found | Invalid session_id or doesn't belong to this employee |
| 409 | Session is not active | Session already closed (punched out) |
| 429 | Too Many Requests | Rate limited (max 30/minute) |

---

## 5. Location Ping Batch (Offline Sync)

When the app was offline, queue pings locally and flush them in one batch when connectivity returns. Max 100 pings per request.

```
POST /api/attendance/location-ping/batch
Authorization: Bearer <token>
Accept: application/json
Content-Type: application/json
```

**Request Body:**
```json
{
    "pings": [
        {
            "session_id": 1,
            "latitude": 18.5741,
            "longitude": 73.7736,
            "accuracy_m": 12.0,
            "address": "Location A",
            "battery_pct": 80,
            "captured_at": "2026-04-21T10:00:00+05:30"
        },
        {
            "session_id": 1,
            "latitude": 18.5742,
            "longitude": 73.7737,
            "battery_pct": 75,
            "captured_at": "2026-04-21T10:30:00+05:30"
        },
        {
            "session_id": 1,
            "latitude": 18.5739,
            "longitude": 73.7734,
            "captured_at": "2026-04-21T11:00:00+05:30"
        }
    ]
}
```

**Each ping object fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `session_id` | Integer | Yes | From punch-in response |
| `latitude` | Number | Yes | GPS latitude |
| `longitude` | Number | Yes | GPS longitude |
| `accuracy_m` | Number | No | GPS accuracy |
| `address` | String | No | Reverse-geocoded address |
| `battery_pct` | Integer | No | Battery percentage |
| `captured_at` | DateTime | Yes | When location was captured on device |

**Success Response (200):**
```json
{
    "status": true,
    "data": {
        "accepted": 3,
        "rejected": [],
        "ping_ids": [2, 3, 4]
    }
}
```

**Partial Success (some pings rejected):**
```json
{
    "status": true,
    "data": {
        "accepted": 2,
        "rejected": [
            {
                "index": 2,
                "reason": "SESSION_NOT_ACTIVE"
            }
        ],
        "ping_ids": [2, 3]
    }
}
```

**Notes:**
- `rejected[].index` refers to the 0-based index in the `pings` array
- A ping is rejected if its `session_id` is not active or doesn't belong to the employee
- Accepted pings are stored even if some are rejected (partial success)

---

## 6. Today's Attendance (Self View)

Get the employee's own attendance status for today.

```
GET /api/attendance/today
Authorization: Bearer <token>
Accept: application/json
```

**No request body needed.**

**Success Response (200) - Active session:**
```json
{
    "status": true,
    "data": {
        "active_session": {
            "session_id": 1,
            "started_at": "2026-04-21T09:00:05+05:30",
            "ping_count": 3,
            "last_ping": {
                "latitude": 18.5742,
                "longitude": 73.7737,
                "captured_at": "2026-04-21T11:00:00+05:30"
            }
        },
        "punches": [
            {
                "type": "in",
                "punched_at": "2026-04-21T09:00:05+05:30",
                "selfie_url": "https://hrms.mecpl.in/storage/attendance/2026/04/123_1745202605.jpg",
                "inside_geofence": true,
                "distance_m": 15
            }
        ],
        "total_seconds": 0
    }
}
```

**Success Response (200) - No active session (after punch-out):**
```json
{
    "status": true,
    "data": {
        "active_session": null,
        "punches": [
            {
                "type": "in",
                "punched_at": "2026-04-21T09:00:05+05:30",
                "selfie_url": "https://hrms.mecpl.in/storage/attendance/2026/04/123_1745202605.jpg",
                "inside_geofence": true,
                "distance_m": 15
            },
            {
                "type": "out",
                "punched_at": "2026-04-21T18:00:10+05:30",
                "selfie_url": "https://hrms.mecpl.in/storage/attendance/2026/04/123_1745234410.jpg",
                "inside_geofence": true,
                "distance_m": 20
            }
        ],
        "total_seconds": 32405
    }
}
```

**Notes:**
- `total_seconds` = sum of all closed sessions' durations today (active session not counted until closed)
- `active_session` is `null` when no session is open
- `last_ping` is `null` if no pings sent yet in the active session
- Multiple punch-in/out pairs in a day are supported (e.g., lunch break)

---

## 7. Punch Out

Records a punch-out with GPS + selfie. Closes the active session.

```
POST /api/attendance/punch-out
Authorization: Bearer <token>
Accept: application/json
Content-Type: multipart/form-data
```

**Request Fields (multipart/form-data):**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `session_id` | Integer | Yes | From punch-in response |
| `selfie` | File | Yes | JPG/JPEG/PNG image, max 2MB |
| `latitude` | Number | Yes | GPS latitude (-90 to 90) |
| `longitude` | Number | Yes | GPS longitude (-180 to 180) |
| `accuracy_m` | Number | No | GPS accuracy in meters |
| `address` | String | No | Reverse-geocoded address, max 500 chars |
| `client_captured_at` | DateTime | Yes | ISO 8601 timestamp from device clock |
| `device_info` | JSON String | No | Device metadata |

**Example Request (Dart):**
```dart
var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/attendance/punch-out'));
request.headers['Authorization'] = 'Bearer $token';
request.headers['Accept'] = 'application/json';

request.files.add(await http.MultipartFile.fromPath('selfie', selfieFile.path));
request.fields['session_id'] = '1';
request.fields['latitude'] = '18.5743404';
request.fields['longitude'] = '73.7736299';
request.fields['accuracy_m'] = '6.0';
request.fields['address'] = 'Pune HQ, Hinjewadi';
request.fields['client_captured_at'] = '2026-04-21T18:00:00+05:30';
```

**Success Response (200):**
```json
{
    "status": true,
    "message": "Punch-out recorded.",
    "data": {
        "session_id": 1,
        "punch_id": 2,
        "duration_seconds": 32395,
        "ping_count": 3,
        "is_last_of_day": true,
        "geofence": {
            "inside": true,
            "distance_m": 20,
            "radius_m": 200
        }
    }
}
```

**Error Responses:**
| Code | Message | Meaning |
|------|---------|---------|
| 404 | Session not found | Invalid session_id or not owned by employee |
| 409 | Session is not active | Already punched out |
| 422 | Validation error | Check selfie, session_id exists |
| 429 | Too Many Requests | Rate limited (max 6/minute) |

**Notes:**
- `duration_seconds` = total time between punch-in and punch-out
- `is_last_of_day` = true (always true for the latest out-punch; previous out-punches for the day get set to false)
- After punch-out, employee can punch-in again for a new session (multiple sessions/day allowed)

---

## 8. Session Timeline

Get the full timeline of a specific session: punch-in, punch-out, and all location pings.

```
GET /api/attendance/session/{session_id}/timeline
Authorization: Bearer <token>
Accept: application/json
```

**Example:** `GET /api/attendance/session/1/timeline`

**No request body needed.**

**Success Response (200):**
```json
{
    "status": true,
    "data": {
        "session": {
            "id": 1,
            "employee_id": 123,
            "started_at": "2026-04-21T09:00:05+05:30",
            "ended_at": "2026-04-21T18:00:10+05:30",
            "status": "closed"
        },
        "punch_in": {
            "latitude": 18.5743404,
            "longitude": 73.7736299,
            "punched_at": "2026-04-21T09:00:05+05:30",
            "selfie_url": "https://hrms.mecpl.in/storage/attendance/2026/04/123_1745202605.jpg",
            "inside_geofence": true
        },
        "punch_out": {
            "latitude": 18.5743404,
            "longitude": 73.7736299,
            "punched_at": "2026-04-21T18:00:10+05:30",
            "selfie_url": "https://hrms.mecpl.in/storage/attendance/2026/04/123_1745234410.jpg",
            "inside_geofence": true
        },
        "pings": [
            {
                "latitude": 18.5740,
                "longitude": 73.7735,
                "captured_at": "2026-04-21T09:30:00+05:30",
                "inside_geofence": true,
                "accuracy_m": 10.0
            },
            {
                "latitude": 18.5741,
                "longitude": 73.7736,
                "captured_at": "2026-04-21T10:00:00+05:30",
                "inside_geofence": true,
                "accuracy_m": 12.0
            }
        ]
    }
}
```

**Error Responses:**
| Code | Message | Meaning |
|------|---------|---------|
| 403 | Forbidden | Not your session and you're not admin |
| 404 | Not found | Session doesn't exist |

**Notes:**
- Employee can view their own sessions
- Admin (role=ADMIN) can view any employee's session
- `punch_out` is `null` if session is still active
- `pings` array is ordered by `captured_at` ascending

---

## 9. Live Attendance (Admin Only)

Get all currently active sessions with last known locations. For the admin dashboard.

```
GET /api/attendance/live
Authorization: Bearer <admin_token>
Accept: application/json
```

**Optional Query Parameters:**

| Param | Type | Description |
|-------|------|-------------|
| `branch_id` | Integer | Filter by branch |
| `limit` | Integer | Max results (default 100) |

**Example:** `GET /api/attendance/live?branch_id=12&limit=50`

**Success Response (200):**
```json
{
    "status": true,
    "data": [
        {
            "session_id": 1,
            "employee": {
                "id": 123,
                "emp_name": "John Doe",
                "emp_code": "1104"
            },
            "branch": {
                "id": 12,
                "branch_name": "HEAD OFFICE"
            },
            "started_at": "2026-04-21T09:00:05+05:30",
            "ping_count": 3,
            "last_ping": {
                "latitude": 18.5742,
                "longitude": 73.7737,
                "inside_geofence": true,
                "captured_at": "2026-04-21T11:00:00+05:30"
            }
        },
        {
            "session_id": 2,
            "employee": {
                "id": 456,
                "emp_name": "Jane Smith",
                "emp_code": "2205"
            },
            "branch": {
                "id": 12,
                "branch_name": "HEAD OFFICE"
            },
            "started_at": "2026-04-21T09:15:00+05:30",
            "ping_count": 0,
            "last_ping": null
        }
    ]
}
```

**Error Responses:**
| Code | Message | Meaning |
|------|---------|---------|
| 403 | Admin access required | User's role is not ADMIN |

**Notes:**
- `last_ping` is `null` if no pings sent yet (employee just punched in)
- Only returns sessions with `status = active` (not closed/force_closed)

---

## Quick Reference Table

| # | Endpoint | Method | Content-Type | Auth | Rate Limit |
|---|----------|--------|-------------|------|------------|
| 1 | `/api/check_login_api` | POST | application/json | No | Default |
| 2 | `/api/me/geofence` | GET | - | Bearer | Default |
| 3 | `/api/attendance/punch-in` | POST | multipart/form-data | Bearer | 6/min |
| 4 | `/api/attendance/location-ping` | POST | application/json | Bearer | 30/min |
| 5 | `/api/attendance/location-ping/batch` | POST | application/json | Bearer | 30/min |
| 6 | `/api/attendance/today` | GET | - | Bearer | Default |
| 7 | `/api/attendance/punch-out` | POST | multipart/form-data | Bearer | 6/min |
| 8 | `/api/attendance/session/{id}/timeline` | GET | - | Bearer | Default |
| 9 | `/api/attendance/live` | GET | - | Bearer (Admin) | Default |

---

## Flow Diagram

```
App Launch
    |
    v
[Login] --> Save token
    |
    v
[Get My Geofence] --> Configure geofence circle on map
    |
    v
[Punch In] --> Save session_id
    |         --> Start 30-min location ping timer
    |
    v
[Location Ping] every 30 min (single or batch if offline)
    |
    v
[Today's Attendance] --> Show status on home screen
    |
    v
[Punch Out] --> Stop location ping timer
    |          --> Show duration
    |
    v
(Employee can punch-in again for new session)
```

---

## Common Error Response Format

All error responses follow this structure:

```json
{
    "status": false,
    "message": "Human-readable error message"
}
```

For validation errors (422):
```json
{
    "message": "The given data was invalid.",
    "errors": {
        "selfie": ["The selfie field is required."],
        "latitude": ["The latitude must be between -90 and 90."]
    }
}
```

---

## DateTime Format

All timestamps use **ISO 8601** format with timezone:
```
2026-04-21T09:00:00+05:30
```

The `+05:30` is India Standard Time (IST). The server stores all times in UTC internally.

---

## Selfie Storage

- Selfies are stored at: `https://hrms.mecpl.in/storage/attendance/{YYYY}/{MM}/{employee_id}_{unix_timestamp}.jpg`
- The `selfie_url` in responses is the full public URL
- Accepted formats: JPG, JPEG, PNG
- Max size: 2MB
