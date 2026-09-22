// Background Location Service - Tracks user location in background.
//
// Scheduling model (as of Case 3):
//   - On punch-in, record the "In" point locally AND schedule a Workmanager
//     periodic task (`backgroundPingCallbackDispatcher` in
//     `background_ping_worker.dart`). That task fires every ~30 min even
//     after the OS kills the app — it's what actually sends pings.
//   - On punch-out, record the "Out" point locally AND cancel the
//     periodic task.
//
// The old Timer.periodic has been retired because it dies the moment
// Android Doze kicks in or the user swipes the app away. Workmanager
// survives both.

import 'dart:async';
import 'dart:convert';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:workmanager/workmanager.dart';
import '../models/attendance_session.dart';
import '../models/location_point_model.dart';
import 'api_service.dart';
import 'attendance_foreground_task.dart';
import 'background_ping_worker.dart';
import 'ping_queue_service.dart';

class BackgroundLocationService {
  static final BackgroundLocationService _instance =
      BackgroundLocationService._internal();
  factory BackgroundLocationService() => _instance;
  BackgroundLocationService._internal();

  // Unified with the key AuthProvider writes in login() / _bootstrap. The
  // Workmanager background isolate reads this same key on each 30-min fire
  // — previously the worker used a separate 'auth_token_for_ping' key that
  // was never populated, so every scheduled ping exited silently without
  // sending anything to /attendance/location-ping.
  static const String _prefsTokenKey = 'auth_token';

  // The user whose session is being tracked. Persisted because the foreground
  // stream has to be rebuilt after a process restart (see
  // [resumeTrackingIfNeeded]), and by then the in-memory _currentUserId is
  // gone along with the rest of the isolate.
  static const String _prefsUserIdKey = 'tracking_user_id';
  // Workmanager periodic frequency. iOS may fire later (BGTaskScheduler is
  // opportunistic); Android honours it closely.
  static const Duration _pingFrequency = Duration(minutes: 30);

  /// Timestamp of the last ping actually sent, persisted so the cadence
  /// survives a process restart AND is shared with the Workmanager isolate.
  ///
  /// This used to be an in-memory field on this singleton, which produced the
  /// erratic intervals seen in production (16:27, 16:27, 16:35, 16:49 instead
  /// of a clean 30 minutes): the field reset to null on every process start
  /// and on every stream restart, and the Workmanager worker — running in its
  /// own isolate with its own memory — never consulted it at all. Two
  /// independent ping sources with no shared clock.
  static const String _prefsLastPingKey = 'last_ping_at';

  /// Scheduler jitter allowance. WorkManager fires within a flex window, so a
  /// tick at 29m50s must count as due — otherwise it is rejected and the next
  /// opportunity is a further 30 minutes away, stretching the real interval
  /// towards an hour.
  static const Duration _pingJitterGrace = Duration(seconds: 90);

  /// Atomically claims the next ping slot. Returns false when one was sent
  /// less than [_pingFrequency] ago, so the caller must skip.
  ///
  /// Claim-before-send: the timestamp is written *before* the network call so
  /// two sources firing at once cannot both pass.
  static Future<bool> claimPingSlot() async {
    final prefs = await SharedPreferences.getInstance();
    // Another isolate (the Workmanager worker) may have written since this
    // isolate last read, so force a re-read rather than trusting the cache.
    await prefs.reload();

    final raw = prefs.getString(_prefsLastPingKey);
    final last = raw == null ? null : DateTime.tryParse(raw);
    final now = DateTime.now();

    if (last != null &&
        now.difference(last) < (_pingFrequency - _pingJitterGrace)) {
      return false;
    }

    await prefs.setString(_prefsLastPingKey, now.toIso8601String());
    return true;
  }

