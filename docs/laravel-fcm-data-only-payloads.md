# Laravel Backend — Switch FCM to Data-Only Payloads (for MECPL logo on every notification)

Standalone reference for the Laravel developer.

**Goal:** make the MECPL logo appear as the **large icon** (right-side image) on **every** push notification — including when the app is in the background or killed, not just foreground.

**Why this doc exists:** FCM HTTP v1's `notification` payload has no field for a custom large icon. The only way to get a consistent right-side image across all app states is for the Flutter app to **render the notification itself** — which means the backend must send **data-only** FCM messages instead of `notification` payloads.

**Scope:** small, low-risk change to `FcmService::sendToDevice`. About 10 lines. Doesn't touch any controller hooks.

---

## 1. The change in one picture

### Before (current behavior — `notification` payload)

```php
$message = CloudMessage::withTarget('token', $fcmToken)
    ->withNotification(Notification::create($title, $body))   // ← FCM auto-renders this
    ->withData($data);
```

- Foreground delivery: Flutter app catches `onMessage`, renders the notification itself **with** the large icon.
- Background/killed delivery: FCM auto-renders **without** a large icon (Android FCM has no large-icon field).

Result: logo appears on foreground notifications only.

### After (target behavior — data-only)

```php
// title + body get folded into `data`; no `withNotification(...)` call.
$message = CloudMessage::withTarget('token', $fcmToken)
    ->withData(array_merge($data, [
        'title' => $title,
        'body'  => $body,
    ]));
```

- Foreground delivery: same — Flutter renders the notification with the large icon.
- Background/killed delivery: FCM no longer auto-renders. Flutter's background handler renders it instead, **with** the large icon.

Result: logo appears on **every** notification, in every app state.

---

## 2. Why we can't just add `notification.image`

FCM v1 has a `notification.image` field, but it controls the **big-picture** (the wide image that only appears when the user expands the notification). It's not the same as the small right-side image that WhatsApp shows next to each chat notification.

Android FCM literally does not expose a field for the large icon. The only way to put one there is to render the notification yourself — which is exactly what data-only payloads let the app do.

---

## 3. The exact change in `FcmService`

Current code (per `laravel-fcm-push-notifications.md` §11):

```php
$message = CloudMessage::withTarget('token', $fcmToken)
    ->withNotification(Notification::create($title, $body))
    ->withData($data)
    ->withAndroidConfig(AndroidConfig::fromArray([
        'priority' => 'high',
        'notification' => [
            'channel_id' => 'mecpl_default',
        ],
    ]));
```

Change to:

```php
// Data-only payload: Flutter app reads `title` and `body` from $data and
// renders the notification locally (with the MECPL logo as the large icon).
// FCM does not auto-render anything — the app is fully responsible.
$message = CloudMessage::withTarget('token', $fcmToken)
    ->withData(array_merge(
        // Coerce every value to a string — FCM rejects non-strings.
        array_map(fn ($v) => (string) $v, $data),
        [
            'title' => $title,
            'body'  => $body,
        ]
    ))
    ->withAndroidConfig(AndroidConfig::fromArray([
        'priority' => 'high',
        // channel_id is no longer needed here (FCM isn't rendering), but
        // keeping it as a hint costs nothing.
    ]));
```

**What changed:**
- Removed `->withNotification(...)`.
- Folded `title` and `body` into `withData(...)`.
- Removed the `notification` block from android config (not used in data-only mode).

That's it. No other backend code changes. Every existing call site (`sendToUser`, `notifyAdmins`, etc.) continues to work unchanged.

---

## 4. Important — set `priority: high`

Already in the code above. **Don't remove it.** With data-only payloads on Android, normal-priority messages can be delayed for up to a few minutes by Doze mode. `priority: high` keeps delivery near-instant, same as before.

You may also need to add `'mutable_content': true` to the android config on some OEMs (Xiaomi, Vivo). If a tester reports delayed background notifications after the switch, try adding this — it forces immediate delivery.

---

## 5. Verification

