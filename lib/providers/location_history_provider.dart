// Location History Provider — drives the "Today's Timing" screen.
//
// Display modes (toggle on the screen):
//   - OFF (default on every screen open): show only the current active
//     session's latest punch-in point. Source: GET /attendance/today →
//     active_session.session_id → pick the matching `in` entry from
//     punches[].
//   - ON: show the full live ping timeline for the current active session.
//     Source: GET /attendance/session/{active_id}/timeline.
//
// Local SharedPreferences cache is NOT used here. If the server call fails
// we surface an error rather than silently showing stale data.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../models/location_point_model.dart';
import '../models/local_punch_record.dart';
import '../repositories/geofence_repository.dart';

/// One attendance session of the day, summarised. The points list flattens
/// every session into one chronological stream, which is right for a
/// timeline but loses the answer to "is this person still working?" — that
/// is what these carry.
class HistorySession {
  final int? id;
  final DateTime? startedAt;
  final DateTime? endedAt;

  /// As the server labels it: `active`, `closed`, or `force_closed`.
  final String status;
  final int pingCount;

  const HistorySession({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.status,
    required this.pingCount,
  });

  /// Open now. A session with no end time is running even if the server
  /// forgot to label it.
  bool get isActive =>
      status == 'active' || (status.isEmpty && endedAt == null);

  bool get isForceClosed => status == 'force_closed';

  String get label {
    if (isActive) return 'Active';
    return isForceClosed ? 'Auto-closed' : 'Completed';
  }

  /// Seconds worked, from the session's own timestamps. An open session is
  /// measured to now.
  int? get durationSeconds {
    final start = startedAt;
    if (start == null) return null;
    return (endedAt ?? DateTime.now()).difference(start).inSeconds;
  }
}

class LocationHistoryProvider extends ChangeNotifier {
  List<LocationPoint> _locationPoints = [];
  bool _isLoading = false;
  String? _errorMessage;

  /// Toggle state for the "Intermediate Tracking" switch. False = OFF (show
  /// only the latest punch-in). True = ON (show full live session timeline).
  /// Always starts OFF on each screen open — see [resetForScreenOpen].
  bool _isTrackingEnabled = false;

  String? _selectedUserId;
  String _selectedDate = _formatDate(DateTime.now());

  /// Total worked seconds for the currently loaded day. Populated by
  /// [loadHistoryForDate] from the history endpoint's `total_seconds`; null
  /// for today's live modes (which don't report a day total).
  int? _totalSeconds;

  List<LocationPoint> get locationPoints => _locationPoints;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isTrackingEnabled => _isTrackingEnabled;
  String? get selectedUserId => _selectedUserId;
  String get selectedDate => _selectedDate;
  int? get totalSeconds => _totalSeconds;

  /// Called on screen open (initState) — wipes any state carried over from a
  /// previous visit and re-asserts toggle = OFF. The provider is a singleton
  /// via Provider.of, so without this the toggle would otherwise persist
  /// across screen reopens.
  void resetForScreenOpen(String userId) {
    _sessions = const [];
    _isTrackingEnabled = false;
    _locationPoints = [];
    _errorMessage = null;
    _isLoading = false;
    _selectedUserId = userId;
    _selectedDate = _formatDate(DateTime.now());
    _totalSeconds = null;
    notifyListeners();
  }

  /// Toggle ON/OFF handler. Display-only — does NOT start/stop the OS-level
  /// background ping scheduler (that's owned by punch-in / punch-out in
  /// AttendanceProvider). The screen calls this and then re-loads data.
  void setLivePingsVisible(bool value) {
    if (_isTrackingEnabled == value) return;
    _isTrackingEnabled = value;
    notifyListeners();
  }

  /// Called when the screen wants the live ping timeline but no session id
  /// could be resolved — no session open today, and none recoverable from
  /// `/attendance/today`'s `punches[].session_id`.
  ///
  /// Exists so that case says something. It used to `return` silently, which
  /// rendered an indistinguishable empty list whether the user simply hadn't
  /// punched in or the backend had omitted `session_id` — the failure that
  /// hid the ping trail for weeks.
  void reportNoTrackableSession() {
    _locationPoints = [];
    _isLoading = false;
    _errorMessage =
        'No attendance session found for today, so there is no location '
        'trail to show. Punch in to start tracking.';
    notifyListeners();
  }

