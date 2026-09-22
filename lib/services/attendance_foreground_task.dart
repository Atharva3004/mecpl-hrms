// Attendance Foreground Task — the ping source that survives task removal.
//
// WHY THIS EXISTS
// ---------------
// The first attempt kept a `Geolocator.getPositionStream` alive with a
// foreground notification. That keeps location flowing while the app is
// *backgrounded*, but it does NOT survive the user swiping the app out of
// recents: the stream is listened to on the main isolate, and Android
// destroys the FlutterEngine when the task is removed. The service may linger
// with no Dart code left to receive anything, so pings simply stopped.
//
// flutter_foreground_task runs its own foreground service with its own
// isolate and its own repeating event, declared `stopWithTask: false`, so the
// service and its Dart handler outlive the activity. This is the only
// client-side mechanism on Android that keeps a timer running after a swipe.
//
// Workmanager is kept as a second, independent source: it survives reboots
// and covers the case where the foreground service is killed outright. Both
// go through `BackgroundLocationService.claimPingSlot()`, so whichever fires
// first takes the 30-minute slot and the other stands down.

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../models/attendance_session.dart';
import 'api_service.dart';
import 'background_location_service.dart';
import 'ping_queue_service.dart';

/// Entry point for the foreground service isolate.
///
/// Must be top-level and `vm:entry-point` annotated so the tree shaker keeps
/// it in release builds — the same contract as the Workmanager dispatcher.
@pragma('vm:entry-point')
void startAttendanceForegroundTask() {
  FlutterForegroundTask.setTaskHandler(_AttendancePingTaskHandler());
}

class _AttendancePingTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('🟩 [FGTASK] started (${starter.name}) at $timestamp');

    // Check immediately rather than waiting out the first tick.
    //
    // Android restarts this service on its own (memory pressure, package
    // replaced, reboot) — observed twice within twenty minutes on a MIUI
    // device. Each restart resets the repeat timer, so a ping that fell due
    // while the service was down would otherwise wait a further interval, and
    // frequent restarts could starve the schedule indefinitely.
    //
    // claimPingSlot() still gates it, so a restart cannot produce an early or
    // duplicate ping — it only lets an already-overdue one go out at once.
    await _pingIfDue();
  }

  /// Fires on the interval configured in [ForegroundTaskOptions.eventAction].
  ///
  /// Deliberately runs at a shorter cadence than the 30-minute ping: the
  /// claim in [BackgroundLocationService.claimPingSlot] decides whether a
  /// ping is actually due. Ticking more often than we send means a missed
  /// window (Doze, no GPS fix, no network) is retried minutes later instead
  /// of waiting a further half hour.
  @override
  void onRepeatEvent(DateTime timestamp) {
    // ignore: discarded_futures
    _pingIfDue();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('🟩 [FGTASK] destroyed at $timestamp (timeout: $isTimeout)');
  }

  Future<void> _pingIfDue() async {
    try {
      // No open session → nothing to attribute a ping to. The service is
      // stopped on punch-out, but a tick can still be in flight.
      final session = await AttendanceSession.load();
      if (session == null) return;

      final token = await BackgroundLocationService.loadAuthTokenStatic();
      if (token == null || token.isEmpty) return;

      // Shared with the Workmanager worker and the foreground stream, so the
      // three sources cannot stack pings on top of each other.
      if (!await BackgroundLocationService.claimPingSlot()) return;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 20));

      // Best-effort enrichment — neither of these may cost us the ping.
      String address = '';
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          address = <String>[
            if ((p.street ?? '').isNotEmpty) p.street!,
            if ((p.subLocality ?? '').isNotEmpty) p.subLocality!,
            if ((p.locality ?? '').isNotEmpty) p.locality!,
            if ((p.administrativeArea ?? '').isNotEmpty) p.administrativeArea!,
          ].join(', ');
        }
      } catch (_) {
        // address stays empty
      }

      int? batteryPct;
      try {
        batteryPct = await Battery().batteryLevel;
      } catch (_) {
        // battery_pct stays null, which the backend accepts
      }

      final capturedAt = DateTime.now();

      // Drain anything stranded by an earlier failure before adding to it.
      await PingQueueService().flush(token);

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
    } catch (e) {
      // Never let an exception escape into the service isolate — an uncaught
      // error here takes the whole foreground service down, which is exactly
      // the failure this class exists to prevent.
      debugPrint('⚠️ [FGTASK] ping failed: $e');
    }
  }
}