Mobile-side handler is already wired (see `lib/services/notification_service.dart::_firebaseBackgroundHandler`). It checks `if (message.notification != null) return;` — so the switch must be **all-or-nothing**. If some endpoints still send `withNotification(...)` and others don't, you'll get inconsistent behavior:
- Endpoints with `withNotification` → FCM renders, no large icon.
- Endpoints without `withNotification` → app renders, with large icon.

Search your codebase to confirm every push goes through `FcmService::sendToDevice` (or whatever the central send method is) and that you've removed `withNotification` from that one place:

```bash
grep -rn "withNotification" app/
```

Should return **zero** matches inside any FCM-related file after the change.

### Test plan

1. **Background test (this is the one that matters):**
   - Phone user logs in fresh, **backgrounds** the app (don't kill).
   - Trigger any push event (e.g., approve a leave from web).
   - Notification appears in the panel within 30 sec.
   - ✅ Title + body shown correctly.
   - ✅ MECPL logo visible as the right-side image.
   - ✅ Tap → app opens to the correct screen.

2. **Killed-app test:**
   - Phone user swipes app away from recents.
   - Trigger a push event.
   - ✅ Notification appears with MECPL logo.
   - ✅ Tap → cold-starts the app to the correct screen.

3. **Foreground test:**
   - Phone user keeps the app open on the dashboard.
   - Trigger a push event.
   - ✅ Heads-up banner appears with MECPL logo on the right.

4. **All existing events still work:**
   - Repeat for: leave submitted (approver + admin broadcast), leave approved, leave rejected, regularization submitted (admin), onboarding submitted (admin). Each should arrive with the logo and route correctly on tap.

### Reporting template

```
Test 1 (background):       PASS / FAIL — Logo visible: YES / NO
Test 2 (killed):           PASS / FAIL — Logo visible: YES / NO
Test 3 (foreground):       PASS / FAIL — Logo visible: YES / NO
Test 4 (all events route): PASS / FAIL

Notes:
```

---

## 6. Common pitfalls

### Pitfall 1 — Forgot to coerce data values to strings

FCM rejects any data payload with non-string values:

```
INVALID_ARGUMENT: Field "message.data" must contain only strings
```

The example uses `array_map(fn ($v) => (string) $v, $data)` to coerce everything. Keep that, or your push call will throw.

### Pitfall 2 — Data-only messages aren't delivered when priority is normal

On Android Doze, normal-priority data-only messages can sit in a queue for several minutes. Always set `priority: high` on the android config.

### Pitfall 3 — iOS data-only is different

On iOS, "data-only" messages (no `notification` payload) are treated as **silent background pushes** — they don't show in the notification center at all. They wake the app to process data.

For now this doc is **Android-only**. iOS push handling will need a different approach when we get to it (probably: use `mutable_content` + a notification service extension to attach the image client-side). Not in scope here.

### Pitfall 4 — Don't forget the `priority` field

Without `priority: high`, the OS may delay or drop your notifications during Doze mode. The Flutter background handler can only render notifications it actually receives — if FCM is throttling them, the app never gets a chance.

---

## 7. Rollback plan

If something breaks unexpectedly:

1. Revert the `FcmService::sendToDevice` change (add `withNotification(...)` back).
2. Push the revert.
3. All notifications return to current behavior (no logo on background, but everything else works).

The Flutter app's background handler is **defensive** — it checks `message.notification != null` and bails out when present. So even with old-style payloads it'll continue working.

---

## 8. Quick checklist

- [ ] Locate `FcmService::sendToDevice` (or your central FCM send method).
- [ ] Remove `->withNotification(Notification::create($title, $body))`.
- [ ] Add `'title' => $title, 'body' => $body` into the `withData()` array.
- [ ] Coerce all data values to strings via `array_map`.
- [ ] Keep `priority: high` in android config.
- [ ] Run Tests 1–4 above and report.

That's the entire change. The Flutter side is already prepared — once you flip the backend, the logo will appear on every notification across all app states.
