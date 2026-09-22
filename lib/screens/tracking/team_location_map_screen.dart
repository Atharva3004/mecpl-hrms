import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../models/branch_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';

/// Team Location — where the whole team is, for a chosen date.
///
/// Reached from the "Team Location" tile on the dashboard, by a director
/// (own menu) or an admin (Teams grid) — the same two roles the API admits.
/// Every branch is shown at once: the bar over the map carries only the
/// employee search and the date, and the draggable sheet carries the one
/// status filter — Active / Completed / Away from site. Tapping a row swaps
/// the team view for that person's route trail.
///
/// DATA: `GET /api/attendance/geofence-live` for the day's roster, fences and
/// counts, and `GET /api/attendance/geofence-timeline` for one session's
/// trail. Contract: docs/geofence-live-dashboard-api.md. Flip [_useMockData]
/// to run the whole screen on [_MockGeofenceApi], which emits the same JSON.
class TeamLocationMapScreen extends StatefulWidget {
  const TeamLocationMapScreen({super.key});

  @override
  State<TeamLocationMapScreen> createState() => _TeamLocationMapScreenState();
}

/// The one question this screen answers: *which* people am I looking at?
///
/// There used to be two overlapping controls for this — four KPI tiles over
/// the map and a segmented tab bar in the sheet — which could disagree and
/// left the reader guessing which one was in charge. One enum, one row of
/// chips, one answer.
enum _View { active, completed, away }