  /// Anchors the 30-minute window to now without sending anything. Called at
  /// punch-in so the first tracking ping lands 30 minutes later.
  static Future<void> anchorPingWindow() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsLastPingKey, DateTime.now().toIso8601String());
  }

  static Future<void> clearPingWindow() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsLastPingKey);
  }

  bool _isTracking = false;
  String? _currentUserId;


  /// Stores the auth token separately so the Workmanager callback (which
  /// runs in its own isolate) can read it from SharedPreferences without
  /// going through any provider.
  static Future<void> storeAuthToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsTokenKey, token);
  }

  /// Public accessor used by [backgroundPingCallbackDispatcher] to read the
  /// stored token from the background isolate.
  static Future<String?> loadAuthTokenStatic() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsTokenKey);
  }

  static Future<String?> _loadAuthToken() => loadAuthTokenStatic();

  // Start background location tracking
  Future<void> startTracking(String userId, {String? selfiePath}) async {
    if (_isTracking) return;

    _isTracking = true;
    _currentUserId = userId;
    print('📍 Starting background location tracking for user: $userId');

    // Remember who we're tracking so the stream can be rebuilt after a
    // process restart without needing a provider or an auth lookup.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsUserIdKey, userId);

    // 1) Record the "In" point locally, for the map's route polyline.
    //
    //    This deliberately does NOT post a ping. A ping at punch-in time
    //    carries the same coordinates, timestamp and selfie as the Punch In
    //    row that opened the session, so it rendered a duplicate row on the
    //    timeline for no extra information. The punch-in record already marks
    //    the start of the trail, and with better data (a real selfie and the
    //    server's own geofence verdict). The first tracking ping is therefore
    //    the first 30-minute tick after punch-in.
    await _saveCurrentLocation(userId, 'In', selfiePath: selfiePath);

    // Anchor the 30-minute window to punch-in, so the first tracking ping
    // lands 30 minutes from now rather than on the stream's first emission.
    await anchorPingWindow();

    // 2) Register a periodic Workmanager task that fires every 30 minutes,
    //    even when the app is backgrounded or killed. The OS re-spawns a
    //    background isolate and invokes [backgroundPingCallbackDispatcher].
    await _schedulePeriodicPingTask();

    // 3) Hold a foreground-service location stream for the whole session.
    //    Workmanager alone is not enough: OEM battery managers cancel its
    //    jobs when the user swipes the app away.
    await _startForegroundStream();
  }

  /// Re-arms tracking for a session that is already open but whose in-process
  /// state was lost — the app was swiped away, killed for memory, or the
  /// phone rebooted, and the user has now reopened it mid-shift.
  ///
  /// [_isTracking] and the stream subscription live in memory, so they die
  /// with the isolate while the session itself survives in SharedPreferences.
  /// Without this, the foreground service would only ever exist between
  /// punch-in and the first time the process died — and on the OEMs this
  /// feature is for, a force-stop also cancels the Workmanager job, leaving
  /// the rest of the shift untracked.
  ///
  /// Safe to call on every screen open: it's a no-op when tracking is already
  /// live or no session is open. Deliberately does **not** replay the 'In'
  /// path — that would post a duplicate punch-in ping and write a second "In"
  /// row into the local history on every app launch.
  Future<void> resumeTrackingIfNeeded({String? fallbackUserId}) async {
    if (_isTracking) return;

    final session = await AttendanceSession.load();
    if (session == null) return;

    final prefs = await SharedPreferences.getInstance();
    // `tracking_user_id` is written at punch-in and is therefore DEVICE-LOCAL.
    // A second phone that logs in mid-shift has an open session on the server
    // but has never written that key, so requiring it meant tracking silently
    // refused to start there — the employee's trail simply stopped when they
    // switched phones. Fall back to the signed-in user and persist it, so the
    // new device adopts the session.
    var userId = prefs.getString(_prefsUserIdKey);
    if (userId == null || userId.isEmpty) {
      userId = fallbackUserId;
      if (userId == null || userId.isEmpty) {
        print('ℹ️ Session open but no user id available — skipping resume');
        return;
      }
      await prefs.setString(_prefsUserIdKey, userId);
      print('📍 Adopting session ${session.sessionId} on this device');
    }

    _isTracking = true;
    _currentUserId = userId;
    print('📍 Resuming tracking for open session ${session.sessionId}');

    // A force-stop cancels scheduled work, so re-register rather than assume
    // the task from punch-in survived.
    await _schedulePeriodicPingTask();
    await _startForegroundStream();
  }

  /// Registers the 30-minute Workmanager job. Shared by punch-in and resume;
  /// `replace` makes it idempotent.
  Future<void> _schedulePeriodicPingTask() async {
    try {
      await Workmanager().registerPeriodicTask(
        kBackgroundPingTaskName,
        kBackgroundPingTaskName,
        frequency: _pingFrequency,
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
        constraints: Constraints(networkType: NetworkType.connected),
        // Android: first execution starts soon so the interval begins from
        // now. iOS ignores this field (BGTaskScheduler is opportunistic).
        initialDelay: const Duration(minutes: 1),
        backoffPolicy: BackoffPolicy.linear,
        backoffPolicyDelay: const Duration(minutes: 5),
      );
      print('📍 Scheduled Workmanager periodic ping task (every 30 min)');
    } catch (e) {
      print('⚠️ Failed to schedule Workmanager task: $e');
      // Tracking state stays true — the foreground stream is still the
      // primary path; the OS scheduler is the backstop.
    }
  }

  /// Starts the foreground service that owns the ping loop.
  ///
  /// Uses flutter_foreground_task rather than a Geolocator position stream.
  /// The stream approach was listened to on the MAIN isolate, so swiping the
  /// app out of recents destroyed the FlutterEngine and the pings stopped
  /// dead — which is the bug this replaces. This service runs its own isolate
  /// with `stopWithTask: false`, so it outlives the activity.
  ///
  /// Best-effort: if the service refuses to start (permission denied,
  /// notifications blocked), tracking falls back to Workmanager alone rather
  /// than failing the punch.
  Future<void> _startForegroundStream() async {
    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'mecpl_attendance_tracking',
          channelName: 'Attendance tracking',
          channelDescription:
              'Shown while your work location is being recorded, between '
              'punch-in and punch-out.',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          // Tick every 5 minutes; claimPingSlot() decides whether a ping is
          // actually due. Ticking more often than we send means a window
          // missed for want of a GPS fix or network is retried soon after,
          // instead of being lost for a further 30 minutes.
          eventAction: ForegroundTaskEventAction.repeat(5 * 60 * 1000),
          // Survive a reboot mid-shift.
          autoRunOnBoot: true,
          autoRunOnMyPackageReplaced: true,
          allowWakeLock: true,
          allowWifiLock: true,
          // Come back if Android kills the service under memory pressure.
          allowAutoRestart: true,
          // THE point of this class: do not die when the task is removed.
          stopWithTask: false,
        ),
      );

      if (await FlutterForegroundTask.isRunningService) {
        // Already running (app reopened mid-shift) — leave it alone rather
        // than restarting and resetting its interval.
        print('📍 Foreground task already running');
        return;
      }

      final result = await FlutterForegroundTask.startService(
        serviceId: 2001,
        serviceTypes: const [ForegroundServiceTypes.location],
        notificationTitle: 'Attendance tracking active',
        notificationText: 'Recording your work location until you punch out.',
        callback: startAttendanceForegroundTask,
      );
      print('📍 Foreground task start: $result');
    } catch (e) {
      print('⚠️ Could not start foreground task: $e');
    }
  }

  Future<void> _stopForegroundStream() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
        print('📍 Foreground task stopped');
      }
    } catch (e) {
      print('⚠️ Could not stop foreground task: $e');
    }
  }

  // Stop background tracking. userId optional — falls back to the one captured
  // when startTracking was called, so punch-out flows don't have to pass it.
  Future<void> stopTracking([String? userId, String? selfiePath]) async {
    if (!_isTracking) return;

    final id = userId ?? _currentUserId;
    _isTracking = false;

    // Stop the foreground service first — that's what dismisses the
    // persistent notification. Leaving it up after punch-out would look like
    // the app is still tracking the employee off the clock.
    await _stopForegroundStream();
    await clearPingWindow();

    // Cancel the OS-scheduled periodic task. This survives app kill, so it's
    // important we explicitly cancel on punch-out.
    try {
      await Workmanager().cancelByUniqueName(kBackgroundPingTaskName);
    } catch (e) {
      print('⚠️ Failed to cancel Workmanager task: $e');
    }

    if (id != null) {
      await _saveCurrentLocation(id, 'Out', selfiePath: selfiePath);
    }
    _currentUserId = null;

    // Drop the persisted id too, so resumeTrackingIfNeeded can't re-arm
    // tracking off a closed session.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsUserIdKey);
    } catch (_) {}

    print('📍 Stopped background location tracking for user: $id');
  }

  /// Manually flush the offline ping queue (app resume, connectivity change, …).
  Future<int> flushQueuedPings() async {
    final token = await _loadAuthToken();
    if (token == null || token.isEmpty) return 0;
    return PingQueueService().flush(token);
  }

  // Check if tracking is active
  bool get isTracking => _isTracking;

  // Save current location. Writes the point to SharedPreferences (so
  // `location_history_provider` keeps working for Location History screens)
  // AND posts it to `/attendance/location-ping`. On network failure the ping
  // is enqueued via `PingQueueService` for later flush.
  Future<void> _saveCurrentLocation(
    String userId,
    String type, {
    String? selfiePath,
  }) async {
    try {
      print('📍 Saving location point: $type');

      Position? position = await _getCurrentPosition();
      if (position == null) {
        print('❌ Failed to get location');
        return;
      }

      String address = await _getAddressFromCoordinates(
        position.latitude,
        position.longitude,
      );

      // Best-effort battery read; a failure must not cost us the ping.
      int? batteryPct;
      try {
        batteryPct = await Battery().batteryLevel;
      } catch (_) {
        // ignore — battery_pct stays null, which the backend accepts
      }

      final capturedAt = DateTime.now();

      // 1) Local record (kept so existing history screens still work).
      //
      //    The battery reading is stored here too. The server has it — we send
      //    it on every ping — but does not return it yet, so this local copy is
      //    what lets the map show a percentage on the device's own trail today
      //    rather than waiting on the API.
      final point = LocationPoint(
        id: capturedAt.millisecondsSinceEpoch.toString(),
        userId: userId,
        timestamp: capturedAt,
        type: type,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        address: address,
        selfiePath: selfiePath,
        batteryPct: batteryPct,
      );
      await _saveLocationPoint(userId, point);

      // 2) Backend ping — only for the 'Tracking' cadence.
      //
      //    'In' and 'Out' are the punch bookends. The punch-in/-out endpoints
      //    already record those positions, with a real selfie and the
      //    server's own geofence verdict, so pinging them again just adds a
      //    duplicate timeline row at the same time and place. They are still
      //    saved locally above for the map's route polyline.
      //
      //    ('Out' additionally must not ping: punch-out closes the session
      //    server-side, so a ping racing it is rejected as SESSION_NOT_ACTIVE.)
      if (type != 'Tracking') {
        print('✅ Location saved (no ping for type=$type): ${point.address}');
        return;
      }

      final session = await AttendanceSession.load();
      if (session == null) {
        print('ℹ️ No active session — cancelling OS scheduler');
        // Nothing to attribute the ping to. Tear down both the Workmanager
        // task and the foreground stream so we neither keep waking up nor
        // leave a "tracking active" notification up with no session behind it.
        _isTracking = false;
        await _stopForegroundStream();
        await clearPingWindow();
        try {
          await Workmanager().cancelByUniqueName(kBackgroundPingTaskName);
        } catch (_) {}
        return;
      }

      final token = await _loadAuthToken();
      if (token == null || token.isEmpty) {
        print('⚠️ No stored auth token; enqueueing ping for later flush');
        await PingQueueService().enqueue(
          QueuedPing(
            sessionId: session.sessionId,
            latitude: position.latitude,
            longitude: position.longitude,
            accuracyM: position.accuracy,
            address: address,
            batteryPct: batteryPct,
            capturedAt: capturedAt,
          ),
        );
        return;
      }

      // Flush any previously-queued pings first so the server sees them in order.
      await PingQueueService().flush(token);

      final response = await ApiService.sendLocationPing(
        token: token,
        sessionId: session.sessionId,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyM: position.accuracy,
        address: address,
        batteryPct: batteryPct,
        capturedAt: capturedAt,
      );

      if (response.isSuccess) {
        print('✅ Ping sent for session ${session.sessionId}');
      } else {
        print('⚠️ Ping failed (${response.error}); enqueueing for later');
        await PingQueueService().enqueue(
          QueuedPing(
            sessionId: session.sessionId,
            latitude: position.latitude,
            longitude: position.longitude,
            accuracyM: position.accuracy,
            address: address,
            batteryPct: batteryPct,
            capturedAt: capturedAt,
          ),
        );
      }
    } catch (e) {
      print('❌ Error saving location: $e');
    }
  }

  // Get current GPS position
  Future<Position?> _getCurrentPosition() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('⚠️ Location services disabled');
        return null;
      }

      // Check permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('⚠️ Location permission denied');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('⚠️ Location permission permanently denied');
        return null;
      }

      // Get position
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      print('❌ Error getting position: $e');
      return null;
    }
  }

  // Get address from coordinates
  Future<String> _getAddressFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      );
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        String address = '';

        if (place.street != null && place.street!.isNotEmpty) {
          address += '${place.street}, ';
        }
        if (place.subLocality != null && place.subLocality!.isNotEmpty) {
          address += '${place.subLocality}, ';
        }
        if (place.locality != null && place.locality!.isNotEmpty) {
          address += '${place.locality}, ';
        }
        if (place.administrativeArea != null &&
            place.administrativeArea!.isNotEmpty) {
          address += place.administrativeArea!;
        }

        return address.isNotEmpty
            ? address
            : '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
      }
      return '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
    } catch (e) {
      print('❌ Error getting address: $e');
      return '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
    }
  }

  // Save location point to SharedPreferences
  Future<void> _saveLocationPoint(String userId, LocationPoint point) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dateKey = _getDateKey();
      final storageKey = 'location_points_${userId}_$dateKey';

      // Get existing points
      List<LocationPoint> points = await getLocationPoints(userId);

      // Add new point
      points.add(point);

      // Convert to JSON and save
      List<Map<String, dynamic>> jsonList = points
          .map((p) => p.toJson())
          .toList();
      String jsonString = jsonEncode(jsonList);

      await prefs.setString(storageKey, jsonString);

      print(
        '💾 Saved ${points.length} location points for $userId on $dateKey',
      );
    } catch (e) {
      print('❌ Error saving to SharedPreferences: $e');
    }
  }

  // Get location points for a user on specific date
  Future<List<LocationPoint>> getLocationPoints(
    String userId, {
    DateTime? date,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dateKey = date != null ? _formatDate(date) : _getDateKey();
      final storageKey = 'location_points_${userId}_$dateKey';

      String? jsonString = prefs.getString(storageKey);
      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }

      List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((json) => LocationPoint.fromJson(json)).toList();
    } catch (e) {
      print('❌ Error loading location points: $e');
      return [];
    }
  }

  // Get all location points for admin (all users)
  Future<Map<String, List<LocationPoint>>> getAllLocationPoints(
    String date,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dateKey = _formatDate(DateTime.parse(date));
      Map<String, List<LocationPoint>> allPoints = {};

      // Get all keys
      Set<String> keys = prefs.getKeys();

      for (String key in keys) {
        if (key.startsWith('location_points_') && key.endsWith('_$dateKey')) {
          // Extract userId from key
          String userId = key
              .replaceAll('location_points_', '')
              .replaceAll('_$dateKey', '');

          String? jsonString = prefs.getString(key);
          if (jsonString != null && jsonString.isNotEmpty) {
            List<dynamic> jsonList = jsonDecode(jsonString);
            List<LocationPoint> points = jsonList
                .map((json) => LocationPoint.fromJson(json))
                .toList();
            allPoints[userId] = points;
          }
        }
      }

      return allPoints;
    } catch (e) {
      print('❌ Error loading all location points: $e');
      return {};
    }
  }

  /// Tears down all tracking state on logout.
  ///
  /// Stops the foreground service, cancels the scheduled job, and deletes
  /// every local artefact of the previous employee's session: the trail
  /// points (for ALL dates, not just today), the queued pings, the tracked
  /// user id and the ping window. Without this, the next person to log in on
  /// a shared device inherits the previous employee's location history — and
  /// the OS keeps waking us to ping a session that is no longer theirs.
  static Future<void> clearAllOnLogout() async {
    try {
      await BackgroundLocationService().stopTracking();
    } catch (_) {
      // stopTracking no-ops when tracking was never started.
    }

    try {
      await Workmanager().cancelByUniqueName(kBackgroundPingTaskName);
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      // Every cached trail, not only today's — a stale key from last week is
      // just as much of a leak.
      for (final key in prefs.getKeys().toList()) {
        if (key.startsWith('location_points_')) {
          await prefs.remove(key);
        }
      }
      await prefs.remove(_prefsUserIdKey);
      await prefs.remove(_prefsLastPingKey);
    } catch (_) {}

    // Queued pings belong to the previous employee's session and would be
    // flushed under the next user's token.
    try {
      await PingQueueService().clear();
    } catch (_) {}
  }

  /// Wipes today's locally cached trail points for whoever is being tracked.
  ///
  /// Called when the server reports no attendance for today. Those points are
  /// written straight to SharedPreferences by [_saveLocationPoint] and the
  /// map screen plots them without consulting the API, so without this a
  /// session deleted (or never persisted) server-side would keep drawing a
  /// route on the map indefinitely.
  static Future<void> clearTodaysLocalPoints() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString(_prefsUserIdKey);
      if (userId == null || userId.isEmpty) return;
      final now = DateTime.now();
      final dateKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await prefs.remove('location_points_${userId}_$dateKey');
    } catch (_) {
      // Non-fatal — the map simply keeps stale points until the next purge.
    }
  }

  // Clear location points for a user on specific date
  Future<void> clearLocationPoints(String userId, {DateTime? date}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dateKey = date != null ? _formatDate(date) : _getDateKey();
      final storageKey = 'location_points_${userId}_$dateKey';

      await prefs.remove(storageKey);
      print('🗑️ Cleared location points for $userId on $dateKey');
    } catch (e) {
      print('❌ Error clearing location points: $e');
    }
  }

  // Get today's date key
  String _getDateKey() {
    return _formatDate(DateTime.now());
  }

  // Format date as YYYY-MM-DD
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