  /// Toggle = OFF mode. Fetches /attendance/today and surfaces **every**
  /// punch (in and out, across all sessions) for the day as a sorted list.
  ///
  /// Hydrates [GeofenceRepository] before parsing so the resulting
  /// [LocationPoint]s carry inside/outside info (used by the row ribbon).
  /// Empty list when the day has no punches yet — the screen interprets
  /// that as a "no punches today" empty state.
  Future<void> loadPunchPairForDate({
    required String token,
    required String userId,
    List<LocalPunchRecord> localFallback = const [],
  }) async {
    _isLoading = true;
    _errorMessage = null;
    _selectedUserId = userId;
    _selectedDate = _formatDate(DateTime.now());
    notifyListeners();

    // Prime the geofence cache so _pointFromMap can fill isInside/distanceM.
    await GeofenceRepository().loadCached();

    final points = <LocationPoint>[];

    try {
      final response = await ApiService.getAttendanceToday(token);
      if (!response.isSuccess || response.data == null) {
        _errorMessage = response.error ?? 'Failed to load today\'s attendance';
      } else {
        final raw = response.data!;
        final body = raw['data'] is Map<String, dynamic>
            ? raw['data'] as Map<String, dynamic>
            : raw;

        // Walk every punch for the day. Multiple sessions (in→out→in→out)
        // are all included — sorted ascending so the screen renders
        // chronologically without per-screen reversal.
        final punches = body['punches'];
        if (punches is List) {
          for (final p in punches) {
            if (p is! Map<String, dynamic>) continue;
            final typeRaw = (p['type'] ?? p['punch_type'] ?? p['kind'] ?? '')
                .toString();
            final t = typeRaw.toLowerCase();
            final isOut = t.contains('out');
            final isIn = t.contains('in') && !isOut;
            if (!isIn && !isOut) continue;
            final point = _pointFromMap(p, userId, type: isOut ? 'Out' : 'In');
            if (point != null) points.add(point);
          }
        }
      }
    } catch (e) {
      _errorMessage = 'Failed to load today\'s punches: $e';
    }

    // Backend wins, local fills gaps. Build a coverage set keyed by
    // session_id + type so we only append local entries the backend
    // hasn't already covered. Handles the common case where the backend
    // omits lat/lng on `/attendance/today` punches[] (which would
    // otherwise leave _locationPoints empty and the UI stuck on the
    // "Waiting for today's punch-in…" hourglass).
    if (localFallback.isNotEmpty) {
      String keyOf(int? sid, String type) => 'sid:${sid ?? "null"}:t:$type';
      final covered = <String>{
        for (final p in points) keyOf(_inferSidFromId(p.id), p.type),
      };
      for (final r in localFallback) {
        final type = r.type == PunchType.punchIn ? 'In' : 'Out';
        if (covered.contains(keyOf(r.sessionId, type))) continue;
        points.add(_localToPoint(r, userId));
      }
    }

    if (points.isNotEmpty) _errorMessage = null;

    // Stable order: ascending by timestamp, In before Out on ties.
    points.sort((a, b) {
      final byTime = a.timestamp.compareTo(b.timestamp);
      if (byTime != 0) return byTime;
      return a.type == 'In' ? -1 : 1;
    });
    _locationPoints = points;

    _isLoading = false;
    notifyListeners();
    // Backfill any rows the backend left without an address. Runs after
    // the main notify so the list paints immediately and addresses fade
    // in as each reverse-geocode resolves.
    // ignore: discarded_futures
    _fillMissingAddresses(userId);
  }

  /// Adapts a [LocalPunchRecord] (captured at punch-time from the device
  /// GPS) into a [LocationPoint]. Used as the fallback when
  /// `/attendance/today` returns punches without coords. Selfie is the
  /// local file path (will be a `file://` source for the card thumbnail);
  /// inside/outside comes from the cached geofence check stored at
  /// punch-time, distance from the same.
  LocationPoint _localToPoint(LocalPunchRecord r, String userId) {
    final type = r.type == PunchType.punchIn ? 'In' : 'Out';
    return LocationPoint(
      id: '${type}_${r.timestamp.millisecondsSinceEpoch}',
      userId: userId,
      timestamp: r.timestamp.toLocal(),
      type: type,
      latitude: r.latitude,
      longitude: r.longitude,
      accuracy: 0.0,
      address: r.address ?? '',
      selfiePath: r.selfieImagePath,
      isInside: r.isInsideOffice,
      distanceM: r.distanceFromOffice,
    );
  }

