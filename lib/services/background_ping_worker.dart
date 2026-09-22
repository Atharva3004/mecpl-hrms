// Background Ping Worker — runs in a separate isolate scheduled by
// Workmanager (Android WorkManager + iOS BGTaskScheduler). Its job is to
// fire a single location-ping while an attendance session is open, and to
// keep firing them even after the OS kills the app.
//
// Why it lives at the top level: Workmanager's contract requires a
// top-level (or static) entry point marked with @pragma('vm:entry-point')
// so the Dart VM can resolve it from the background isolate. Anything
// inside a class or closure won't be callable from the OS scheduler.

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';

import '../models/attendance_session.dart';
import 'api_service.dart';
import 'background_location_service.dart';
import 'ping_queue_service.dart';

/// Unique task id used when scheduling / cancelling the periodic ping job.
/// Kept stable — Workmanager matches tasks by name on both Android and iOS.
const String kBackgroundPingTaskName = 'mecpl.attendance.location_ping';

/// Entry point invoked by Workmanager in a background isolate. Must be a
/// top-level function and annotated with `vm:entry-point` so the tree
/// shaker doesn't strip it from the release build.
@pragma('vm:entry-point')
void backgroundPingCallbackDispatcher() {
  // WidgetsFlutterBinding is required so plugins (geolocator,
  // shared_preferences, geocoding) can bind to the background isolate's
  // message channel.
  WidgetsFlutterBinding.ensureInitialized();

  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != kBackgroundPingTaskName) {
      // Unknown task — tell the OS we're done, nothing to retry.
      return Future.value(true);
    }

    try {
      // 1) Must have an active session — if the user punched out, the OS
      //    may still have one more scheduled wake-up queued; swallow it.
      final session = await AttendanceSession.load();
      if (session == null) return Future.value(true);

      // 2) Need the auth token — persisted by the foreground flow on login
      //    and read back from SharedPreferences here.
      final token = await BackgroundLocationService.loadAuthTokenStatic();
      if (token == null || token.isEmpty) return Future.value(true);

      // 3) Respect the shared 30-minute window. This isolate has its own
      //    memory, so without a persisted claim it pinged on its own schedule
      //    while the foreground stream pinged on another — which is what
      //    produced intervals of 8 and 14 minutes instead of 30. Returning
      //    true (not false) marks the wake-up handled: the work was not
      //    needed, so there is nothing for the OS to retry.
      if (!await BackgroundLocationService.claimPingSlot()) {
        return Future.value(true);
      }

      // 4) Get a fresh GPS fix. If this throws, the catch block returns
      //    false so Workmanager can retry on the next scheduled window.
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 20));

      // Best-effort reverse geocode — don't fail the ping if geocoding fails.
      String address = '';
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final parts = <String>[
            if ((p.street ?? '').isNotEmpty) p.street!,
            if ((p.subLocality ?? '').isNotEmpty) p.subLocality!,
            if ((p.locality ?? '').isNotEmpty) p.locality!,
            if ((p.administrativeArea ?? '').isNotEmpty) p.administrativeArea!,
          ];
          address = parts.join(', ');
        }
      } catch (_) {
        // ignore — address stays empty
      }

      // Best-effort battery read — same contract as the address above, a
      // failure here must not cost us the ping.
      int? batteryPct;
      try {
        batteryPct = await Battery().batteryLevel;
      } catch (_) {
        // ignore — battery_pct stays null, which the backend accepts
      }

      final capturedAt = DateTime.now();

      // 5) Flush anything enqueued earlier (offline → online transition is
      //    likely what just happened if we're back in background).
      await PingQueueService().flush(token);

      // 6) Post the current ping.
      final response = await ApiService.sendLocationPing(
        token: token,
        sessionId: session.sessionId,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyM: position.accuracy,
        address: address.isEmpty ? null : address,
        batteryPct: batteryPct,
        capturedAt: capturedAt,
      );

      if (!response.isSuccess) {
        // Stash it so it still gets sent eventually.
        await PingQueueService().enqueue(
          QueuedPing(
            sessionId: session.sessionId,
            latitude: position.latitude,
            longitude: position.longitude,
            accuracyM: position.accuracy,
            address: address.isEmpty ? null : address,
            batteryPct: batteryPct,
            capturedAt: capturedAt,
          ),
        );
      }

      return Future.value(true);
    } catch (_) {
      // Any unexpected failure — let the OS retry on the next window.
      return Future.value(false);
    }
  });
}
