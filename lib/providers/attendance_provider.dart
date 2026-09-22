// Attendance Provider to manage attendance state
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/attendance_model.dart';
import '../models/attendance_session.dart';
import '../models/today_attendance_model.dart';
import '../models/user_model.dart';
import '../models/location_point_model.dart';
import '../models/local_punch_record.dart';
import '../repositories/geofence_repository.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/camera_service.dart';
import '../services/device_info_helper.dart';
import '../services/background_location_service.dart';
import '../services/ping_queue_service.dart';

/// SharedPreferences key for the today-only local punch records cache. Lets
/// the Punch History screen show entries immediately on cold start, before
/// (or even when) the `/attendance/today` API has populated `_todayPunchRecords`.
const String _kLocalPunchRecordsPref = 'attendance_local_punch_records_v1';

class AttendanceProvider extends ChangeNotifier {
  /// Fires the cold-start rehydrate (persisted session + today's local punch
  /// records) the moment the provider is constructed. The provider is
  /// registered as `ChangeNotifierProvider(create: (_) => AttendanceProvider())`
  /// in main.dart, so this runs once per app launch. Fire-and-forget — any UI
  /// listening will rebuild via the `notifyListeners()` call inside.
  AttendanceProvider() {
    // ignore: discarded_futures
    loadPersistedSession();
  }

  List<AttendanceModel> _history = [];
  List<UserModel> _teamAttendance = [];
  TodayAttendanceModel? _todayAttendance;
  bool _isLoading = false;

  // Re-entrancy guards for the session punch flow. Separate from _isLoading,
  // which is only raised once the upload starts — these cover the whole call
  // including the GPS fix and reverse geocode that precede it.
  bool _punchInFlight = false;
  bool _punchOutFlight = false;
  String? _errorMessage;
  bool _isClockedIn = false;

  // Calendar data: key is date string "yyyy-MM-dd", value is {status, late, type}
  Map<String, Map<String, dynamic>> _calendarData = {};
  bool _isCalendarLoading = false;

  // My Attendance data from get_my_attendance API
  List<Map<String, dynamic>> _myAttendanceData = [];
  Map<String, dynamic> _myAttendanceSummary = {};
  bool _isMyAttendanceLoading = false;

  // Location tracking state
  bool _isTrackingLocation = false;
  List<Map<String, double>> _trackedRoute = [];
  Map<String, double>? _currentPosition;
  Map<String, dynamic> _geofenceStatus = {};
  DateTime? _trackingStartTime;
  StreamSubscription<Position>? _locationSubscription;
  String _trackingDuration = '00:00:00';
  Timer? _durationTimer;
  double _totalDistanceTracked = 0;

  // Selfie & punch state
  String? _pendingSelfiePath;

  // Local punch records with location
  List<LocalPunchRecord> _localPunchRecords = [];

  // Active attendance session (from backend /attendance/punch-in).
  AttendanceSession? _activeSession;

  // Fires at the next local midnight to auto-clear a session that rolled over
  // from the previous calendar day, so the UI shows a fresh Punch In button
  // for the new day instead of leaving the user "still clocked in" from
  // yesterday. Re-armed whenever an active session exists.
  Timer? _midnightRolloverTimer;

  // Last-known geofence status from the most recent punch (for UI banner).
  // Keys: inside (bool), distanceM (double), radiusM (int?).
  Map<String, dynamic>? _lastPunchGeofence;

  // Conflict state: server says a session is already open (see spec §4.4.2).
  Map<String, dynamic>? _sessionConflict;

  // Server-side feature flag mirrored from /me/geofence.geofence_attendance.
  // Default true so the button isn't silently hidden before the config loads;
  // becomes false only when the backend explicitly returns "No".
  bool _isGeofenceAttendanceEnabled = true;

  // Punch times for today, sourced from the new /attendance/today endpoint
  // and from punch-in/out success responses. The legacy /today-employee-
  // attendance endpoint doesn't know about session-based punches, so the
  // punch cards can't rely on todayAttendance.firstIn/lastOut alone.
  DateTime? _lastPunchIn;
  DateTime? _lastPunchOut;

  // Today's punch records as returned by the backend. Persisted across app
  // restarts via /attendance/today, unlike [_localPunchRecords] which is
  // in-memory only. Used by the Punch History screen and the attendance
  // timeline on the attendance tab.
  List<LocalPunchRecord> _todayPunchRecords = <LocalPunchRecord>[];

  // Total seconds the employee has been clocked in across all closed
  // sessions today (as reported by /attendance/today.total_seconds). An
  // active/open session is not counted until it closes. Drives the
  // work-hours chip for geofence users.
  int? _todayTotalSeconds;

  List<AttendanceModel> get history => _history;
  List<UserModel> get teamAttendance => _teamAttendance;
  TodayAttendanceModel? get todayAttendance => _todayAttendance;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isClockedIn => _isClockedIn;
  Map<String, Map<String, dynamic>> get calendarData => _calendarData;
  bool get isCalendarLoading => _isCalendarLoading;
  List<Map<String, dynamic>> get myAttendanceData => _myAttendanceData;
  Map<String, dynamic> get myAttendanceSummary => _myAttendanceSummary;
  bool get isMyAttendanceLoading => _isMyAttendanceLoading;

  // Tracking getters
  bool get isTrackingLocation => _isTrackingLocation;
  List<Map<String, double>> get trackedRoute => _trackedRoute;
  Map<String, double>? get currentPosition => _currentPosition;
  Map<String, dynamic> get geofenceStatus => _geofenceStatus;
  String get trackingDuration => _trackingDuration;
  double get totalDistanceTracked => _totalDistanceTracked;
  String? get pendingSelfiePath => _pendingSelfiePath;
  List<LocalPunchRecord> get localPunchRecords => _localPunchRecords;
  AttendanceSession? get activeSession => _activeSession;
  bool get hasActiveSession => _activeSession != null;
  Map<String, dynamic>? get lastPunchGeofence => _lastPunchGeofence;
  Map<String, dynamic>? get sessionConflict => _sessionConflict;

  /// Whether the current branch has geofence-based attendance enabled.
  /// Mirrors `geofence_attendance == "Yes"` from the `/me/geofence` response.
  /// Drives visibility of the punch button on the dashboard and attendance
  /// screens — when false, the user cannot punch in/out from the app.
  bool get isGeofenceAttendanceEnabled => _isGeofenceAttendanceEnabled;

  /// Today's punch records as returned by the backend (survives app restart).
  /// Falls back to the in-memory local list when the server hasn't replied yet.
  /// Merged punch list for the Punch History screen.
  ///
  /// Rule: **API wins, local fills gaps.** When `/attendance/today` has
  /// returned records we treat the server as source of truth. We then
  /// append any local-only records whose `session_id` (or `id` when no
  /// session_id is set) isn't represented server-side — that covers the
  /// "just punched but the API hasn't aggregated yet" window and any
  /// offline punch waiting to sync. The final list is sorted by timestamp
  /// so the UI's reverse() call still shows newest first.
  List<LocalPunchRecord> get todayPunchRecords {
    if (_todayPunchRecords.isEmpty) return _localPunchRecords;

    final serverKeys = <String>{
      for (final r in _todayPunchRecords)
        r.sessionId != null ? 'sid:${r.sessionId}:${r.type.name}' : 'id:${r.id}',
    };

    final merged = <LocalPunchRecord>[..._todayPunchRecords];
    for (final r in _localPunchRecords) {
      final key = r.sessionId != null
          ? 'sid:${r.sessionId}:${r.type.name}'
          : 'id:${r.id}';
      if (!serverKeys.contains(key)) merged.add(r);
    }
    merged.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return merged;
  }