  /// Recovers the integer session_id that [_pointFromMap] never preserved
  /// directly on [LocationPoint]. The id format is `Type_<ms>` — there's
  /// nothing to recover here, so we return null. The coverage check above
  /// falls back to type-only matching when both sides have null sids.
  int? _inferSidFromId(String id) => null;

  /// Toggle = ON mode. Fetches the full live timeline for the given active
  /// session via GET /attendance/session/{id}/timeline and renders the
  /// resulting punch_in + pings + punch_out as a sorted chronological list.
  ///
  /// Surfaces the error to the UI on failure — no local-cache fallback.
  Future<void> loadFromTodaysSession({
    required String token,
    required int sessionId,
    required String userId,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    _selectedUserId = userId;
    _selectedDate = _formatDate(DateTime.now());
    notifyListeners();

    // Prime the geofence cache so every ping gets a green/red ribbon (the
    // ribbon color is derived from isInside in _pointFromMap below).
    await GeofenceRepository().loadCached();

    try {
      final response = await ApiService.getSessionTimeline(
        token: token,
        sessionId: sessionId,
      );
      if (!response.isSuccess || response.data == null) {
        _locationPoints = [];
        _errorMessage = response.error ?? 'Failed to load session timeline';
        return;
      }

      final raw = response.data!;
      final body = raw['data'] is Map<String, dynamic>
          ? raw['data'] as Map<String, dynamic>
          : raw;

      final points = <LocationPoint>[];

      final punchIn = body['punch_in'];
      if (punchIn is Map<String, dynamic>) {
        final p = _pointFromMap(punchIn, userId, type: 'In');
        if (p != null) points.add(p);
      }
      final pings = body['pings'];
      if (pings is List) {
        for (final ping in pings) {
          if (ping is Map<String, dynamic>) {
            final p = _pointFromMap(ping, userId, type: 'Tracking');
            if (p != null) points.add(p);
          }
        }
      }
      final punchOut = body['punch_out'];
      if (punchOut is Map<String, dynamic>) {
        final p = _pointFromMap(punchOut, userId, type: 'Out');
        if (p != null) points.add(p);
      }

      points.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      _locationPoints = points;
      // Ping timestamps are the server's own `captured_at`, rendered as-is.
      // Show the punch-in selfie on each tracking ping row.
      _applyPunchInSelfieToTracking();
    } catch (e) {
      _locationPoints = [];
      _errorMessage = 'Failed to load session timeline: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
      // ignore: discarded_futures
      _fillMissingAddresses(userId);
    }
  }

  /// Past-date browsing. Fetches GET /attendance/history?date=YYYY-MM-DD and
  /// flattens every session's punches (and, when [includePings] is true, its
  /// tracking pings) into the same chronological [LocationPoint] list the
  /// screen already renders for today.
  ///   - [includePings] = false (toggle OFF) → punches only.
  ///   - [includePings] = true  (toggle ON)  → punches + tracking pings.
  ///
  /// [adminUserId] is forwarded as `?user_id=` only when an admin is viewing
  /// another employee. Surfaces errors to the UI; no local-cache fallback.
  /// An empty day leaves [locationPoints] empty (the screen shows a clean
  /// "no records for this date" state).
  /// Sessions behind the current [locationPoints], newest last. Populated by
  /// [loadHistoryForDate] only — the live/today paths load a single session
  /// and have no list to summarise.
  List<HistorySession> _sessions = const [];
  List<HistorySession> get sessions => _sessions;

  Future<void> loadHistoryForDate({
    required String token,
    required String userId,
    required String date,
    required bool includePings,
    int? adminUserId,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    _selectedUserId = userId;
    _selectedDate = date;
    _totalSeconds = null;
    _sessions = const [];
    notifyListeners();

    // Prime the geofence cache so every point gets a green/red ribbon.
    await GeofenceRepository().loadCached();

    try {
      final response = await ApiService.getAttendanceHistoryByDate(
        token: token,
        date: date,
        userId: adminUserId,
      );
      if (!response.isSuccess || response.data == null) {
        _locationPoints = [];
        _sessions = const [];
        _errorMessage = response.error ?? 'Failed to load history';
        return;
      }

      final raw = response.data!;
      final body = raw['data'] is Map<String, dynamic>
          ? raw['data'] as Map<String, dynamic>
          : raw;

      _totalSeconds = _toDouble(body['total_seconds'])?.toInt();

      final points = <LocationPoint>[];
      final summaries = <HistorySession>[];
      final sessions = body['sessions'];
      if (sessions is List) {
        for (final s in sessions) {
          if (s is! Map<String, dynamic>) continue;

          final rawPings = s['pings'];
          summaries.add(
            HistorySession(
              id: _toDouble(s['session_id'] ?? s['id'])?.toInt(),
              startedAt: _parseTimestamp((s['started_at'] ?? '').toString()),
              endedAt: _parseTimestamp((s['ended_at'] ?? '').toString()),
              status: (s['status'] ?? '').toString().toLowerCase(),
              // The count the server actually sent, not the number we chose
              // to render — `includePings` false must not read as "no pings".
              pingCount: rawPings is List ? rawPings.length : 0,
            ),
          );

          final punches = s['punches'];
          if (punches is List) {
            for (final p in punches) {
              if (p is! Map<String, dynamic>) continue;
              final t = (p['type'] ?? '').toString().toLowerCase();
              final isOut = t.contains('out');
              final isIn = t.contains('in') && !isOut;
              if (!isIn && !isOut) continue;
              final point = _pointFromMap(
                p,
                userId,
                type: isOut ? 'Out' : 'In',
              );
              if (point != null) points.add(point);
            }
          }

          if (includePings) {
            final pings = s['pings'];
            if (pings is List) {
              for (final ping in pings) {
                if (ping is! Map<String, dynamic>) continue;
                final point = _pointFromMap(ping, userId, type: 'Tracking');
                if (point != null) points.add(point);
              }
            }
          }
        }
      }

      // Ascending by timestamp, In before Out on ties. Unlike today's live
      // mode we keep each ping's real `captured_at` — history timestamps are
      // reliable ISO-8601 (+05:30), so no client-side realignment is needed.
      points.sort((a, b) {
        final byTime = a.timestamp.compareTo(b.timestamp);
        if (byTime != 0) return byTime;
        return a.type == 'In' ? -1 : 1;
      });
      _locationPoints = points;
      _sessions = summaries;
      if (includePings) _applyPunchInSelfieToTracking();
    } catch (e) {
      _locationPoints = [];
      _sessions = const [];
      _errorMessage = 'Failed to load history: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
      // ignore: discarded_futures
      _fillMissingAddresses(userId);
    }
  }

  /// Silent refresh used by the 60-second auto-refresh loop while toggle is
  /// ON. Doesn't flip the isLoading flag so the UI doesn't blink a spinner
  /// every minute — the existing list just updates in place.
  Future<void> refreshTimelineSilently({
    required String token,
    required int sessionId,
    required String userId,
  }) async {
    try {
      final response = await ApiService.getSessionTimeline(
        token: token,
        sessionId: sessionId,
      );
      if (!response.isSuccess || response.data == null) return;

      final raw = response.data!;
      final body = raw['data'] is Map<String, dynamic>
          ? raw['data'] as Map<String, dynamic>
          : raw;

      final points = <LocationPoint>[];
      final punchIn = body['punch_in'];
      if (punchIn is Map<String, dynamic>) {
        final p = _pointFromMap(punchIn, userId, type: 'In');
        if (p != null) points.add(p);
      }
      final pings = body['pings'];
      if (pings is List) {
        for (final ping in pings) {
          if (ping is Map<String, dynamic>) {
            final p = _pointFromMap(ping, userId, type: 'Tracking');
            if (p != null) points.add(p);
          }
        }
      }
      final punchOut = body['punch_out'];
      if (punchOut is Map<String, dynamic>) {
        final p = _pointFromMap(punchOut, userId, type: 'Out');
        if (p != null) points.add(p);
      }
      points.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // Only notify if the list actually changed — avoids unnecessary
      // rebuilds when the 30-min backend cadence means nothing new landed.
      if (points.length != _locationPoints.length) {
        _locationPoints = points;
        _applyPunchInSelfieToTracking();
        notifyListeners();
        // ignore: discarded_futures
        _fillMissingAddresses(userId);
      }
    } catch (_) {
      // Silent fail — auto-refresh shouldn't surface transient network
      // blips. The next tick will retry.
    }
  }

  /// Converts a backend point-like map (punch-in, punch-out, or ping) into
  /// a [LocationPoint]. Returns null when coords or timestamp are missing.
  ///
  /// Computes [LocationPoint.isInside] / [LocationPoint.distanceM] locally
  /// when the [GeofenceRepository] cache is hydrated. Leaves them null when
  /// the cache is empty (cold start) — the row renders a neutral ribbon
  /// rather than guessing.
  LocationPoint? _pointFromMap(
    Map<String, dynamic> m,
    String userId, {
    required String type,
  }) {
    final lat = _toDouble(m['latitude']);
    final lng = _toDouble(m['longitude']);
    final tsRaw = (m['punched_at'] ?? m['captured_at'])?.toString();
    if (lat == null || lng == null || tsRaw == null) return null;
    final ts = _parseTimestamp(tsRaw);
    if (ts == null) return null;

    // Always compute the distance — check() falls back to the office config
    // when the server fence cache isn't hydrated, so the row can still show a
    // real distance instead of "—". The inside/outside verdict is only trusted
    // (for the ribbon color) when a real fence is actually cached; otherwise it
    // stays null so the ribbon renders neutral rather than guessing.
    final check = GeofenceRepository().check(lat, lng);
    final distanceM = check.distanceM;
    final bool? isInside = GeofenceRepository().cached != null
        ? check.inside
        : null;

    return LocationPoint(
      id: '${type}_${ts.millisecondsSinceEpoch}',
      userId: userId,
      timestamp: ts.toLocal(),
      type: type,
      latitude: lat,
      longitude: lng,
      accuracy: _toDouble(m['accuracy_m']) ?? 0.0,
      address: m['address']?.toString() ?? '',
      selfiePath: m['selfie_url']?.toString(),
      isInside: isInside,
      distanceM: distanceM,
      // Battery at capture time. Two shapes, because the two record types
      // carry it differently:
      //   * pings  — a real column, returned as a top-level `battery_pct`
      //   * punches — nested inside the `device_info` JSON we send on
      //     punch-in / punch-out (attendance_punches has no battery column)
      // Neither is returned by the API yet. Reading both means the badge
      // appears whichever way the backend chooses to expose it, with no
      // client release needed.
      batteryPct: _batteryFrom(m),
    );
  }

  /// Reuse the session's Punch In selfie as the image for every Tracking row.
  /// Background pings can't capture their own photo, so per product decision
  /// the punch-in face is shown on each ping row (falling back to a map-pin
  /// only when there's no punch-in selfie to borrow).
  void _applyPunchInSelfieToTracking() {
    String? inSelfie;
    for (final p in _locationPoints) {
      if (p.type == 'In' && (p.selfiePath?.isNotEmpty ?? false)) {
        inSelfie = p.selfiePath;
        break;
      }
    }
    if (inSelfie == null) return;
    for (var i = 0; i < _locationPoints.length; i++) {
      final p = _locationPoints[i];
      if (p.type == 'Tracking' &&
          (p.selfiePath == null || p.selfiePath!.isEmpty)) {
        _locationPoints[i] = p.copyWith(selfiePath: inSelfie);
      }
    }
  }

  // NOTE: `_alignTrackingTimestampsToPunchIn()` used to live here. It
  // re-stamped every Tracking row as punch_in + n*30min, because backend
  // pings once arrived as naive, timezone-skewed strings. That meant the
  // timeline displayed *derived* times, not real ones — a ping captured at
  // 10:47 rendered as 10:00. The server now sends `captured_at` as ISO-8601
  // with an explicit offset (see docs/geofence-module-guide.md §3.8), and
  // `_parseTimestamp` below still guards the naive case, so the real
  // timestamps are shown as recorded.

  /// Pulls the battery reading out of a point payload, top-level first and
  /// then from `device_info`.
  ///
  /// `device_info` may arrive as a decoded map (Laravel casts the column to
  /// `array`) or as a raw JSON string if the cast is ever dropped — both are
  /// handled, because a punch losing its badge over a serialisation detail
  /// would be invisible and hard to trace.
  static int? _batteryFrom(Map<String, dynamic> m) {
    final direct = _toDouble(m['battery_pct'])?.toInt();
    if (direct != null) return direct;

    final raw = m['device_info'];
    Map<String, dynamic>? info;
    if (raw is Map<String, dynamic>) {
      info = raw;
    } else if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) info = decoded;
      } catch (_) {
        return null;
      }
    }
    if (info == null) return null;
    return _toDouble(info['battery_pct'])?.toInt();
  }

  /// Lenient numeric read for backend payloads.
  ///
  /// Laravel serialises `decimal` columns (latitude, longitude, accuracy_m)
  /// as JSON **strings** by default, so a plain `as num?` cast throws a
  /// TypeError. Both callers here sit inside a broad try/catch, so that
  /// throw would surface as "Failed to load session timeline" and blank the
  /// whole screen over a formatting detail. Returns null for anything
  /// unparseable, which the callers already handle.
  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  /// Parses a backend timestamp string into a UTC [DateTime].
  ///
  /// The backend is inconsistent: punches arrive with a `Z` (or ±HH:MM) TZ
  /// suffix, but background-isolate pings often arrive as naive strings
  /// like `"2026-05-29T07:27:00"`. `DateTime.parse` treats the naive form
  /// as **local** time, which leaks the IST offset (≈5h30m) into the
  /// rendered hour. We detect the missing-TZ case and reinterpret as UTC,
  /// then the caller's `.toLocal()` lines up both kinds of timestamps.
  DateTime? _parseTimestamp(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    final hasTz =
        raw.endsWith('Z') ||
        raw.endsWith('z') ||
        RegExp(r'[+\-]\d{2}:?\d{2}$').hasMatch(raw);
    if (hasTz) return parsed;
    // Naive ISO → backend almost certainly sent UTC without the marker.
    // Re-stamp the wall-clock fields as UTC so .toLocal() shifts correctly.
    return DateTime.utc(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
    );
  }

  /// Best-effort client-side reverse-geocode for any row whose backend
  /// `address` was empty. The `geocoding` package's `placemarkFromCoordinates`
  /// is rate-limited and slow, so we run requests serially and update the
  /// in-memory list as each address resolves. Notifies once per successful
  /// fill so the UI patches the row instead of waiting for the full batch.
  Future<void> _fillMissingAddresses(String userId) async {
    final service = LocationService();
    for (var i = 0; i < _locationPoints.length; i++) {
      final p = _locationPoints[i];
      if (p.address.isNotEmpty) continue;
      if (p.userId != userId) continue;
      final addr = await service.getAddressFromCoordinates(
        p.latitude,
        p.longitude,
      );
      if (addr == null || addr.isEmpty) continue;
      // Index may have shifted if a fresh load happened mid-flight; re-find
      // the same id rather than assuming position stability.
      final stillIdx = _locationPoints.indexWhere((x) => x.id == p.id);
      if (stillIdx == -1) return;
      _locationPoints[stillIdx] = _locationPoints[stillIdx].copyWith(
        address: addr,
      );
      notifyListeners();
    }
  }

  // Set selected user (for admin)
  void setSelectedUser(String userId) {
    _selectedUserId = userId;
    notifyListeners();
  }

  // Set selected date
  void setSelectedDate(String date) {
    _selectedDate = date;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  List<String> getUniqueUserIds() {
    final userIds = _locationPoints.map((p) => p.userId).toSet().toList();
    return userIds;
  }

  List<LocationPoint> getPointsForUser(String userId) {
    // Ascending chronological — the new TimingRowCard list renders top-to-
    // bottom in order, so we don't reverse here anymore.
    return _locationPoints.where((p) => p.userId == userId).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  static String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