class _TeamLocationMapScreenState extends State<TeamLocationMapScreen>
    with WidgetsBindingObserver {
  static const Duration _pollInterval = Duration(seconds: 45);

  /// Flip to true to run the screen on [_MockGeofenceApi] again — useful for
  /// a demo, or while the live endpoint is down. Deliberately not `const`:
  /// the analyzer then keeps type-checking both branches instead of treating
  /// the unused one as dead code.
  static final bool _useMockData = false;

  // Only shown for the instant before the first load frames the real markers,
  // and when nobody is punched in. Employees span branches, so there is no
  // single "our office" centre worth hardcoding here.
  static const CameraPosition _fallbackCamera = CameraPosition(
    target: LatLng(20.5937, 78.9629),
    zoom: 4,
  );

  GoogleMapController? _mapController;
  Timer? _pollTimer;

  final TextEditingController _searchController = TextEditingController();

  // ─── Filters ──────────────────────────────────────────────────────────
  List<BranchModel> _branches = const [];
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  String _query = '';
  _View _view = _View.active;

  // ─── Roster sheet ─────────────────────────────────────────────────────
  // The sheet collapses to a summary bar so the map can take the whole
  // screen. Which layout the sheet draws is decided from its real height by
  // the LayoutBuilder in [_buildSheet] — never from a flag, which can
  // disagree with the box mid-animation.
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  /// Only feeds the map's bottom padding, so Google's controls sit above the
  /// sheet. Written solely by [_onSheetDragged], from the size the sheet
  /// actually reached.
  bool _sheetCollapsed = false;
  double _collapsedFraction = 0.14;
  // Tall enough that the chips and three rows are visible without a drag —
  // the old 0.34 left barely two rows under the header.
  static const double _expandedFraction = 0.42;

  /// Below this the header line and the chips cannot both fit, so the sheet
  /// draws its one-line summary instead. Measured against the real box, not
  /// guessed from a state flag.
  static const double _minExpandedHeight = 152;

  /// While searching the chips are hidden, so the header alone needs much
  /// less room. Without this the sheet would fall back to its summary bar
  /// exactly when the keyboard is up — that is, exactly when you are typing
  /// and want to see the matches.
  static const double _minExpandedHeightSearching = 104;

  // ─── Data ─────────────────────────────────────────────────────────────
  List<_LiveEmployee> _all = const [];
  bool _loading = true;
  String? _error;

  /// Whether the failure in [_error] is worth another attempt. A dead network
  /// is; asking a live-only endpoint for last Tuesday is not.
  bool _canRetry = true;
  DateTime? _lastUpdated;
  String? _selectedKey;

  /// The first successful load frames every marker; later polls must not yank
  /// the camera away from wherever the director has panned to.
  bool _hasFramedMarkers = false;

  // ─── Route trail ──────────────────────────────────────────────────────
  // Tapping someone switches the map from "where is everyone" to "where did
  // this one person go". Only their pins stay on screen — a trail drawn
  // through fifteen other people's markers is unreadable.
  _LiveEmployee? _routeFor;
  List<_RoutePoint> _routePoints = const [];
  bool _routeLoading = false;
  String? _routeError;

  bool get _isToday => DateUtils.isSameDay(_date, DateTime.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sheetController.addListener(_onSheetDragged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
      _startPolling();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _searchController.dispose();
    _sheetController.removeListener(_onSheetDragged);
    _sheetController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  // Polling in the background is how you collect aborted sockets: Android
  // tears the connection down on doze or a radio handover and the request dies
  // mid-flight. Stop while hidden, and catch up on the way back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
      _refresh(silent: true);
    } else {
      _stopPolling();
    }
  }

  void _startPolling() {
    _stopPolling();
    // Only "today" is live data — a past date is settled history and polling
    // it just burns battery for an identical payload.
    if (!_isToday) return;
    _pollTimer = Timer.periodic(_pollInterval, (_) => _refresh(silent: true));
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Guarded because the poll timer and the lifecycle observer both reach
  /// for this, and `context.read` on a disposed State throws.
  String? get _token => mounted ? context.read<AuthProvider>().token : null;

  /// The single seam between this screen and the backend.
  ///
  /// `GET /api/attendance/geofence-live` (admin/director) returns one day's
  /// sessions, the fences to draw and the server's own counts in a single
  /// call — contract in docs/geofence-live-dashboard-api.md §1.
  ///
  /// No `branch_id` is sent: a director watches every site at once, and the
  /// employee search covers the rare "just this one" question.
  ///
  /// Returns the inner `data` object, so the caller reads `employees` and
  /// `branches` off it directly.
  Future<Map<String, dynamic>> _loadSnapshot() async {
    if (_useMockData) return _MockGeofenceApi.fetch(date: _date);

    final token = _token;
    if (token == null || token.isEmpty) {
      throw const _LiveUnavailable('Your session has expired. Sign in again.');
    }

    final res = await ApiService.getGeofenceLive(token: token, date: _date);
    if (!res.isSuccess) {
      // A role problem and a bad date are both permanent for this request —
      // retrying either just re-fails, so do not offer a button that cannot
      // work. Everything else (timeout, socket, 5xx) is worth another go.
      const permanent = {'FORBIDDEN', 'INVALID_DATE'};
      throw _LiveUnavailable(
        res.error ?? 'Could not load the team map.',
        canRetry: !permanent.contains(res.errorCode),
      );
    }

    final data = res.data?['data'];
    if (data is! Map<String, dynamic>) {
      throw const _LiveUnavailable('The server sent an unexpected response.');
    }
    return data;
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _canRetry = true;
      });
    }

    try {
      final payload = await _loadSnapshot();
      if (!mounted) return;

      final rows = payload['employees'];
      final parsed = <_LiveEmployee>[];
      if (rows is List) {
        for (final row in rows.whereType<Map<String, dynamic>>()) {
          parsed.add(_LiveEmployee.fromJson(row, parsed.length));
        }
      }

      // The fences ride along with the roster, so they can never describe a
      // different branch set than the pins do.
      final fences = payload['branches'];
      final branches = <BranchModel>[];
      if (fences is List) {
        for (final b in fences.whereType<Map<String, dynamic>>()) {
          branches.add(BranchModel.fromJson(b));
        }
      }

      setState(() {
        _all = parsed;
        if (branches.isNotEmpty) _branches = branches;
        _loading = false;
        _error = null;
        _lastUpdated = DateTime.now();
        // A marker that vanished between polls must not keep the sheet
        // highlighted on a row that is no longer there.
        if (_selectedKey != null && !parsed.any((e) => e.key == _selectedKey)) {
          _selectedKey = null;
        }

        // Re-resolve the route's subject against the new roster, so the bar
        // keeps reporting a live "seen 2 min ago" instead of freezing at
        // whatever it said when the row was tapped. If the session is gone,
        // so is the trail.
        final subject = _routeFor;
        if (subject != null) {
          final updated = parsed.where((e) => e.key == subject.key).firstOrNull;
          if (updated == null) {
            _routeFor = null;
            _routePoints = const [];
            _routeError = null;
            _routeLoading = false;
          } else {
            _routeFor = updated;
          }
        }
      });

      if (!_hasFramedMarkers && _mapped.isNotEmpty) {
        _hasFramedMarkers = true;
        _frameAllMarkers();
      }
    } on _LiveUnavailable catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
        _canRetry = e.canRetry;
        // This one is not a hiccup — the data genuinely is not there, so
        // leaving yesterday's markers up would be a lie.
        if (!e.canRetry) _all = const [];
      });
    } catch (e) {
      if (!mounted) return;
      // A failed poll must not wipe a map that is already useful — keep the
      // last good markers and flag them as stale instead.
      setState(() {
        _loading = false;
        _error = 'Could not load live attendance.';
        _canRetry = true;
      });
    }
  }

  /// Keeps the chevron honest when the sheet is dragged rather than tapped.
  /// Only fires a rebuild on the crossing, not on every drag frame.
  void _onSheetDragged() {
    if (!_sheetController.isAttached) return;
    final collapsed = _sheetController.size <= _collapsedFraction + 0.03;
    if (collapsed != _sheetCollapsed && mounted) {
      setState(() => _sheetCollapsed = collapsed);
    }
  }

  /// Reads the sheet's actual size rather than a remembered flag, and does
  /// not touch [_sheetCollapsed] — the controller listener owns that, once
  /// the sheet has really moved. Setting it here used to render the tall
  /// layout inside the short box for the length of the animation, which is
  /// what painted the yellow overflow stripes across the sheet.
  void _toggleSheet() {
    if (!_sheetController.isAttached) return;
    final expanded = _sheetController.size > _collapsedFraction + 0.03;
    _sheetController.animateTo(
      expanded ? _collapsedFraction : _expandedFraction,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  // ─── Derived sets ─────────────────────────────────────────────────────

  /// Everything matching branch + search, before the status filters. This is
  /// what the KPI tiles count, so their numbers always describe the same
  /// population the list is drawn from.
  bool get _searching => _query.trim().isNotEmpty;

  List<_LiveEmployee> get _scoped {
    final terms = _query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) return _all;

    // Every word has to land somewhere in the row, in any order — so
    // "shetty abhi", "abhilash 1104" and "priya balewadi" all find their
    // person. Matching the whole query as one string, the way this used to,
    // meant a typed space could only ever fail.
    return _all.where((e) {
      final haystack =
          '${e.name} ${e.empCode} ${e.department} '
                  '${e.branchName}'
              .toLowerCase();
      return terms.every(haystack.contains);
    }).toList();
  }

  /// A search looks across every status. Hiding a match because the wrong
  /// chip happens to be selected is indistinguishable, from the outside,
  /// from a search that does not work.
  List<_LiveEmployee> get _visible =>
      _searching ? _scoped : _scoped.where(_matchesView).toList();

  bool _matchesView(_LiveEmployee e) {
    switch (_view) {
      case _View.active:
        return e.isActive;
      case _View.completed:
        return !e.isActive;
      case _View.away:
        return e.isAway;
    }
  }

  /// Only rows with a ping can be drawn. Everyone else is counted separately
  /// so the map never silently under-reports the roster.
  List<_LiveEmployee> get _mapped =>
      _visible.where((e) => e.hasLocation).toList();

  int get _withoutLocation => _visible.length - _mapped.length;

  // ─── Map plumbing ─────────────────────────────────────────────────────

  Set<Marker> get _markers {
    final subject = _routeFor;
    if (subject != null) {
      final start = _routePoints.where((p) => p.isPunchIn).firstOrNull;
      final end = _routePoints.where((p) => p.isPunchOut).firstOrNull;
      final fmt = DateFormat('h:mm a');
      return {
        if (subject.hasLocation)
          Marker(
            markerId: MarkerId(subject.key),
            position: LatLng(subject.latitude!, subject.longitude!),
            icon: BitmapDescriptor.defaultMarkerWithHue(subject.markerHue),
            infoWindow: InfoWindow(
              title: subject.displayName,
              snippet: subject.statusLine,
            ),
          ),
        if (start != null)
          Marker(
            markerId: const MarkerId('route_start'),
            position: start.position,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
            infoWindow: InfoWindow(
              title: 'Punched in',
              snippet: start.at == null ? null : fmt.format(start.at!),
            ),
          ),
        if (end != null)
          Marker(
            markerId: const MarkerId('route_end'),
            position: end.position,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
            infoWindow: InfoWindow(
              title: 'Punched out',
              snippet: end.at == null ? null : fmt.format(end.at!),
            ),
          ),
      };
    }

    return {
      for (final e in _mapped)
        Marker(
          markerId: MarkerId(e.key),
          position: LatLng(e.latitude!, e.longitude!),
          icon: BitmapDescriptor.defaultMarkerWithHue(e.markerHue),
          infoWindow: InfoWindow(
            title: e.displayName,
            snippet: '${e.branchName} · ${e.statusLine}',
          ),
          onTap: () => setState(() => _selectedKey = e.key),
        ),
    };
  }

  Set<Polyline> get _polylines {
    if (_routePoints.length < 2) return const {};
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: [for (final p in _routePoints) p.position],
        color: AppColors.primary,
        width: 4,
      ),
    };
  }

  /// The fence itself, so an "outside" pin reads as a fact rather than a
  /// claim — you can see how far out the person actually is.
  Set<Circle> get _circles {
    return {
      for (final b in _branches)
        if (b.latitude != null && b.longitude != null)
          Circle(
            circleId: CircleId('fence_${b.id}'),
            center: LatLng(b.latitude!, b.longitude!),
            radius: (b.geofenceRadiusM ?? 150).toDouble(),
            fillColor: AppColors.primary.withOpacity(0.08),
            strokeColor: AppColors.primary.withOpacity(0.45),
            strokeWidth: 2,
          ),
    };
  }

  Future<void> _frameAllMarkers() async {
    final controller = _mapController;
    final pins = _mapped;
    if (controller == null || pins.isEmpty) return;

    // A one-marker bounds box is degenerate on Android — zoom to the point
    // instead of asking the SDK to fit a zero-area rectangle.
    if (pins.length == 1) {
      final only = pins.first;
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(only.latitude!, only.longitude!), 16),
      );
      return;
    }

    final lats = pins.map((e) => e.latitude!);
    final lngs = pins.map((e) => e.longitude!);
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(lats.reduce(min), lngs.reduce(min)),
          northeast: LatLng(lats.reduce(max), lngs.reduce(max)),
        ),
        64,
      ),
    );
  }

  /// Tapping a row shows that person's day: their pin, their trail, and
  /// nothing else. Tapping the same row again goes back to the whole team.
  Future<void> _showRoute(_LiveEmployee employee) async {
    if (_routeFor?.key == employee.key) {
      _clearRoute();
      return;
    }

    _collapseSheet();
    setState(() {
      _selectedKey = employee.key;
      _routeFor = employee;
      _routePoints = const [];
      _routeError = null;
      _routeLoading = employee.sessionId != null;
    });

    if (employee.sessionId == null) {
      setState(() => _routeError = 'No route for this session.');
      await _focusOn(employee);
      return;
    }

    List<_RoutePoint> points = const [];
    String? error;
    try {
      points = _useMockData
          ? await _MockGeofenceApi.route(employee)
          : await _fetchRoute(employee.sessionId!);
    } on _LiveUnavailable catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not load the route.';
    }

    if (!mounted || _routeFor?.key != employee.key) return;
    setState(() {
      _routePoints = points;
      _routeLoading = false;
      _routeError = error ?? (points.isEmpty ? 'No route recorded.' : null);
    });

    if (points.length >= 2) {
      await _frameRoute(points);
    } else {
      await _focusOn(employee);
    }
  }

  Future<List<_RoutePoint>> _fetchRoute(int sessionId) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw const _LiveUnavailable('Your session has expired. Sign in again.');
    }
    final res = await ApiService.getGeofenceRoute(
      token: token,
      sessionId: sessionId,
    );
    if (!res.isSuccess) {
      throw _LiveUnavailable(res.error ?? 'Could not load the route.');
    }
    final raw = (res.data?['data'] as Map?)?['points'];
    if (raw is! List) return const [];
    return [
      for (final p in raw.whereType<Map<String, dynamic>>())
        ?_RoutePoint.fromJson(p),
    ];
  }

  /// [reframe] is false when the caller is about to move the camera itself,
  /// so the map does not animate out to the whole team and straight back in
  /// to one person.
  void _clearRoute({bool reframe = true}) {
    setState(() {
      _routeFor = null;
      _routePoints = const [];
      _routeError = null;
      _routeLoading = false;
      _selectedKey = null;
    });
    if (reframe) _frameAllMarkers();
  }

  /// Both row actions need the sheet out of the way — there is no point
  /// centring the map under a panel that covers it.
  void _collapseSheet() {
    if (!_sheetController.isAttached) return;
    if (_sheetController.size <= _collapsedFraction + 0.03) return;
    _sheetController.animateTo(
      _collapsedFraction,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  /// "Locate": where this person is right now. Any trail on screen belongs
  /// to someone else's question, so it comes down first — otherwise the
  /// camera flies to a marker the route view is not drawing.
  Future<void> _locateOn(_LiveEmployee employee) async {
    if (_routeFor != null) _clearRoute(reframe: false);
    _collapseSheet();
    await _focusOn(employee);
  }

  Future<void> _frameRoute(List<_RoutePoint> points) async {
    final lats = points.map((p) => p.latitude);
    final lngs = points.map((p) => p.longitude);
    await _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(lats.reduce(min), lngs.reduce(min)),
          northeast: LatLng(lats.reduce(max), lngs.reduce(max)),
        ),
        72,
      ),
    );
  }

  Future<void> _focusOn(_LiveEmployee employee) async {
    setState(() => _selectedKey = employee.key);
    if (!employee.hasLocation) return;
    await _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(employee.latitude!, employee.longitude!),
        17,
      ),
    );
    await _mapController?.showMarkerInfoWindow(MarkerId(employee.key));
  }

  // ─── Filter actions ───────────────────────────────────────────────────

  void _onFilterChanged() {
    // A new branch or date is a different population entirely — let the next
    // load re-frame the camera around it.
    _hasFramedMarkers = false;
    _refresh();
    _startPolling();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(DateTime.now().year - 2),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = DateUtils.dateOnly(picked));
    _onFilterChanged();
  }

  // ─── UI ───────────────────────────────────────────────────────────────
  //
  // Layout, top to bottom: a bar for *which person* and *which day*, the map,
  // and a sheet for *what state*. Each question is asked in exactly one place.

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Team Location',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 1),
            Row(
              children: [
                if (_isToday) ...[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  _isToday
                      ? 'Live now'
                      : DateFormat('EEE, d MMM yyyy').format(_date),
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: _isToday
                        ? AppColors.success
                        : (isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
        ),
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            // Whatever the map is currently showing is what this frames —
            // framing the whole team while only one trail is drawn would
            // zoom to pins that are not there.
            tooltip: _routeFor == null ? 'Show everyone' : 'Fit this route',
            icon: const Icon(Iconsax.maximize_4, size: 19),
            onPressed: _routeFor != null
                ? (_routePoints.length < 2
                      ? null
                      : () => _frameRoute(_routePoints))
                : (_mapped.isEmpty ? null : _frameAllMarkers),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Iconsax.refresh, size: 19),
            onPressed: _loading ? null : () => _refresh(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _fallbackCamera,
            markers: _markers,
            polylines: _polylines,
            circles: _circles,
            onMapCreated: (controller) {
              _mapController = controller;
              if (!_hasFramedMarkers && _mapped.isNotEmpty) {
                _hasFramedMarkers = true;
                _frameAllMarkers();
              }
            },
            onTap: (_) {
              if (_routeFor != null) {
                _clearRoute();
              } else {
                setState(() => _selectedKey = null);
              }
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            padding: EdgeInsets.only(
              // Enough to clear whatever the overlay currently is - scope
              // bar, route card, retry strip - so Google's own controls
              // never hide under it.
              top: _topOverlayHeight,
              bottom:
                  MediaQuery.of(context).size.height *
                  (_sheetCollapsed ? _collapsedFraction : _expandedFraction),
            ),
          ),
          Positioned(
            top: 12,
            left: 14,
            right: 14,
            child: Column(
              children: [
                // While a trail is up, the bar names whose day you are
                // looking at. Search and date belong to the team view and
                // would only invite a tap that silently drops the route.
                _routeFor == null
                    ? _buildScopeBar(isDark)
                    : _buildRouteBar(isDark),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  _buildErrorBar(),
                ],
              ],
            ),
          ),
          if (_loading && _all.isEmpty)
            const Center(child: CircularProgressIndicator()),
          _buildSheet(isDark),
        ],
      ),
    );
  }

  // ─── Scope bar: which person, which day ───────────────────────────────
  // Search, then the date. The date reads as a value rather than a control
  // label, so the bar states the day it is showing even when nobody is going
  // to tap it.

  Widget _buildScopeBar(bool isDark) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : const Color(0xFFEEF0F6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.4 : 0.10),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: _buildSearchField(isDark)),
          Container(
            width: 1,
            height: 22,
            color: isDark ? AppColors.darkBorder : AppColors.border,
          ),
          Expanded(
            flex: 2,
            child: _scopePill(
              isDark: isDark,
              icon: Iconsax.calendar_1,
              label: _isToday ? 'Today' : DateFormat('d MMM').format(_date),
              onTap: _pickDate,
            ),
          ),
        ],
      ),
    );
  }

  /// Height of the floating stack above the map: the bar, plus the selfie
  /// strip when a route with photos is up, plus the retry line when it is
  /// showing, plus the margins around them.
  double get _topOverlayHeight {
    var height = 46.0;
    if (_routeFor?.hasSelfies == true) height += 70;
    if (_error != null) height += 44;
    return height + 22;
  }

  Widget _buildRouteBar(bool isDark) {
    final subject = _routeFor!;
    final String detail;
    if (_routeLoading) {
      detail = 'Loading route…';
    } else if (_routeError != null) {
      detail = _routeError!;
    } else {
      final stops = _routePoints.length;
      final battery = subject.batteryPct == null
          ? ''
          : ' · ${subject.batteryPct}% battery';
      detail =
          '$stops ${stops == 1 ? 'point' : 'points'} · '
          '${subject.statusLine}$battery';
    }

    final bar = Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.45)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.4 : 0.10),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: _routeLoading
                ? const CircularProgressIndicator(strokeWidth: 2)
                : const Icon(
                    Iconsax.routing,
                    size: 15,
                    color: AppColors.primary,
                  ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subject.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.textPrimary,
                  ),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500,
                    color: _routeError != null
                        ? AppColors.warning
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _clearRoute,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                'Back to team',
                style: GoogleFonts.poppins(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (!subject.hasSelfies) return bar;

    // The proof at each end of the trail: who actually stood there when the
    // day started, and when it finished.
    return Column(
      children: [
        bar,
        const SizedBox(height: 8),
        Container(
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : const Color(0xFFEEF0F6),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.4 : 0.10),
                blurRadius: 16,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              if (subject.punchInSelfie != null)
                _buildSelfieChip(
                  isDark: isDark,
                  url: subject.punchInSelfie!,
                  label: 'Punched in',
                  at: subject.startedAt,
                  color: AppColors.success,
                ),
              if (subject.punchOutSelfie != null)
                _buildSelfieChip(
                  isDark: isDark,
                  url: subject.punchOutSelfie!,
                  label: subject.isForceClosed ? 'Auto-closed' : 'Punched out',
                  at: subject.endedAt,
                  color: AppColors.error,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSelfieChip({
    required bool isDark,
    required String url,
    required String label,
    required DateTime? at,
    required Color color,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openSelfie(url, label),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withOpacity(0.6), width: 1.5),
              ),
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, _) =>
                    const ColoredBox(color: Color(0x11000000)),
                errorWidget: (_, _, _) => const Icon(
                  Iconsax.gallery_slash,
                  size: 16,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  Text(
                    at == null ? '-' : DateFormat('h:mm a').format(at),
                    maxLines: 1,
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Full-screen and pinch-zoomable. A 44px thumbnail is enough to know a
  /// photo exists and nowhere near enough to recognise a face.
  void _openSelfie(String url, String label) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Iconsax.close_circle, color: Colors.white),
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: InteractiveViewer(
                  maxScale: 4,
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.contain,
                    placeholder: (_, _) => const SizedBox(
                      height: 200,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (_, _, _) => SizedBox(
                      height: 200,
                      child: Center(
                        child: Text(
                          'Could not load the photo.',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scopePill({
    required bool isDark,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13),
        child: Row(
          children: [
            Icon(icon, size: 14, color: AppColors.primary),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.textPrimary,
                ),
              ),
            ),
            Icon(
              Iconsax.arrow_down_1,
              size: 14,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBar() {
    return Material(
      color: AppColors.warning.withOpacity(0.96),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _canRetry ? () => _refresh() : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          child: Row(
            children: [
              const Icon(Iconsax.warning_2, size: 16, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _error ?? 'Could not update.',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
              if (_canRetry)
                Text(
                  'Retry',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Sheet: who ───────────────────────────────────────────────────────

  Widget _buildSheet(bool isDark) {
    final scoped = _scoped;
    final active = scoped.where((e) => e.isActive).length;
    final completed = scoped.length - active;
    final away = scoped.where((e) => e.isAway).length;
    final rows = _visible;

    // Collapsed height is a pixel target, not a fixed fraction — 14% of a
    // tall phone is a comfortable bar, but 14% of a short one clips the
    // chevron. So it has to be resolved against a real height.
    //
    // That height is the sheet's *parent*, which is what
    // DraggableScrollableSheet multiplies its fractions by — not the screen.
    // The two differ whenever the keyboard is up: the Scaffold shrinks the
    // body, the screen stays the same size, and a fraction derived from the
    // screen then resolves to far fewer pixels than intended. That is what
    // overflowed the collapsed bar by 20px the moment search was tapped.
    // Positioned.fill rather than a bare LayoutBuilder: as a plain Stack
    // child it would be measured with loose constraints, and `maxHeight`
    // there is the stack's limit rather than the height the sheet will
    // actually be laid out in. Filling makes the two the same number.
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, box) {
          final bottomInset = MediaQuery.of(context).padding.bottom;

          // 64px is the grab handle plus the summary row; anything less and
          // the bar clips. The system inset is added only when the Scaffold
          // has not already eaten it, so this holds with or without a nav bar.
          //
          // Capped below the expanded size as well: on a short box the target
          // can exceed it, and snapSizes that are not ascending assert.
          _collapsedFraction = ((64 + bottomInset) / box.maxHeight).clamp(
            0.09,
            _expandedFraction - 0.04,
          );

          return _buildSheetBody(isDark, scoped, rows, active, completed, away);
        },
      ),
    );
  }

  Widget _buildSheetBody(
    bool isDark,
    List<_LiveEmployee> scoped,
    List<_LiveEmployee> rows,
    int active,
    int completed,
    int away,
  ) {
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: _expandedFraction,
      minChildSize: _collapsedFraction,
      maxChildSize: 0.85,
      snap: true,
      snapSizes: [_collapsedFraction, _expandedFraction],
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          // The one source of truth for which layout fits: the height the
          // sheet has *right now*, mid-animation included. A flag can
          // disagree with the box; constraints cannot.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxHeight <
                  (_searching
                      ? _minExpandedHeightSearching
                      : _minExpandedHeight);
              return Column(
                children: [
                  const SizedBox(height: 7),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkBorder
                          : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: compact
                              ? _buildCollapsedSummary(
                                  isDark,
                                  active,
                                  completed,
                                )
                              : _buildHeaderLine(isDark, scoped.length),
                        ),
                        const SizedBox(width: 8),
                        _buildSheetChevron(isDark, compact),
                      ],
                    ),
                  ),
                  // The chips are the only thing the arrow hides — and they
                  // mean nothing while a search is spanning every status.
                  if (!compact && !_searching)
                    _buildViewChips(isDark, active, completed, away),
                  // The list stays in the tree at every size, and
                  // [Expanded] lets it shrink to the few pixels the collapsed
                  // bar leaves over.
                  //
                  // It must not be dropped when collapsed: `scrollController`
                  // is what DraggableScrollableSheet drives its own height
                  // from, so taking its scrollable out of the tree left the
                  // controller with nothing to move. The sheet then froze at
                  // whatever height it had — collapsed header, expanded box,
                  // a blank white block in between — and neither the arrow
                  // nor "See list" could undo it.
                  Expanded(
                    child: ClipRect(
                      child: rows.isEmpty
                          ? _buildEmptyList(scrollController, isDark)
                          : ListView.separated(
                              controller: scrollController,
                              padding: const EdgeInsets.only(bottom: 28),
                              itemCount: rows.length,
                              separatorBuilder: (_, _) => Divider(
                                height: 1,
                                indent: 68,
                                color: isDark
                                    ? AppColors.darkBorder
                                    : Colors.grey.shade200,
                              ),
                              itemBuilder: (_, i) =>
                                  _buildEmployeeTile(rows[i], isDark),
                            ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// One plain sentence about what the list is showing, plus the search
  /// toggle. No jargon, no second copy of the counts — the chips below own
  /// the numbers.
  Widget _buildHeaderLine(bool isDark, int total) {
    final updated = _lastUpdated == null
        ? null
        : DateFormat('h:mm a').format(_lastUpdated!);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _searching
                    ? '$total ${total == 1 ? 'match' : 'matches'}'
                    : '$total ${total == 1 ? 'person' : 'people'} ${_isToday ? 'today' : 'on this day'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.textPrimary,
                ),
              ),
              if (updated != null)
                Text(
                  _withoutLocation > 0
                      ? 'Updated $updated · $_withoutLocation not on the map'
                      : 'Updated $updated',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500,
                    color: _withoutLocation > 0
                        ? AppColors.warning
                        : AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// The whole filter, in one row. Each chip says what it means in words and
  /// carries its own count, so tapping one can never disagree with a number
  /// somewhere else on the screen.
  Widget _buildViewChips(bool isDark, int active, int completed, int away) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        children: [
          _viewChip(
            isDark: isDark,
            view: _View.active,
            label: 'Active',
            count: active,
            color: AppColors.success,
          ),
          const SizedBox(width: 8),
          _viewChip(
            isDark: isDark,
            view: _View.completed,
            label: 'Completed',
            count: completed,
            color: AppColors.info,
          ),
          const SizedBox(width: 8),
          _viewChip(
            isDark: isDark,
            view: _View.away,
            label: 'Away from site',
            count: away,
            color: AppColors.warning,
          ),
        ],
      ),
    );
  }

  Widget _viewChip({
    required bool isDark,
    required _View view,
    required String label,
    required int count,
    required Color color,
  }) {
    final selected = _view == view;
    return GestureDetector(
      onTap: () => setState(() => _view = view),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? color.withOpacity(isDark ? 0.24 : 0.12)
              : (isDark
                    ? AppColors.darkSurfaceVariant
                    : AppColors.surfaceVariant),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 1.4,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: selected ? color : color.withOpacity(0.45),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? (isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.textPrimary)
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '$count',
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sits in the scope bar over the map, which draws the shell around it —
  /// hence no decoration of its own. Always visible: finding one person is
  /// the second thing anyone does here, after looking at the map.
  Widget _buildSearchField(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13),
      child: Row(
        children: [
          Icon(
            Iconsax.search_normal_1,
            size: 14,
            color: _query.isEmpty ? AppColors.textSecondary : AppColors.primary,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'Search employee',
                hintStyle: GoogleFonts.poppins(
                  fontSize: 11.5,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ),
          if (_query.isNotEmpty)
            InkWell(
              onTap: () {
                _searchController.clear();
                setState(() => _query = '');
              },
              child: const Icon(
                Iconsax.close_circle,
                size: 17,
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }

  /// The arrow that shrinks the roster away. Points down when there is
  /// something to hide, up when there is something to bring back.
  Widget _buildSheetChevron(bool isDark, bool compact) {
    return Material(
      color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _toggleSheet,
        child: SizedBox(
          width: 32,
          height: 32,
          child: AnimatedRotation(
            turns: compact ? 0.5 : 0,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            child: Icon(
              Iconsax.arrow_down_1,
              size: 14,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  /// What the list shrinks into: the two numbers that matter, one line tall.
  /// The whole bar is the tap target, not just the 36px chevron.
  Widget _buildCollapsedSummary(bool isDark, int active, int completed) {
    Widget count(String label, int value, Color color) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            '$value',
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleSheet,
      child: SizedBox(
        height: 32,
        child: Row(
          children: [
            count('active', active, AppColors.success),
            const SizedBox(width: 14),
            count('completed', completed, AppColors.info),
            const Spacer(),
            // Short enough to survive next to two counts on a narrow phone —
            // "Tap for list" ellipsised to "Tap for li…" at this width.
            Text(
              'See list',
              maxLines: 1,
              style: GoogleFonts.poppins(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyList(ScrollController controller, bool isDark) {
    final String message;
    if (_loading) {
      message = 'Loading…';
    } else if (_searching) {
      message = 'Nobody matches “${_query.trim()}”';
    } else {
      switch (_view) {
        case _View.completed:
          message = 'Nobody has completed the day yet';
        case _View.away:
          message = 'Everyone is at their site';
        case _View.active:
          message = _isToday
              ? 'Nobody is punched in right now'
              : 'No attendance on this day';
      }
    }

    return ListView(
      controller: controller,
      children: [
        const SizedBox(height: 24),
        const Icon(
          Iconsax.profile_delete,
          size: 30,
          color: AppColors.textTertiary,
        ),
        const SizedBox(height: 10),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Photo when the server has one, initials when it does not — and the
  /// initials also stand in while the image loads or if it fails, so the row
  /// never collapses to an empty square.
  ///
  /// The ring and the corner dot carry inside/outside now that the row has
  /// no "At site" / "Away" words: green at site, orange away, grey no
  /// location, blue finished. The dot sits on the corner so it survives a
  /// photo filling the square.
  Widget _buildAvatar(_LiveEmployee e, Color statusColor, bool isDark) {
    final fallback = Center(
      child: Text(
        e.initials,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: statusColor,
        ),
      ),
    );

    return SizedBox(
      width: 38,
      height: 38,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 38,
            height: 38,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.13),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: statusColor.withOpacity(0.55)),
            ),
            child: e.photoUrl == null
                ? fallback
                : CachedNetworkImage(
                    imageUrl: e.photoUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => fallback,
                    errorWidget: (_, _, _) => fallback,
                  ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
                // Ringed in the sheet's own colour so the dot reads as a
                // badge rather than a smudge on the photo.
                border: Border.all(
                  color: isDark ? AppColors.darkSurface : Colors.white,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// One of the two actions on a row. Disabled rather than hidden when it
  /// cannot work, so the rows stay the same shape down the list.
  Widget _buildRowAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    final tint = onTap == null ? AppColors.textTertiary : color;
    return SizedBox(
      width: 76,
      height: 25,
      child: Material(
        color: tint.withOpacity(0.11),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 11, color: tint),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: tint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmployeeTile(_LiveEmployee e, bool isDark) {
    final selected = e.key == _selectedKey;
    final statusColor = e.statusColor;

    return Material(
      color: selected
          ? AppColors.primary.withOpacity(isDark ? 0.14 : 0.06)
          : Colors.transparent,
      child: InkWell(
        // The row does what the Locate button does — the button is there to
        // name the gesture, not to be the only way to reach it.
        onTap: e.hasLocation ? () => _locateOn(e) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
          child: Row(
            children: [
              _buildAvatar(e, statusColor, isDark),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            e.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                        // Searching by code is common; showing the code is
                        // what makes such a hit read as a hit.
                        if (e.empCode.isNotEmpty) ...[
                          const SizedBox(width: 5),
                          Text(
                            '#${e.empCode}',
                            style: GoogleFonts.poppins(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      e.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            e.statusLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: statusColor,
                            ),
                          ),
                        ),
                        if (e.batteryPct != null) ...[
                          const SizedBox(width: 5),
                          Icon(
                            e.isBatteryLow
                                ? Iconsax.battery_empty
                                : Iconsax.battery_full,
                            size: 11,
                            color: e.isBatteryLow
                                ? AppColors.error
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${e.batteryPct}%',
                            style: GoogleFonts.poppins(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: e.isBatteryLow
                                  ? AppColors.error
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildRowAction(
                    icon: Iconsax.routing,
                    label: 'Route',
                    color: AppColors.primary,
                    // No session id, no trail to ask for.
                    onTap: e.sessionId == null ? null : () => _showRoute(e),
                  ),
                  const SizedBox(height: 5),
                  _buildRowAction(
                    icon: Iconsax.location,
                    label: 'Locate',
                    color: AppColors.secondary,
                    // Nothing to centre on for someone the map cannot place.
                    onTap: e.hasLocation ? () => _locateOn(e) : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Why the live feed could not answer. [canRetry] is false when the data is
/// genuinely absent rather than momentarily unreachable, so the UI can drop
/// the Retry affordance instead of offering a button that cannot work.
class _LiveUnavailable implements Exception {
  final String message;
  final bool canRetry;

  const _LiveUnavailable(this.message, {this.canRetry = true});

  @override
  String toString() => message;
}

// ─── Model ──────────────────────────────────────────────────────────────

/// One attendance session for the chosen date, flattened to what the screen
/// needs. [fromJson] parses the `employees[]` rows of
/// `GET /api/attendance/geofence-live` (docs/geofence-live-dashboard-api.md
/// §"Employee Object"), so the mock and the real endpoint go through exactly
/// the same code.
class _LiveEmployee {
  final String key;

  /// Needed to ask for this session's route trail. Null only if the server
  /// omitted it, in which case the route action is not offered.
  final int? sessionId;

  final String name;
  final String empCode;
  final String department;
  final String branchName;
  final String? photoUrl;
  final double? latitude;
  final double? longitude;
  final DateTime? capturedAt;
  final DateTime? startedAt;
  final DateTime? endedAt;

  /// Tri-state on purpose. `null` is "we have no location for this person",
  /// which is a different fact from "outside the fence" and must not be
  /// reported as one.
  final bool? insideGeofence;

  /// Metres from the fence centre, when the server worked it out.
  final int? distanceM;

  /// Seconds the session has run. The server computes it; deriving it from
  /// the timestamps here would disagree on a force-closed session.
  final int? durationSeconds;

  /// Last reported battery. Only surfaced when it is low enough to explain a
  /// stale position — a dead phone is the usual reason someone stops pinging.
  final int? batteryPct;

  final String? punchInSelfie;
  final String? punchOutSelfie;

  final bool isActive;

  /// The shift ended and the system closed the session; nobody punched out.
  final bool isForceClosed;

  const _LiveEmployee({
    required this.key,
    required this.sessionId,
    required this.name,
    required this.empCode,
    required this.department,
    required this.branchName,
    required this.photoUrl,
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
    required this.startedAt,
    required this.endedAt,
    required this.insideGeofence,
    required this.distanceM,
    required this.durationSeconds,
    required this.batteryPct,
    required this.punchInSelfie,
    required this.punchOutSelfie,
    required this.isActive,
    required this.isForceClosed,
  });

  factory _LiveEmployee.fromJson(Map<String, dynamic> json, int index) {
    final empCode = (json['emp_code'] ?? '').toString();
    final sessionId = _toInt(json['session_id'] ?? json['id']);
    final status = (json['status'] ?? '').toString().toLowerCase();
    final photo = (json['emp_image_url'] ?? '').toString().trim();

    return _LiveEmployee(
      // Session id first. It is stable across polls, like emp_code, but it is
      // also unique when one person has two sessions in a day — keying on
      // emp_code there would give two rows the same MarkerId and lose a pin.
      key: sessionId != null
          ? 'sess_$sessionId'
          : (empCode.isNotEmpty ? 'emp_$empCode' : 'row_$index'),
      sessionId: sessionId,
      name: (json['emp_name'] ?? '—').toString(),
      empCode: empCode,
      // The server sends "-" when there is no department; that is noise in a
      // subtitle, so treat it as empty.
      department: _clean(json['department']),
      branchName: _clean(json['branch_name'], fallback: '—'),
      photoUrl: photo.isEmpty ? null : photo,
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      capturedAt: _toDate(json['captured_at']),
      startedAt: _toDate(json['started_at']),
      // A force-closed session has no punch-out; the shift end stands in for
      // one so the row can still say when the day ended.
      endedAt: _toDate(json['ended_at']) ?? _toDate(json['shift_end_time']),
      insideGeofence: json['inside_geofence'] is bool
          ? json['inside_geofence'] as bool
          : null,
      distanceM: _toInt(json['distance_m']),
      durationSeconds: _toInt(json['duration_seconds']),
      batteryPct: _toInt(json['battery_pct']),
      punchInSelfie: _url(json['punch_in_selfie']),
      punchOutSelfie: _url(json['punch_out_selfie']),
      isActive: status == 'active',
      isForceClosed: status == 'force_closed',
    );
  }

  bool get hasLocation => latitude != null && longitude != null;

  bool get hasSelfies => punchInSelfie != null || punchOutSelfie != null;

  /// Low enough to explain a position going stale, and worth colouring red.
  /// The percentage itself is shown at every level.
  bool get isBatteryLow => batteryPct != null && batteryPct! <= 20;

  /// "9h 15m", the format the dashboard contract asks for. Null when the
  /// server did not send a duration.
  String? get durationLabel {
    final seconds = durationSeconds;
    if (seconds == null || seconds <= 0) return null;
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours == 0) return '${minutes}m';
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }

  /// Active, located, and outside the fence — the only combination the
  /// "Away from site" chip should count. An unknown position is not an
  /// accusation.
  bool get isAway => isActive && insideGeofence == false;

  String get displayName => empCode.isEmpty ? name : '$name ($empCode)';

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '—';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  String get subtitle {
    final role = department.isEmpty ? null : department;
    return [branchName, if (role != null) role].join(' · ');
  }

  Color get statusColor {
    if (!isActive) return AppColors.info;
    if (insideGeofence == null) return AppColors.textTertiary;
    return insideGeofence! ? AppColors.success : AppColors.warning;
  }

  String get badgeLabel {
    if (!isActive) return isForceClosed ? 'Auto-closed' : 'Completed';
    if (insideGeofence == null) return 'No location';
    if (insideGeofence!) return 'At site';
    // How far out is the whole point of flagging someone away.
    return distanceM == null ? 'Away' : 'Away · ${distanceM}m';
  }

  double get markerHue {
    if (!isActive) return BitmapDescriptor.hueAzure;
    if (insideGeofence == null) return BitmapDescriptor.hueViolet;
    return insideGeofence!
        ? BitmapDescriptor.hueGreen
        : BitmapDescriptor.hueOrange;
  }

  /// The one line that says what this person is doing: a finished session
  /// shows its span, a running one shows how fresh the last fix is.
  String get statusLine {
    final fmt = DateFormat('h:mm a');
    final inAt = startedAt == null ? '—' : fmt.format(startedAt!);
    if (!isActive) {
      final outAt = endedAt == null ? '—' : fmt.format(endedAt!);
      final span = durationLabel == null ? '' : ' · $durationLabel';
      if (isForceClosed) return 'Started $inAt · auto-closed $outAt$span';
      return 'Worked $inAt to $outAt$span';
    }
    final since = startedAt == null ? '' : 'Started $inAt · ';
    return '${since}seen $lastPingAgo';
  }

  String get lastPingAgo {
    final at = capturedAt;
    if (at == null) return 'no location yet';
    final diff = DateTime.now().difference(at);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    return '${diff.inDays}d ago';
  }

  static String? _url(dynamic value) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? null : text;
  }

  static String _clean(dynamic value, {String fallback = ''}) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty || text == '-') return fallback;
    return text;
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  /// Timestamps arrive as `{iso, time, date, full}` objects on this endpoint.
  /// Only `iso` is machine-readable — the rest are pre-formatted for a UI
  /// that is not this one. A plain ISO string is accepted too, so the mock
  /// and any older payload still parse.
  static DateTime? _toDate(dynamic value) {
    if (value == null) return null;
    if (value is Map) {
      final iso = value['iso'];
      return iso == null ? null : DateTime.tryParse(iso.toString())?.toLocal();
    }
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}

/// One stop on a session's trail: where the person punched in, each ping in
/// between, and where they punched out.
class _RoutePoint {
  final String type; // punch_in | ping | punch_out
  final double latitude;
  final double longitude;
  final DateTime? at;

  const _RoutePoint({
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.at,
  });

  static _RoutePoint? fromJson(Map<String, dynamic> json) {
    final lat = _LiveEmployee._toDouble(json['latitude']);
    final lng = _LiveEmployee._toDouble(json['longitude']);
    // A point without coordinates cannot be drawn; drop it rather than
    // letting it collapse the polyline onto null island.
    if (lat == null || lng == null) return null;
    return _RoutePoint(
      type: (json['type'] ?? 'ping').toString(),
      latitude: lat,
      longitude: lng,
      at: _LiveEmployee._toDate(json['time']),
    );
  }

  LatLng get position => LatLng(latitude, longitude);
  bool get isPunchIn => type == 'punch_in';
  bool get isPunchOut => type == 'punch_out';
}

// ─── Mock backend ───────────────────────────────────────────────────────

/// Stand-in for the geofence endpoints until the real ones land.
///
/// Deliberately returns the *JSON envelope* rather than model objects, so the
/// screen's parsing and filtering are the code that will run in production.
/// Delete this class and point [_TeamLocationMapScreenState._loadSnapshot] and
/// `_loadBranches` at `ApiService` when the API is ready.
class _MockGeofenceApi {
  static final List<BranchModel> _branches = [
    BranchModel(
      id: 1,
      branchName: 'Pune — Balewadi',
      latitude: 18.5680,
      longitude: 73.7749,
      geofenceRadiusM: 160,
    ),
    BranchModel(
      id: 2,
      branchName: 'Pune — Hinjewadi',
      latitude: 18.5913,
      longitude: 73.7389,
      geofenceRadiusM: 220,
    ),
    BranchModel(
      id: 3,
      branchName: 'Nashik — Satpur',
      latitude: 19.9975,
      longitude: 73.7398,
      geofenceRadiusM: 180,
    ),
    BranchModel(
      id: 4,
      branchName: 'Mumbai — Andheri',
      latitude: 19.1197,
      longitude: 72.8464,
      geofenceRadiusM: 130,
    ),
  ];

  /// (name, emp code, department, branch id)
  static const List<(String, String, String, int)> _roster = [
    ('Abhilash Shetty', '1104', 'Projects', 1),
    ('Rahul Sharma', '1112', 'Site', 1),
    ('Priya Menon', '1118', 'QA/QC', 1),
    ('Amit Kulkarni', '1123', 'Survey', 1),
    ('Sneha Patil', '1131', 'HR', 1),
    ('Vikram Rao', '1140', 'Planning', 2),
    ('Neha Joshi', '1147', 'Billing', 2),
    ('Imran Shaikh', '1152', 'Safety', 2),
    ('Kavita Desai', '1158', 'Accounts', 2),
    ('Sandeep Naik', '1166', 'Site', 3),
    ('Anjali Kulkarni', '1173', 'Design', 3),
    ('Rohit Gaikwad', '1179', 'Stores', 3),
    ('Farhan Qureshi', '1184', 'Structural', 4),
    ('Deepa Iyer', '1190', 'Admin', 4),
    ('Manoj Pawar', '1196', 'Site', 4),
    ('Sania Kadam', '1201', 'Trainee', 4),
  ];

  /// The endpoint's `{iso, time, date, full}` timestamp object.
  static Map<String, String> _time(DateTime at) => {
    'iso': at.toIso8601String(),
    'time': DateFormat('hh:mm a').format(at),
    'date': DateFormat('dd MMM yyyy').format(at),
    'full': DateFormat('dd MMM yyyy, hh:mm a').format(at),
  };

  /// A plausible trail for the demo path: punch-in, a wander, and a
  /// punch-out for anyone who has finished.
  static Future<List<_RoutePoint>> route(_LiveEmployee employee) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final origin = employee.hasLocation
        ? LatLng(employee.latitude!, employee.longitude!)
        : const LatLng(18.5680, 73.7749);

    final rng = Random(employee.sessionId ?? 0);
    final start = employee.startedAt ?? DateTime.now();
    final points = <_RoutePoint>[
      _RoutePoint(
        type: 'punch_in',
        latitude: origin.latitude + 0.0012,
        longitude: origin.longitude - 0.0009,
        at: start,
      ),
    ];

    for (var i = 1; i <= 6; i++) {
      points.add(
        _RoutePoint(
          type: 'ping',
          latitude: origin.latitude + (rng.nextDouble() - 0.5) * 0.003,
          longitude: origin.longitude + (rng.nextDouble() - 0.5) * 0.003,
          at: start.add(Duration(minutes: 45 * i)),
        ),
      );
    }

    if (!employee.isActive) {
      points.add(
        _RoutePoint(
          type: 'punch_out',
          latitude: origin.latitude,
          longitude: origin.longitude,
          at: employee.endedAt ?? start.add(const Duration(hours: 9)),
        ),
      );
    }
    return points;
  }

  /// Returns the inner `data` object of
  /// `GET /api/attendance/geofence-live` — same keys, same nesting, so the
  /// screen's parsing is the code that runs in production either way.
  static Future<Map<String, dynamic>> fetch({required DateTime date}) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final now = DateTime.now();
    final today = DateUtils.dateOnly(now);
    final dateKey = DateFormat('yyyy-MM-dd').format(date);

    final branches = [
      for (final b in _branches)
        {
          'id': b.id,
          'branch_name': b.branchName,
          'latitude': b.latitude,
          'longitude': b.longitude,
          'geofence_radius_m': b.geofenceRadiusM,
        },
    ];

    // Nothing has happened tomorrow yet.
    if (date.isAfter(today)) {
      return {
        'date': dateKey,
        'summary': const {
          'total_today': 0,
          'active_now': 0,
          'completed': 0,
          'outside_fence': 0,
        },
        'employees': const <Map<String, dynamic>>[],
        'branches': branches,
      };
    }

    // Seeded by the date so a given day always renders the same board —
    // scrubbing the date picker back and forth must not reshuffle people.
    final seed = date.year * 10000 + date.month * 100 + date.day;
    final rng = Random(seed);
    final isToday = DateUtils.isSameDay(date, today);

    final rows = <Map<String, dynamic>>[];
    for (final (name, code, department, bId) in _roster) {
      final branch = _branches.firstWhere((b) => b.id == bId);

      // A settled day is all finished; today is a live mix.
      final active = isToday && rng.nextDouble() < 0.62;
      final forceClosed = !active && rng.nextDouble() < 0.12;
      final inside = rng.nextDouble() < 0.78;
      // Two people a day forget to enable location — the "not on the map"
      // counter needs something to count, and `inside_geofence: null` is a
      // real state this screen has to render.
      final located = rng.nextDouble() < 0.88;

      final startedAt = DateTime(
        date.year,
        date.month,
        date.day,
        8,
        30,
      ).add(Duration(minutes: rng.nextInt(75)));
      final endedAt = active
          ? null
          : DateTime(
              date.year,
              date.month,
              date.day,
              17,
              30,
            ).add(Duration(minutes: rng.nextInt(90)));

      final captured = active
          ? now.subtract(Duration(minutes: rng.nextInt(26)))
          : endedAt;

      // Inside pins scatter within the fence; outside ones sit a few hundred
      // metres away so the circle overlay actually reads as a boundary.
      final spread = inside ? 0.0008 : 0.0045;
      final lat = branch.latitude! + (rng.nextDouble() - 0.5) * 2 * spread;
      final lng = branch.longitude! + (rng.nextDouble() - 0.5) * 2 * spread;

      rows.add({
        'session_id': int.parse(code),
        'emp_id': int.parse(code),
        'emp_name': name,
        'emp_code': code,
        'emp_image_url': null,
        'department': department,
        'branch_name': branch.branchName,
        'latitude': located ? lat : null,
        'longitude': located ? lng : null,
        'inside_geofence': located ? inside : null,
        'captured_at': located && captured != null ? _time(captured) : null,
        'started_at': _time(startedAt),
        'ended_at': endedAt == null ? null : _time(endedAt),
        'duration_seconds': (endedAt ?? now).difference(startedAt).inSeconds,
        'ping_count': rng.nextInt(40),
        // Spans the low-battery threshold so the demo path exercises the
        // warning too, not just the happy case.
        'battery_pct': 8 + rng.nextInt(92),
        'distance_m': located
            ? (inside ? rng.nextInt(80) : 200 + rng.nextInt(600))
            : null,
        'status': active ? 'active' : (forceClosed ? 'force_closed' : 'closed'),
        'shift_end_time': forceClosed && endedAt != null
            ? _time(endedAt)
            : null,
        'punch_in_selfie': null,
        'punch_out_selfie': null,
      });
    }

    final activeCount = rows.where((r) => r['status'] == 'active').length;
    return {
      'date': dateKey,
      'summary': {
        'total_today': rows.length,
        'active_now': activeCount,
        'completed': rows.length - activeCount,
        'outside_fence': rows
            .where(
              (r) => r['status'] == 'active' && r['inside_geofence'] == false,
            )
            .length,
      },
      'employees': rows,
      'branches': branches,
    };
  }
}