  /// Formatted most-recent punch-in time for today (e.g. "09:25 AM"), or null
  /// when the user hasn't punched in yet today. Reflects the LATEST punch-in
  /// the user performed (not the first of the day), so the card updates after
  /// each new punch-in even when the user has multiple sessions in a day.
  String? get lastPunchInDisplay =>
      _lastPunchIn == null ? null : _fmtTimeOfDay(_lastPunchIn!);

  /// Formatted most-recent punch-out time for today, or null when the user
  /// hasn't punched out yet today.
  String? get lastPunchOutDisplay =>
      _lastPunchOut == null ? null : _fmtTimeOfDay(_lastPunchOut!);

  /// Work-hours number string sourced from /attendance/today.total_seconds,
  /// matching the legacy `todayAttendance.totalWorkHours` format (e.g.
  /// "7.50"). The caller appends "hrs" in the UI. Returns null when the
  /// endpoint hasn't populated the field (non-geofence user never called
  /// it, or no closed session yet today — the backend reports 0 for an
  /// open session).
  String? get todayWorkHoursDisplay {
    final secs = _todayTotalSeconds;
    if (secs == null) return null;
    return (secs / 3600.0).toStringAsFixed(2);
  }

  /// True when the employee has completed today's full punch-in / punch-out
  /// cycle (backend enforces one cycle per IST calendar day; the client
  /// mirrors that so the UI locks both buttons until midnight). Derived from
  /// existing state — no separate field or persistence needed:
  ///   - _lastPunchOut is today's local date, AND
  ///   - no active session is currently open.
  bool get todayCycleCompleted {
    final out = _lastPunchOut;
    if (out == null) return false;
    if (_activeSession != null) return false;
    final now = DateTime.now();
    final outLocal = out.toLocal();
    return outLocal.year == now.year &&
        outLocal.month == now.month &&
        outLocal.day == now.day;
  }

  /// Session id for today's attendance session, or null when the employee
  /// hasn't punched in yet today. Prefers the active session, then falls
  /// back to the most recent punch record (backend includes session_id on
  /// each punch in /attendance/today.punches), so the id is recoverable
  /// even after punch-out and fresh installs.
  int? get todaySessionId {
    final active = _activeSession?.sessionId;
    if (active != null) return active;
    for (final r in _todayPunchRecords.reversed) {
      if (r.sessionId != null) return r.sessionId;
    }
    return null;
  }

  String _fmtTimeOfDay(DateTime dt) {
    final local = dt.toLocal();
    final h12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final mm = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    return '${h12.toString().padLeft(2, '0')}:$mm $ampm';
  }

  /// Rehydrates session state from SharedPreferences on app start.
  Future<void> loadPersistedSession() async {
    _activeSession = await AttendanceSession.load();
    if (_activeSession != null) {
      _isClockedIn = true;
      _lastPunchIn ??= _activeSession!.startedAt;
    }
    // Restore today's punch records from disk so the Punch History screen
    // doesn't go blank between cold start and the first /attendance/today
    // response.
    await _loadPunchRecords();
    // If the persisted session is from a prior day, clear it immediately so
    // the UI shows Punch In for the new day.
    _handleMidnightRollover();
    _scheduleMidnightRollover();
    notifyListeners();
  }

