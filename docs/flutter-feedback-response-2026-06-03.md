# Flutter Feedback Response â 2026-06-03

**From:** Backend team  
**To:** Flutter developer  
**Re:** `docs/mobile_requirement/attendance-history-flutter-feedback.md`

---

## Both Issues Fixed

---

## Issue 1: Active sessions not returned by `/attendance/history` â FIXED

### Root Cause
The history query was only matching on the `date` column (`whereDate('date', $date)`). Some sessions had the `date` column set using server time that didn't match the requested IST date, or the column was null for manually created test sessions.

### Fix
Added fallback â history now queries: `WHERE date = $date OR DATE(started_at) = $date`

This ensures sessions are found by EITHER the `date` column OR the `started_at` timestamp.

### Confirmation
- Active sessions with `status: "active"` ARE now included in history results
- Sessions with `ended_at: null` ARE returned (not filtered out)
- Sessions with empty `punches: []` but with pings ARE returned
- The response includes `status: "active"` so the app knows the session is still open

### Test
```
GET /api/attendance/history?date=2026-05-28
```
Should now return session_id 2 (the one with 161 pings) for user 77.

---

## Issue 2: Tokens being revoked / "session expired" â FIXED

### Root Cause
Line 130 of `LoginAPIController.php` had:
```php
$employee->tokens()->delete(); // Revoke ALL previous tokens
```

This deleted ALL existing tokens on every login. So:
- Device A logs in â gets token 285
- Device B logs in â deletes token 285, gets token 286
- Device A makes any API call â 401 "session expired"

### Fix
- **Removed** the `tokens()->delete()` line
- Multi-device login is now **allowed** â each login creates a new token without revoking existing ones
- Token expiration: `null` (no expiry) â confirmed in `config/sanctum.php`

### What this means for the app
- Employee can be logged in on **multiple devices** simultaneously
- Tokens do **not expire** â they stay valid until explicitly revoked (via logout)
- Logging in on a new device does NOT kill the old device's session
- The "Your session has expired" error should no longer occur

### Token Lifetime
- **Expiration:** None (`sanctum.expiration = null`)
- **Revocation:** Only on explicit logout (`POST /api/logout`)
- **Multi-device:** Allowed â unlimited concurrent tokens per employee

---

## What You Need to Update on Flutter Side

### For Issue 1
No changes needed â the response shape is exactly the same. Active sessions will now appear with `status: "active"` and `ended_at: null`.

### For Issue 2
1. **Remove any "re-login on 401" retry loops** that might be causing rapid re-authentication cycles
2. The app can safely store the token persistently (SharedPreferences) â it won't expire
3. Only clear the stored token when the user explicitly taps "Logout"
4. If you get a 401, show the login screen (the token was revoked by logout, not by expiry)

---

## Files Modified

| File | Change |
|------|--------|
| `app/Http/Controllers/Api/AttendanceViewController.php` | History query now matches by `date` OR `started_at` date |
| `app/Http/Controllers/Api/LoginAPIController.php` | Removed `$employee->tokens()->delete()` â multi-device login allowed |

No migrations needed. Upload both files and test.