  /// Writes `_localPunchRecords` to SharedPreferences. Called after every
  /// punch-in / punch-out and after the session_id stamp in the success path,
  /// so a kill+relaunch right after a punch never loses the entry.
  Future<void> _savePunchRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _localPunchRecords.map((r) => r.toJson()).toList();
      await prefs.setString(_kLocalPunchRecordsPref, jsonEncode(list));
    } catch (e) {
      debugPrint('⚠️ _savePunchRecords failed: $e');
    }
  }

  /// Restores `_localPunchRecords` from SharedPreferences, dropping any record
  /// whose timestamp isn't on today's local date (matches the screen's
  /// today-only scope and prevents the cache from growing forever).
  Future<void> _loadPunchRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kLocalPunchRecordsPref);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;

      final now = DateTime.now();
      final restored = <LocalPunchRecord>[];
      final stale = <LocalPunchRecord>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          final rec = LocalPunchRecord.fromJson(
            item.cast<String, dynamic>(),
          );
          final local = rec.timestamp.toLocal();
          final isToday = local.year == now.year &&
              local.month == now.month &&
              local.day == now.day;
          if (isToday) {
            restored.add(rec);
          } else {
            stale.add(rec);
          }
        } catch (_) {
          // Skip corrupted entries rather than wiping the whole cache.
        }
      }
      _localPunchRecords = restored;

      // The punch-card times are NOT seeded from disk.
      //
      // They used to be, so a cold start wouldn't flash "--:--" before
      // /attendance/today landed. But that made the card assert a punch time
      // on the strength of local storage alone: when a punch was deleted
      // server-side (or never persisted), every app launch replayed it from
      // disk and the employee saw a punch-in that does not exist in the
      // database. Times now come only from the server — /attendance/today for
      // geofence users, /today-employee-attendance otherwise — and the card
      // shows "--:--" until one of them answers.
      //
      // `restored` is still kept as a cache of server-confirmed punches (for
      // the Punch History thumbnails); _parseTodayPunches drops any entry the
      // server doesn't confirm on the next successful sync.

      // Free disk for anything no longer in scope (yesterday's selfies, etc.).
      _purgeSelfies(stale);

      // If everything was stale (yesterday or older), drop the persisted blob.
      if (restored.isEmpty) {
        await prefs.remove(_kLocalPunchRecordsPref);
      }
    } catch (e) {
      debugPrint('⚠️ _loadPunchRecords failed: $e');
    }
  }

  /// Arms a one-shot timer that fires at the next local midnight and clears a
  /// session that has rolled over into a new calendar day. The fire also
  /// reschedules itself, so the provider keeps checking day-to-day as long as
  /// the app is alive.
  void _scheduleMidnightRollover() {
    _midnightRolloverTimer?.cancel();
    // Only arm when there's actually something to roll over.
    if (_activeSession == null) return;
    final now = DateTime.now();
    // Fire 1 second past midnight so DateTime.now() on fire reliably lands on
    // the new day (avoids flakiness from Timer firing a hair early).
    final nextFire = DateTime(now.year, now.month, now.day + 1).add(
      const Duration(seconds: 1),
    );
    final wait = nextFire.difference(now);
    _midnightRolloverTimer = Timer(wait, () {
      _handleMidnightRollover();
      _scheduleMidnightRollover();
    });
  }

  /// If an active session started on a prior calendar day, treat it as closed
  /// locally so the punch card resets to Punch In for today. We can't call the
  /// backend punch-out here (it requires a selfie the user never captured), so
  /// the server-side session stays open until the user's next real action —
  /// the existing SESSION_ALREADY_OPEN path handles that case.
  void _handleMidnightRollover() {
    final session = _activeSession;
    if (session == null) return;
    final now = DateTime.now();
    final startLocal = session.startedAt.toLocal();
    final startedToday = startLocal.year == now.year &&
        startLocal.month == now.month &&
        startLocal.day == now.day;
    if (startedToday) return;

    _activeSession = null;
    _isClockedIn = false;
    // Clear punch times so today's card renders fresh "--:--" values instead
    // of leaking yesterday's punch-in time into the new day.
    _lastPunchIn = null;
    _lastPunchOut = null;
    _todayTotalSeconds = null;
    _todayPunchRecords = <LocalPunchRecord>[];
    // Drop the persisted local cache too — yesterday's punches shouldn't
    // resurrect on tomorrow's first cold start. Delete their selfies first
    // so app docs dir doesn't accumulate forever.
    _purgeSelfies(_localPunchRecords);
    _localPunchRecords.clear();
    unawaited(_savePunchRecords());
    AttendanceSession.clear();
    BackgroundLocationService().stopTracking();
    notifyListeners();
  }

  /// Reads the cached geofence from SharedPreferences (no network) and mirrors
  /// `geofence_attendance` into this provider so the UI rebuilds.
  Future<void> loadGeofenceConfig() async {
    await GeofenceRepository().loadCached();
    _applyGeofenceFlag();
  }

  /// Refreshes the geofence from `/me/geofence` and mirrors the resulting flag.
  /// Silent on network error — the UI keeps the previously known value.
  Future<void> refreshGeofenceConfig(String token) async {
    try {
      await GeofenceRepository().refresh(token);
      _applyGeofenceFlag();
    } catch (e) {
      debugPrint('⚠️ refreshGeofenceConfig failed: $e');
    }
  }

  /// Screen-open bootstrap for the geofence flow (Case 1).
  ///   1. Refreshes `/me/geofence` so we know whether the user is
  ///      geofence-enabled (this runs for every user — it's the only way to
  ///      read `geofence_attendance`).
  ///   2. Only when the flag is "Yes", pulls `/attendance/today` to rebuild
  ///      session state. Non-geofence users never touch the session-based
  ///      endpoint.
  Future<void> bootstrapForGeofenceUser(String token, {String? userId}) async {
    await refreshGeofenceConfig(token);
    if (_isGeofenceAttendanceEnabled) {
      await syncActiveSession(token, userId: userId);
    }
  }

  void _applyGeofenceFlag() {
    final g = GeofenceRepository().cached;
    // When the repo has no cached value yet, default to enabled (optimistic).
    // Once the server responds, only an explicit "No" turns the button off.
    final next = g?.isAttendanceEnabled ?? true;
    if (next != _isGeofenceAttendanceEnabled) {
      _isGeofenceAttendanceEnabled = next;
      notifyListeners();
    }
  }

  /// Syncs the active session with the server using GET /attendance/today.
  ///
  /// The server is authoritative — if it reports no active session, any local
  /// copy is discarded (covers "app was killed after punch-out completed but
  /// before the local state was cleared"). If the server has a session that we
  /// don't, we restore it so punch-out still works after an app restart.
  ///
  /// Silent on network error so app launch is never blocked.
  Future<void> syncActiveSession(String token, {String? userId}) async {
    // Session-based attendance (open sessions, restore-across-restart, the
    // punch card's live times) only applies to geofence-enabled users. For
    // everyone else there is no session to restore, so bail early — this also
    // guarantees the fixes below (no fabricated punch-in time, fail-safe
    // cross-day guard) never touch a non-geofence account.
    if (!_isGeofenceAttendanceEnabled) return;
    try {
      debugPrint('🟦 [PUNCH-HISTORY-DEBUG] Calling GET /attendance/today …');
      final response = await ApiService.getAttendanceToday(token);
      debugPrint(
        '🟦 [PUNCH-HISTORY-DEBUG] Response: isSuccess=${response.isSuccess} '
        'error=${response.error} data is null? ${response.data == null}',
      );
      if (!response.isSuccess || response.data == null) {
        debugPrint(
          '🟥 [PUNCH-HISTORY-DEBUG] Aborting — API failed or returned no body. '
          'History will fall back to local cache only.',
        );
        return;
      }

      final raw = response.data!;
      // Print the full body so you can see EXACTLY what the backend sent.
      // debugPrint chunks long strings automatically so this won't get truncated.
      debugPrint('🟦 [PUNCH-HISTORY-DEBUG] Raw body keys: ${raw.keys.toList()}');
      debugPrint('🟦 [PUNCH-HISTORY-DEBUG] Full body: ${jsonEncode(raw)}');

      final body = raw['data'] is Map<String, dynamic>
          ? raw['data'] as Map<String, dynamic>
          : raw;

      final punches = body['punches'];
      if (punches is List) {
        debugPrint(
          '🟦 [PUNCH-HISTORY-DEBUG] punches[] length = ${punches.length}',
        );
        if (punches.isNotEmpty) {
          // Log the first entry so you can see field names + whether
          // latitude/longitude/selfie_url are present (those are what the
          // parser requires to keep a record).
          debugPrint(
            '🟦 [PUNCH-HISTORY-DEBUG] First punch sample: ${jsonEncode(punches.first)}',
          );
        }
      } else {
        debugPrint(
          '🟥 [PUNCH-HISTORY-DEBUG] body["punches"] is NOT a list '
          '(got ${punches.runtimeType}). Backend may not be returning the '
          'punches array — history cannot be rebuilt from the server.',
        );
      }

      // Parse today's punch list → records + first-in / last-out times.
      _parseTodayPunches(body);

      debugPrint(
        '🟩 [PUNCH-HISTORY-DEBUG] After parse: _todayPunchRecords has '
        '${_todayPunchRecords.length} record(s). '
        '(If this is 0 but punches[] above was non-empty, the parser dropped '
        'them — most likely because latitude/longitude were missing.)',
      );

      final serverSession = body['active_session'];

      if (serverSession is Map<String, dynamic>) {
        final id = _asInt(serverSession['session_id']);
        // The server names this `started_at` (docs/geofence-module-guide.md
        // §3.6). Reading only `opened_at` meant this was ALWAYS null, so the
        // "started today?" guard below failed for every session and cleared
        // the one we had just opened — the user was silently un-clocked-in
        // and their punch-in time vanished on the next refresh.
        final openedAt =
            (serverSession['started_at'] ?? serverSession['opened_at'])
                ?.toString();
        if (id != null) {
          // Parse the server's opened_at WITHOUT fabricating a time. Previously
          // a missing/blank opened_at fell back to DateTime.now(), which then
          // leaked onto the punch card as a punch-in the user never made (they
          // just logged in). We now keep it null and let the guard below decide.
          final parsedOpenedAt =
              openedAt == null ? null : DateTime.tryParse(openedAt)?.toLocal();

          // Cross-day guard, fail-safe: only restore the session as ACTIVE when
          // opened_at is present, parseable, AND lands on today's local date.
          // A missing / unparseable / prior-day opened_at all resolve to "not a
          // valid session for today" → we clear it and show Punch In. This is
          // what stops a stale open session (never closed server-side at end of
          // day) from showing the user as still clocked-in the next morning and
          // forcing a manual punch-out before they can punch in again.
          final now = DateTime.now();
          final startedToday = parsedOpenedAt != null &&
              parsedOpenedAt.year == now.year &&
              parsedOpenedAt.month == now.month &&
              parsedOpenedAt.day == now.day;

          // Destructive branches require POSITIVE evidence.
          //
          // This guard used to fire whenever `startedToday` was false, which
          // included the "we couldn't read the timestamp at all" case. When
          // the field name drifted (`opened_at` vs `started_at`) that turned a
          // cosmetic parse miss into data loss: it wiped the live session from
          // memory AND from disk on every sync, so users were silently
          // un-clocked-in and could not punch out.
          //
          // Absence of a timestamp now means "unknown", and unknown leaves
          // state alone. A genuinely stale session is still cleaned up by the
          // midnight rollover timer, and by the 409 SESSION_ALREADY_OPEN
          // handling on the next punch-in — neither of which depends on
          // parsing this field.
          if (parsedOpenedAt == null) {
            debugPrint(
              '🟥 [SESSION] active_session has no readable start time '
              '(keys: ${serverSession.keys.toList()}). Keeping existing '
              'session rather than clearing it — check the API contract.',
            );
            assert(
              false,
              'active_session is missing started_at/opened_at — the server '
              'contract changed. See docs/geofence-module-guide.md §3.6.',
            );
          }

          if (parsedOpenedAt != null && !startedToday) {
            if (_activeSession != null) {
              _activeSession = null;
              await AttendanceSession.clear();
            }
            _isClockedIn = false;
            _midnightRolloverTimer?.cancel();
            // Only the SESSION is stale here — today's punch data is not.
            // `_parseTodayPunches` ran a few lines above and already filtered
            // `punches[]` down to sessions that started today, so whatever it
            // produced is genuinely today's. Clearing `_lastPunchIn` /
            // `_lastPunchOut` / `_todayPunchRecords` in this branch meant a
            // single unparseable or prior-day `opened_at` on the server's
            // `active_session` blanked out punches the user really did make:
            // the punch card fell back to "--:--" and Punch History went
            // empty on every refresh.
            notifyListeners();
            return;
          }

          // Start time, best available source. The server's value wins; when
          // it's unreadable we reuse what we already hold (the session we
          // opened at punch-in, or the parsed punch time) rather than
          // fabricating `now()` — a fabricated time would show the user a
          // punch-in they never made.
          final startedAt =
              parsedOpenedAt ?? _activeSession?.startedAt ?? _lastPunchIn;
          if (startedAt == null) {
            // No readable time anywhere. Keep the session id usable but don't
            // invent a clock reading; leave the card to the punches[] parser.
            debugPrint(
              '🟥 [SESSION] No start time from server or local state for '
              'session $id — leaving punch times untouched.',
            );
            _isClockedIn = true;
            notifyListeners();
            return;
          }

          final session = AttendanceSession(
            sessionId: id,
            startedAt: startedAt,
          );
          _activeSession = session;
          _isClockedIn = true;
          // The currently-open session's opened_at IS the user's latest
          // punch-in — and it's now guaranteed to be a real, today-local time
          // (never a fabricated now()). Only fall back to it when the punches[]
          // parser didn't already pick one up.
          _lastPunchIn ??= session.startedAt;
          await session.save();
          _scheduleMidnightRollover();
          // The session is open but this process may be a fresh one (app was
          // swiped away / killed / phone rebooted mid-shift). Re-arm the
          // foreground location service — it lives in memory and died with
          // the old isolate, while the session survived on disk. No-op when
          // tracking is already running.
          unawaited(BackgroundLocationService()
              .resumeTrackingIfNeeded(fallbackUserId: userId));
          notifyListeners();
          return;
        }
      }

      // Server says no active session — drop any stale local copy.
      if (_activeSession != null) {
        _activeSession = null;
        await AttendanceSession.clear();
      }
      _isClockedIn = false;
      _midnightRolloverTimer?.cancel();
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ syncActiveSession failed: $e');
    }
  }

  /// Walks today's punches payload and populates:
  ///   - [_todayPunchRecords]: full punch records (for the Punch History
  ///     screen and the attendance timeline), with `selfieImagePath` holding
  ///     a remote URL if the backend returned one.
  ///   - [_lastPunchIn] / [_lastPunchOut]: punch-card time labels.
  ///
  /// Accepts several common shapes so it works even if the backend tweaks keys:
  ///   { punches: [{type: "in"|"out", timestamp|captured_at|punched_at: "..."}] }
  ///   { punches: [...] } with 'punch_type' or 'kind' fields
  ///   { first_in: "...", last_out: "..." } as a flat fallback.
  void _parseTodayPunches(Map<String, dynamic> body) {
    DateTime? latestIn;
    DateTime? latestOut;
    final records = <LocalPunchRecord>[];
    final now = DateTime.now();

    // First pass: collect session IDs whose punch-IN appears in today's
    // response with a today-local timestamp. A cross-midnight session only
    // shows up here via its punch-out (the in happened yesterday and isn't
    // in today's payload), so the absence of a punch-in is our signal that
    // the whole session belongs to yesterday and should be ignored here.
    final punches = body['punches'];
    final sessionsStartedToday = <int>{};
    if (punches is List) {
      for (final p in punches) {
        if (p is! Map) continue;
        final map = p.cast<String, dynamic>();
        final sid = _asInt(map['session_id']);
        if (sid == null) continue;
        final typeRaw =
            (map['type'] ?? map['punch_type'] ?? map['kind'] ?? '').toString();
        final t = typeRaw.toLowerCase();
        final isIn = t.contains('in') && !t.contains('out');
        if (!isIn) continue;
        final timeRaw = (map['timestamp'] ??
                map['captured_at'] ??
                map['punched_at'] ??
                map['time'])
            ?.toString();
        final dt = timeRaw == null ? null : DateTime.tryParse(timeRaw);
        if (dt == null) continue;
        final local = dt.toLocal();
        if (local.year == now.year &&
            local.month == now.month &&
            local.day == now.day) {
          sessionsStartedToday.add(sid);
        }
      }
    }

    bool sessionStartedToday(int? sid) {
      if (sid == null) return true; // no session_id → treat as today (legacy)
      return sessionsStartedToday.contains(sid);
    }

    if (punches is List) {
      for (final p in punches) {
        if (p is! Map) continue;
        final map = p.cast<String, dynamic>();

        final sid = _asInt(map['session_id']);
        // Skip any punch whose session didn't start today. That filters out
        // cross-midnight punch-outs (session's punch-in was yesterday and
        // isn't in the response), which would otherwise leak yesterday's
        // close time onto today's punch card.
        if (!sessionStartedToday(sid)) continue;

        final typeRaw =
            (map['type'] ?? map['punch_type'] ?? map['kind'] ?? '').toString();
        final t = typeRaw.toLowerCase();
        final isIn = t.contains('in') && !t.contains('out');
        final isOut = t.contains('out');

        final timeRaw = (map['timestamp'] ??
                map['captured_at'] ??
                map['punched_at'] ??
                map['time'])
            ?.toString();
        final dt = timeRaw == null ? null : DateTime.tryParse(timeRaw);
        if (dt != null) {
          // Track the LATEST in/out of the day so the punch card reflects
          // the user's most recent action.
          if (isIn && (latestIn == null || dt.isAfter(latestIn))) latestIn = dt;
          if (isOut && (latestOut == null || dt.isAfter(latestOut))) {
            latestOut = dt;
          }
        }

        // Build a full record so the Punch History screen can render it.
        final lat = _asDouble(map['latitude']);
        final lng = _asDouble(map['longitude']);
        if (dt != null && lat != null && lng != null) {
          final insideRaw = map['inside_geofence'];
          final inside = insideRaw == null
              ? true
              : (insideRaw == true || insideRaw == 1 || insideRaw == '1');
          // Distance: prefer a meaningful server value; otherwise compute it
          // locally (against the cached branch fence, or the office fallback)
          // so Punch History never shows a blank "—" or "0 m".
          final backendDist = _asDouble(map['distance_m']);
          final distance = (backendDist != null && backendDist > 0)
              ? backendDist
              : GeofenceRepository().check(lat, lng).distanceM;
          records.add(
            LocalPunchRecord(
              id: (map['id'] ?? dt.millisecondsSinceEpoch).toString(),
              timestamp: dt.toLocal(),
              type: isOut ? PunchType.punchOut : PunchType.punchIn,
              latitude: lat,
              longitude: lng,
              address: map['address']?.toString(),
              selfieImagePath: map['selfie_url']?.toString(),
              isInsideOffice: inside,
              distanceFromOffice: distance,
              sessionId: sid,
            ),
          );
        }
      }
    }

    // Flat-shape fallback when the backend returns top-level first_in/last_out
    // strings instead of a punches[] array. These fields are often populated
    // from the biometric system on the server side and can include yesterday's
    // times when a session spans midnight — accept them only when the parsed
    // timestamp is today's local date, so biometric data from a prior day
    // doesn't bleed onto today's punch card.
    bool isLocalToday(DateTime? dt) {
      if (dt == null) return false;
      final local = dt.toLocal();
      return local.year == now.year &&
          local.month == now.month &&
          local.day == now.day;
    }

    if (latestIn == null) {
      final flatIn = _parseFlexibleTime(body['last_in']) ??
          _parseFlexibleTime(body['first_in']);
      if (isLocalToday(flatIn)) latestIn = flatIn;
    }
    if (latestOut == null) {
      final flatOut = _parseFlexibleTime(body['last_out']);
      if (isLocalToday(flatOut)) latestOut = flatOut;
    }

    // Keep chronological order (oldest → newest). The UI reverses for display.
    records.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // The server is authoritative. This method only runs after a SUCCESSFUL
    // /attendance/today response, so an empty punches[] means "you have not
    // punched today" — not "we don't know".
    //
    // This used to fall back to the last locally-known time whenever the
    // server sent nothing, a workaround from when /attendance/today returned
    // `punches: []` even for employees who had punched. That endpoint now
    // returns punches correctly, and the fallback had become the bug: a punch
    // deleted (or never persisted) server-side stayed on the card forever,
    // replayed from disk on every refresh, showing the employee a punch-in
    // that no longer exists in the database.
    _lastPunchIn = latestIn;
    _lastPunchOut = latestOut;
    _todayPunchRecords = records;

    // Drop any locally cached punch the server did not confirm. The local
    // cache is a mirror of database rows, never a second source of truth.
    if (_localPunchRecords.isNotEmpty) {
      // Keyed off `sessionsStartedToday`, which is built from the RAW
      // punches[] above — not from `records`, which drops any punch missing
      // coordinates. A punch the server has but couldn't plot must still
      // count as confirmed, or we would purge a valid local record.
      final serverSessionIds = sessionsStartedToday;
      final confirmed = _localPunchRecords.where((r) {
        if (!isLocalToday(r.timestamp)) return false;
        return r.sessionId != null && serverSessionIds.contains(r.sessionId);
      }).toList();

      if (confirmed.length != _localPunchRecords.length) {
        debugPrint(
          '🧹 Dropping ${_localPunchRecords.length - confirmed.length} local '
          'punch record(s) the server does not have.',
        );
        _localPunchRecords = confirmed;
        unawaited(_savePunchRecords());
      }
    }

    // The map screen plots today's trail straight from SharedPreferences,
    // bypassing the API entirely. When the server has no punches today those
    // points describe a session that no longer exists, so drop them too —
    // otherwise a deleted session keeps drawing a route.
    if (sessionsStartedToday.isEmpty) {
      unawaited(BackgroundLocationService.clearTodaysLocalPoints());
    }
    // Session-based total for geofence users. Represents the sum of all
    // closed sessions today — active sessions don't contribute until
    // they're punched out (that's the backend's contract).
    _todayTotalSeconds = _asInt(body['total_seconds']);

    // Sanity-check the server's total against the punches it sent alongside
    // it. We do NOT override it — the server owns attendance — but a large
    // disagreement means the session row and its own punches contradict each
    // other, and that must not pass silently.
    //
    // Observed 1 Sep 2026: a 12:51 → 18:08 shift (5h16m) came back as
    // total_seconds = 1218 (20m), because the session's `started_at` had been
    // overwritten with the punch-out time. That figure feeds work-hours
    // reporting and payroll. See docs/backend-urgent-session-times.md.
    final total = _todayTotalSeconds;
    if (total != null &&
        total > 0 &&
        latestIn != null &&
        latestOut != null &&
        latestOut.isAfter(latestIn)) {
      final fromPunches = latestOut.difference(latestIn).inSeconds;
      // 5 minutes of slack covers rounding and multi-session days, where the
      // server's total legitimately differs from first-in/last-out.
      if ((fromPunches - total).abs() > 300) {
        debugPrint(
          '🟥 [HOURS] total_seconds=$total disagrees with punches '
          '(${latestIn.toIso8601String()} → ${latestOut.toIso8601String()} '
          '= ${fromPunches}s). Session row and punches contradict each other — '
          'work hours are likely wrong server-side.',
        );
      }
    }
  }

  /// Lenient int reader. The backend serialises some numeric columns as JSON
  /// strings ("42", "19.076"), and a hard `as num?` cast on those throws a
  /// TypeError that unwinds all the way out of [syncActiveSession]'s try —
  /// silently killing the whole sync, so the punch card showed "--:--" even
  /// though the punch existed in the response body.
  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? double.tryParse(v.toString())?.toInt();
  }

  /// Lenient double reader — same rationale as [_asInt].
  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  DateTime? _parseFlexibleTime(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString();
    if (s.isEmpty) return null;
    final dt = DateTime.tryParse(s);
    if (dt != null) return dt;
    // "HH:mm[:ss]" fallback — attach today's date.
    try {
      final parts = s.split(':');
      if (parts.length >= 2) {
        final now = DateTime.now();
        return DateTime(
          now.year,
          now.month,
          now.day,
          int.parse(parts[0]),
          int.parse(parts[1]),
        );
      }
    } catch (_) {}
    return null;
  }

  void clearSessionConflict() {
    _sessionConflict = null;
    notifyListeners();
  }

  // Fetch Today's Attendance from API
  Future<void> fetchTodayAttendance(String token, {String? date}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await ApiService.getTodayAttendance(token, date: date);

      if (response.isSuccess && response.data != null) {
        final data = response.data!;
        if (data['status'] == true && data['todayAttendance'] != null) {
          _todayAttendance = TodayAttendanceModel.fromJson(
            data['todayAttendance'] as Map<String, dynamic>,
          );
        } else {
          _todayAttendance = null;
        }
        // NOTE: _isClockedIn is owned by the session-based flow
        // (syncActiveSession / punchInWithLocation / punchOutWithLocation).
        // The legacy /today-employee-attendance endpoint does not know about
        // new sessions, so it must not touch this flag.
      } else {
        _errorMessage = response.error ?? 'Failed to load today attendance';
      }
    } catch (e) {
      _errorMessage = 'Error: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Fetch Attendance History
  Future<void> fetchHistory({String? startDate, String? endDate}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await ApiService.getAttendanceHistory(
        startDate: startDate,
        endDate: endDate,
      );

      if (response.isSuccess && response.data != null) {
        _history = ApiService.parseAttendanceFromResponse(response.data!);
      } else {
        _errorMessage = response.error ?? 'Failed to load history';
      }
    } catch (e) {
      _errorMessage = 'Error: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Fetch Team Attendance
  Future<void> fetchTeamAttendance({
    required String token,
    required String date,
    String? branchId,
    String? role,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await ApiService.getTeamAttendance(
        token: token,
        date: date,
        branchId: branchId,
        role: role,
      );

      if (response.isSuccess && response.data != null) {
        _teamAttendance = ApiService.parseDailyAttendanceFromResponse(
          response.data!,
        );
      } else {
        _errorMessage = response.error ?? 'Failed to load team attendance';
      }
    } catch (e) {
      _errorMessage = 'Error: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Clock In
  Future<bool> clockIn({required String time, required String location}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await ApiService.clockIn(time: time, location: location);

      if (response.isSuccess) {
        _isClockedIn = true;
        await fetchHistory(); // Refresh history
        return true;
      } else {
        _errorMessage = response.error ?? 'Clock-in failed';
        return false;
      }
    } catch (e) {
      _errorMessage = 'Error: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Clock Out
  Future<bool> clockOut({required String time}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await ApiService.clockOut(time: time);

      if (response.isSuccess) {
        _isClockedIn = false;
        await fetchHistory(); // Refresh history
        return true;
      } else {
        _errorMessage = response.error ?? 'Clock-out failed';
        return false;
      }
    } catch (e) {
      _errorMessage = 'Error: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Fetch Calendar Data for a specific month
  Future<void> fetchCalendarData({
    required String token,
    required String month,
    required String year,
  }) async {
    _isCalendarLoading = true;
    notifyListeners();

    try {
      final response = await ApiService.getCalendarData(
        token: token,
        month: month,
        year: year,
      );

      if (response.isSuccess && response.data != null) {
        final data = response.data!;
        if (data['success'] == true && data['attendanceData'] != null) {
          final Map<String, dynamic> rawAttendance = data['attendanceData'];
          _calendarData = rawAttendance.map((key, value) {
            return MapEntry(key, Map<String, dynamic>.from(value));
          });
        }
      } else {
        print('❌ Calendar data error: ${response.error}');
      }
    } catch (e) {
      print('❌ fetchCalendarData Exception: $e');
    } finally {
      _isCalendarLoading = false;
      notifyListeners();
    }
  }

  // Fetch My Attendance (filtered)
  Future<void> fetchMyAttendance({
    required String token,
    required String filter,
    String fromDate = '',
    String toDate = '',
  }) async {
    _isMyAttendanceLoading = true;
    notifyListeners();

    try {
      final response = await ApiService.getMyAttendance(
        token: token,
        filter: filter,
        fromDate: fromDate,
        toDate: toDate,
      );

      if (response.isSuccess && response.data != null) {
        final data = response.data!;
        if (data['success'] == true) {
          _myAttendanceSummary = Map<String, dynamic>.from(
            data['summary'] ?? {},
          );
          final List<dynamic> rawData = data['data'] ?? [];
          _myAttendanceData = rawData
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        }
      } else {
        print('❌ My Attendance error: ${response.error}');
      }
    } catch (e) {
      print('❌ fetchMyAttendance Exception: $e');
    } finally {
      _isMyAttendanceLoading = false;
      notifyListeners();
    }
  }

  // Check current clock status (if API provides it)
  void setClockStatus(bool status) {
    _isClockedIn = status;
    notifyListeners();
  }

  // Submit Attendance Regularization
  Future<bool> submitRegularization({
    required String token,
    required String dailyAttendanceId,
    required String newInTime,
    required String newOutTime,
    String reason = '',
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await ApiService.submitRegularization(
        token: token,
        dailyAttendanceId: dailyAttendanceId,
        newInTime: newInTime,
        newOutTime: newOutTime,
        reason: reason,
      );

      if (response.isSuccess) {
        await fetchMyAttendance(token: token, filter: 'last_7_days');
        return true;
      } else {
        _errorMessage = response.error ?? 'Regularization failed';
        return false;
      }
    } catch (e) {
      _errorMessage = 'Error: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ========== LOCATION TRACKING METHODS ==========

  // Start location tracking
  void startLocationTracking() {
    if (_isTrackingLocation) return;

    _isTrackingLocation = true;
    _trackingStartTime = DateTime.now();
    _trackedRoute.clear();
    _totalDistanceTracked = 0;

    // Start duration timer
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_trackingStartTime != null) {
        final duration = DateTime.now().difference(_trackingStartTime!);
        final hours = duration.inHours.toString().padLeft(2, '0');
        final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
        final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
        _trackingDuration = '$hours:$minutes:$seconds';
        notifyListeners();
      }
    });

    // Start location stream
    final locationService = LocationService();
    _locationSubscription = locationService.getLocationStream().listen(
      (Position position) {
        _updateLocation(position);
      },
      onError: (error) {
        print('Location tracking error: $error');
      },
    );

    // Get initial position
    locationService.getCurrentPosition().then((position) {
      if (position != null) {
        _updateLocation(position);
      }
    });

    notifyListeners();
  }

  // Update location
  void _updateLocation(Position position) {
    final locationService = LocationService();
    _currentPosition = {
      'latitude': position.latitude,
      'longitude': position.longitude,
    };

    _trackedRoute.add(_currentPosition!);

    // Calculate distance
    if (_trackedRoute.length > 1) {
      _totalDistanceTracked = locationService.calculateTotalDistance(
        _trackedRoute
            .map(
              (point) => LocationPoint(
                timestamp: DateTime.now(),
                latitude: point['latitude']!,
                longitude: point['longitude']!,
                accuracy: 0,
                id: '',
                userId: '',
                type: '',
                address: '',
              ),
            )
            .toList(),
      );
    }

    // Check geofence
    locationService.checkGeofenceStatus(position).then((status) {
      _geofenceStatus = status;
      notifyListeners();
    });

    notifyListeners();
  }

  // Stop location tracking
  void stopLocationTracking() {
    _isTrackingLocation = false;
    _locationSubscription?.cancel();
    _locationSubscription = null;
    _durationTimer?.cancel();
    _durationTimer = null;
    notifyListeners();
  }

  // Check geofence status (one-time)
  Future<void> checkGeofence() async {
    final locationService = LocationService();
    final position = await locationService.getCurrentPosition();

    if (position != null) {
      _currentPosition = {
        'latitude': position.latitude,
        'longitude': position.longitude,
      };
      _geofenceStatus = await locationService.checkGeofenceStatus(position);
      notifyListeners();
    }
  }

  // Capture selfie for punch
  Future<String?> capturePunchSelfie() async {
    final cameraService = CameraService();
    _pendingSelfiePath = await cameraService.captureSelfie();
    notifyListeners();
    return _pendingSelfiePath;
  }

  // Clear pending selfie
  void clearPendingSelfie() {
    _pendingSelfiePath = null;
    notifyListeners();
  }

  // ========== PUNCH WITH LOCATION (session-based) ==========

  /// Session-based punch-in. Uploads selfie + location to `/attendance/punch-in`,
  /// stores returned session_id locally, and starts background pings.
  ///
  /// Returns true on API success. Out-of-fence punches still return true —
  /// [lastPunchGeofence] carries the warning info for the UI to render.
  Future<bool> punchInWithLocation({
    required String time,
    required String location,
    required String userId,
    required String token,
  }) async {
    // Re-entrancy guard. Every call site shows a modal barrier before calling,
    // but the guard belongs here: a punch takes a GPS fix and a reverse
    // geocode before `_isLoading` is ever set, and the server's duplicate
    // protection is a 409 that costs a round trip and a scary error message.
    // See docs/geofence-module-guide.md §6.1 (concurrent punch-in race).
    if (_punchInFlight) return false;
    _punchInFlight = true;
    try {
      return await _punchInWithLocationImpl(
        time: time,
        location: location,
        userId: userId,
        token: token,
      );
    } finally {
      _punchInFlight = false;
    }
  }

  Future<bool> _punchInWithLocationImpl({
    required String time,
    required String location,
    required String userId,
    required String token,
  }) async {
    final locationService = LocationService();
    final geofenceRepo = GeofenceRepository();
    final queue = PingQueueService();

    // 1. GPS
    final position = await locationService.getCurrentPosition();
    if (position == null) {
      _errorMessage = 'Unable to get your location. Please enable GPS.';
      notifyListeners();
      return false;
    }

    // 2. Local geofence check (for local record + UI; server recomputes authoritatively)
    final localCheck = geofenceRepo.check(position.latitude, position.longitude);

    // 3. Reverse geocode
    final address = await locationService.getAddressFromCoordinates(
      position.latitude,
      position.longitude,
    );

    // 4. Build the record, but DO NOT persist it yet.
    //
    // This used to be written to disk before the upload, "so Punch View still
    // works even if upload fails". That made the card lie: a punch the server
    // rejected (409 on a stale session, 403, validation, no network) still
    // showed a punch-in time forever, replayed from disk on every cold start,
    // while the database had nothing. The server is the single source of
    // truth for attendance — a punch is only real once it has been accepted.
    final selfiePath = _pendingSelfiePath;
    final punchRecord = LocalPunchRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      type: PunchType.punchIn,
      latitude: position.latitude,
      longitude: position.longitude,
      address: address,
      selfieImagePath: selfiePath,
      isInsideOffice: localCheck.inside,
      distanceFromOffice: localCheck.distanceM,
    );
    _pendingSelfiePath = null;

    if (selfiePath == null) {
      _errorMessage = 'Selfie is required for punch-in.';
      notifyListeners();
      return false;
    }

    // 5. Upload
    _isLoading = true;
    _sessionConflict = null;
    notifyListeners();

    // Stamp which phone made this punch. `attendance_punches.device_info` has
    // existed since day one but nothing ever populated it — every punch stored
    // null. Best-effort: a metadata failure must not cost the punch.
    Map<String, dynamic>? deviceInfo;
    try {
      deviceInfo = await DeviceInfoHelper.getPunchDeviceInfo();
    } catch (_) {
      deviceInfo = null;
    }

    final response = await ApiService.punchIn(
      token: token,
      selfiePath: selfiePath,
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyM: position.accuracy,
      address: address,
      clientCapturedAt: DateTime.now(),
      deviceInfo: deviceInfo,
    );

    _isLoading = false;

    if (response.isConflict) {
      final raw = response.data ?? const <String, dynamic>{};
      // Server sends `code`; `error_code` is the older spelling. See
      // ApiResponse._readErrorCode.
      final errorCode = (raw['code'] ?? raw['error_code'])?.toString();
      final conflictPayload = _extractPayload(raw);

      if (errorCode == 'ALREADY_PUNCHED_TODAY') {
        // Backend says today's cycle is already complete. Hydrate the local
        // state so `todayCycleCompleted` flips to true and both punch
        // buttons stay hidden until the next calendar day.
        final startedAt = conflictPayload['started_at']?.toString();
        final endedAt = conflictPayload['ended_at']?.toString();
        if (startedAt != null) {
          _lastPunchIn = DateTime.tryParse(startedAt)?.toLocal();
        }
        // Prefer ended_at; fall back to now so the cycle-completed check
        // still fires even if the backend didn't include the field.
        _lastPunchOut = endedAt != null
            ? DateTime.tryParse(endedAt)?.toLocal() ?? DateTime.now()
            : DateTime.now();
        _activeSession = null;
        _isClockedIn = false;
        await AttendanceSession.clear();
        _errorMessage = response.error ??
            'You have already completed today\'s punch-in and punch-out.';
        notifyListeners();
        return false;
      }

      // Default 409 — SESSION_ALREADY_OPEN (existing behavior).
      // Default 409 — SESSION_ALREADY_OPEN.
      //
      // "Punch out first" is only actionable when the open session is
      // today's. A session left open on an earlier day is cleared locally by
      // the cross-day guard in syncActiveSession, so punch-out has nothing to
      // close — telling the user to punch out then deadlocks them: punch-in
      // 409s, punch-out reports "no active session". Work out which case this
      // is before writing the message.
      await _resolveOpenSessionConflict(
        token,
        _asInt(conflictPayload['session_id'] ?? raw['session_id']),
        raw,
      );
      return false;
    }

    if (!response.isSuccess) {
      // 403 GEOFENCE_NOT_ENABLED — the branch/employee isn't opted into
      // app-based punching. Mirror the flag locally so the punch button hides
      // straight away instead of letting the user retry into the same 403.
      if (response.errorCode == 'GEOFENCE_NOT_ENABLED') {
        _isGeofenceAttendanceEnabled = false;
        _errorMessage = response.error ??
            'Geofence attendance is not enabled for your account. '
                'Please contact admin.';
        notifyListeners();
        return false;
      }

      _errorMessage = response.error ?? 'Punch-in failed';
      notifyListeners();
      return false;
    }

    // 6. Parse session + geofence info from response
    final payload = _extractPayload(response.data);
    final sessionId = (payload['session_id'] as num?)?.toInt();
    final serverTime = payload['server_time']?.toString();
    final geofence = payload['geofence'] as Map<String, dynamic>?;

    if (sessionId == null) {
      _errorMessage = 'Server did not return a session id';
      notifyListeners();
      return false;
    }

    _activeSession = AttendanceSession(
      sessionId: sessionId,
      startedAt:
          serverTime != null ? DateTime.parse(serverTime).toLocal() : DateTime.now(),
    );
    await _activeSession!.save();
    // Arm the midnight rollover so this session auto-clears if the user leaves
    // the app open past 12 AM without punching out.
    _scheduleMidnightRollover();

    // Every successful punch-in → surface that time on the punch card
    // (overwrites any earlier punch-in time, per product requirement).
    _lastPunchIn = _activeSession!.startedAt;

    // NOW the punch is real — the server accepted it and gave us a session id.
    // Only at this point does it get cached locally, as a mirror of a row that
    // exists in the database (used for the Punch History thumbnail and as a
    // fallback while /attendance/today catches up). Never as a substitute for
    // a punch the server never recorded.
    _localPunchRecords.add(
      punchRecord.copyWith(
        sessionId: sessionId,
        // Prefer the server's timestamp so the card matches the database
        // rather than the device clock.
        timestamp: _activeSession!.startedAt,
      ),
    );
    unawaited(_savePunchRecords());

    _lastPunchGeofence = geofence == null
        ? null
        : {
            'inside': geofence['inside'] ?? true,
            'distanceM': (geofence['distance_m'] as num?)?.toDouble() ?? 0,
            'radiusM': (geofence['radius_m'] as num?)?.toInt(),
          };
    _isClockedIn = true;
    _errorMessage = null;

    // 7. Keep the local selfie on disk so the Punch History thumbnail still
    // renders after a kill+reopen (the saved LocalPunchRecord points at this
    // path). Stale selfies from previous days are wiped during the midnight
    // rollover / _loadPunchRecords cleanup pass — see _purgeStaleSelfies.

    // 8. Refresh and kick off background pings
    notifyListeners();
    fetchTodayAttendance(token);

    // Flush anything left in the offline queue, then start tracking.
    unawaited(queue.flush(token));
    BackgroundLocationService().startTracking(userId);

    return true;
  }

  /// Session-based punch-out. Closes the active session on the backend.
  Future<bool> punchOutWithLocation({
    required String time,
    required String token,
  }) async {
    // Same guard as punch-in — a double submit here would try to close an
    // already-closed session and surface a 409.
    if (_punchOutFlight) return false;
    _punchOutFlight = true;
    try {
      return await _punchOutWithLocationImpl(time: time, token: token);
    } finally {
      _punchOutFlight = false;
    }
  }

  Future<bool> _punchOutWithLocationImpl({
    required String time,
    required String token,
  }) async {
    final session = _activeSession;
    if (session == null) {
      _errorMessage = 'No active session to close.';
      notifyListeners();
      return false;
    }

    final locationService = LocationService();
    final geofenceRepo = GeofenceRepository();
    final queue = PingQueueService();

    final position = await locationService.getCurrentPosition();
    if (position == null) {
      _errorMessage = 'Unable to get your location. Please enable GPS.';
      notifyListeners();
      return false;
    }

    final localCheck = geofenceRepo.check(position.latitude, position.longitude);
    final address = await locationService.getAddressFromCoordinates(
      position.latitude,
      position.longitude,
    );

    final selfiePath = _pendingSelfiePath;
    final punchRecord = LocalPunchRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      type: PunchType.punchOut,
      latitude: position.latitude,
      longitude: position.longitude,
      address: address,
      selfieImagePath: selfiePath,
      isInsideOffice: localCheck.inside,
      distanceFromOffice: localCheck.distanceM,
      sessionId: session.sessionId,
    );
    // Not persisted yet — same rule as punch-in. A punch-out the server
    // rejects must not leave a punch-out time on the card while the session
    // is still open in the database.
    _pendingSelfiePath = null;

    if (selfiePath == null) {
      _errorMessage = 'Selfie is required for punch-out.';
      notifyListeners();
      return false;
    }

    // Flush any queued pings before closing the session, so the server sees the
    // full breadcrumb trail.
    await queue.flush(token);

    _isLoading = true;
    notifyListeners();

    Map<String, dynamic>? outDeviceInfo;
    try {
      outDeviceInfo = await DeviceInfoHelper.getPunchDeviceInfo();
    } catch (_) {
      outDeviceInfo = null;
    }

    final response = await ApiService.punchOut(
      token: token,
      sessionId: session.sessionId,
      selfiePath: selfiePath,
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyM: position.accuracy,
      address: address,
      clientCapturedAt: DateTime.now(),
      deviceInfo: outDeviceInfo,
    );

    _isLoading = false;

    if (!response.isSuccess) {
      _errorMessage = response.error ?? 'Punch-out failed';
      notifyListeners();
      return false;
    }

    // Server accepted — close the session locally too.
    BackgroundLocationService().stopTracking();
    await AttendanceSession.clear();
    _activeSession = null;
    _isClockedIn = false;
    _midnightRolloverTimer?.cancel();

    final payload = _extractPayload(response.data);

    // Record the punch-out time so the UI shows it without needing a refetch.
    // Prefer server_time → else the local capture time we just sent.
    final outServerTime = payload['server_time']?.toString();
    _lastPunchOut = outServerTime != null
        ? DateTime.parse(outServerTime).toLocal()
        : DateTime.now();

    // Accepted by the server — only now does it get cached locally, stamped
    // with the server's own time so the card matches the database row.
    _localPunchRecords.add(punchRecord.copyWith(timestamp: _lastPunchOut));
    unawaited(_savePunchRecords());

    // punch-out doesn't always include a geofence map, but capture it if present
    final geofence = payload['geofence'] as Map<String, dynamic>?;
    _lastPunchGeofence = geofence == null
        ? null
        : {
            'inside': geofence['inside'] ?? true,
            'distanceM': (geofence['distance_m'] as num?)?.toDouble() ?? 0,
            'radiusM': (geofence['radius_m'] as num?)?.toInt(),
          };

    // Keep the punch-out selfie on disk so Punch History still shows it after
    // a kill+reopen. Wiped during the next midnight rollover.

    _errorMessage = null;
    notifyListeners();
    fetchTodayAttendance(token);
    return true;
  }

  // Clear today's local punch records
  void clearLocalPunchRecords() {
    _purgeSelfies(_localPunchRecords);
    _localPunchRecords.clear();
    unawaited(_savePunchRecords());
    notifyListeners();
  }

  // ---------- Helpers ----------

  /// Works out what a 409 SESSION_ALREADY_OPEN actually means and writes a
  /// message the user can act on.
  ///
  /// The 409 body carries only `session_id`, not when that session started, so
  /// we ask `/attendance/today` for `active_session.started_at`. Two outcomes:
  ///
  ///  * **Started today** — recoverable. The device simply lost its local copy
  ///    (reinstall, cleared data, new phone). Adopt the session so punch-out
  ///    works again.
  ///  * **Started earlier / unknown** — an orphaned session the server never
  ///    closed. The user cannot fix this themselves: punch-in 409s forever and
  ///    punch-out has nothing local to close. Name the date and send them to
  ///    an administrator instead of repeating "punch out first", which is
  ///    impossible advice and is what left people stuck.
  Future<void> _resolveOpenSessionConflict(
    String token,
    int? sessionId,
    Map<String, dynamic> raw,
  ) async {
    _sessionConflict = raw;

    // The 409 body already carries the session's start time —
    // AttendancePunchController::punchIn() returns
    // `data: { session_id, started_at }`. Read it first and skip the extra
    // round trip; only fall back to /attendance/today when it's absent.
    DateTime? startedAt;
    final conflictPayload = _extractPayload(raw);
    final inlineStarted = conflictPayload['started_at']?.toString();
    if (inlineStarted != null) {
      startedAt = DateTime.tryParse(inlineStarted)?.toLocal();
    }

    if (startedAt != null) {
      _applyOpenSessionOutcome(sessionId, startedAt);
      return;
    }

    try {
      final today = await ApiService.getAttendanceToday(token);
      if (today.isSuccess && today.data != null) {
        final body = today.data!['data'] is Map<String, dynamic>
            ? today.data!['data'] as Map<String, dynamic>
            : today.data!;
        final active = body['active_session'];
        if (active is Map<String, dynamic>) {
          sessionId ??= _asInt(active['session_id']);
          final startedRaw =
              (active['started_at'] ?? active['opened_at'])?.toString();
          startedAt =
              startedRaw == null ? null : DateTime.tryParse(startedRaw)?.toLocal();
        }
      }
    } catch (e) {
      debugPrint('⚠️ Could not resolve open-session conflict: $e');
    }

    await _applyOpenSessionOutcome(sessionId, startedAt);
  }

  /// Writes the outcome of an open-session conflict: adopt it when it is
  /// today's, otherwise report it as an orphan only an admin can clear.
  Future<void> _applyOpenSessionOutcome(
    int? sessionId,
    DateTime? startedAt,
  ) async {
    final now = DateTime.now();
    final startedToday = startedAt != null &&
        startedAt.year == now.year &&
        startedAt.month == now.month &&
        startedAt.day == now.day;

    if (startedToday && sessionId != null) {
      _activeSession = AttendanceSession(
        sessionId: sessionId,
        startedAt: startedAt,
      );
      await _activeSession!.save();
      _isClockedIn = true;
      _lastPunchIn ??= startedAt;
      _scheduleMidnightRollover();
      _errorMessage = 'You are already punched in for today '
          '(since ${_fmtTimeOfDay(startedAt)}). Your session has been '
          'restored — punch out when you finish.';
      notifyListeners();
      return;
    }

    final where = startedAt != null
        ? 'from ${startedAt.day}/${startedAt.month}/${startedAt.year}'
        : 'from an earlier day';
    _errorMessage = 'You have an attendance session still open $where'
        '${sessionId != null ? ' (ID $sessionId)' : ''}. '
        'It must be closed by an administrator before you can punch in again.';
    notifyListeners();
  }

  Map<String, dynamic> _extractPayload(Map<String, dynamic>? raw) {
    if (raw == null) return const {};
    final nested = raw['data'];
    return nested is Map<String, dynamic> ? nested : raw;
  }

  void _safeDeleteSelfie(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.delete();
    } catch (_) {
      // Non-fatal — device will garbage-collect at reboot worst case.
    }
  }

  /// Walks a list of punch records and deletes each one's selfie from the
  /// app's documents directory. Only acts on local file paths — remote URLs
  /// (backend-sourced) are skipped. Used by midnight rollover, manual clear,
  /// and the cold-start "drop stale records" pass.
  void _purgeSelfies(Iterable<LocalPunchRecord> stale) {
    for (final r in stale) {
      final p = r.selfieImagePath;
      if (p == null || p.isEmpty) continue;
      if (p.startsWith('http://') || p.startsWith('https://')) continue;
      _safeDeleteSelfie(p);
    }
  }

  @override
  void dispose() {
    _midnightRolloverTimer?.cancel();
    _locationSubscription?.cancel();
    _durationTimer?.cancel();
    super.dispose();
  }
}
