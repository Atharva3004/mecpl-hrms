import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../models/location_point_model.dart';
import '../../models/local_punch_record.dart';
import '../../providers/location_history_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/attendance_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/role_model.dart';
import '../../models/user_model.dart';
import '../../services/api_service.dart';
import '../../widgets/attendance/timing_row_card.dart';
import '../attendance/punch_view_screen.dart';
import 'employee_location_map_screen.dart';

class LocationHistoryScreen extends StatefulWidget {
  const LocationHistoryScreen({super.key});

  @override
  State<LocationHistoryScreen> createState() => _LocationHistoryScreenState();
}

class _LocationHistoryScreenState extends State<LocationHistoryScreen> {
  String? _selectedEmployeeId;
  bool _isDateToday = true;

  // ─── Viewing another employee (admin / director only) ────────────────
  // Null means "my own history", which is what the screen opens on. Set by
  // the search field; cleared by "Back to mine".
  UserModel? _viewingEmployee;

  /// Everyone the admin may look up. Fetched once, filtered locally — the
  /// list is small enough that a round trip per keystroke would be worse.
  List<UserModel> _allEmployees = const [];
  bool _loadingEmployees = false;

  /// Set when the roster could not be fetched, so the search field can say
  /// so and offer a retry instead of sitting on "Loading employees…"
  /// forever — a hint that never changes is indistinguishable from a hang.
  String? _employeeError;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  // 60-second polling loop that pulls /attendance/session/{id}/timeline
  // while the "Intermediate Tracking" toggle is ON. Cancelled on toggle OFF,
  // on screen dispose, and on past-date selection.
  Timer? _refreshTimer;

  // Null until _checkLocationAvailability() runs. True = GPS on + permission
  // granted. False = GPS off or permission denied → screen shows a "turn
  // location on" banner per the product spec. Re-checked on resume and
  // whenever the user taps the toggle.
  bool? _locationAvailable;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    // Reset the toggle to OFF on every screen open (the provider is a
    // singleton, so without this the last state would carry over).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final userId = auth.currentUser?.id;
      if (userId != null) {
        context.read<LocationHistoryProvider>().resetForScreenOpen(userId);
      }
      _checkLocationAvailability();
      _loadForCurrentState();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Checks device-level location services + app permission. Kept separate
  /// from the toggle so the "turn location on" banner renders even when the
  /// toggle is OFF (latest-punch-in mode).
  Future<void> _checkLocationAvailability() async {
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) {
      if (!mounted) return;
      setState(() => _locationAvailable = false);
      return;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.deniedForever) {
      if (!mounted) return;
      setState(() => _locationAvailable = false);
      return;
    }
    if (!mounted) return;
    setState(() => _locationAvailable = true);
  }

  /// The screen always opens on the signed-in user's own day. For an admin
  /// or director it additionally fetches the roster in the background, so
  /// the search field has something to match against — but nothing about
  /// the initial view depends on that call landing.
  Future<void> _loadEmployees() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    if (!mounted) return;
    setState(() => _selectedEmployeeId = currentUser?.id);

    if (currentUser == null || !currentUser.role.canViewLocationHistory) return;

    final token = authProvider.token;
    if (token == null || token.isEmpty) return;

    setState(() {
      _loadingEmployees = true;
      _employeeError = null;
    });
    try {
      final response = await ApiService.getEmployees(token);
      if (!mounted) return;
      if (response.isSuccess && response.data != null) {
        final people = ApiService.parseEmployeesFromResponse(response.data!);
        // Yourself is not a "search result" — your own day is what the
        // screen already shows, and "Back to mine" is how you return.
        final others = people.where((e) => e.id != currentUser.id).toList();
        setState(() {
          _allEmployees = others;
          _loadingEmployees = false;
          // An empty roster is not success: the field would match nothing
          // and look broken. Say so, and let them try again.
          _employeeError = others.isEmpty ? 'No employees found' : null;
        });
      } else {
        setState(() {
          _loadingEmployees = false;
          _employeeError = response.error ?? 'Could not load employees';
        });
      }
    } catch (e) {
      debugPrint('Location history: could not load employees — $e');
      if (!mounted) return;
      setState(() {
        _loadingEmployees = false;
        _employeeError = 'Could not load employees';
      });
    }
  }

  /// Switch the screen over to one employee's day.
  void _viewEmployee(UserModel employee) {
    FocusScope.of(context).unfocus();
    setState(() {
      _viewingEmployee = employee;
      _selectedEmployeeId = employee.id;
    });
    _loadForCurrentState();
  }

  /// Back to the admin's own history — the state the screen opens in.
  void _viewMyself() {
    FocusScope.of(context).unfocus();
    _searchController.clear();
    setState(() {
      _viewingEmployee = null;
      _selectedEmployeeId = context.read<AuthProvider>().currentUser?.id;
    });
    _loadForCurrentState();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Formats a whole-day work total (seconds) as "8h 0m" for the banner.
  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;
    final isAdmin = currentUser?.role.canViewLocationHistory ?? false;
    // Strictly the Admin role — only they get the Intermediate Tracking
    // toggle and the View on Google Map button.
    final isStrictAdmin = currentUser?.role == UserRole.admin;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _viewingEmployee?.fullName ?? 'Today\'s Timing',
          style: GoogleFonts.poppins(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 17,
          ),
        ),
      ),
      body: Consumer<LocationHistoryProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.errorMessage != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    provider.errorMessage!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () =>
                        _loadLocationData(provider, currentUser?.id),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final points = _selectedEmployeeId != null
              ? provider.getPointsForUser(_selectedEmployeeId!)
              : provider.locationPoints;

          return Column(
            children: [
              _buildTopCard(
                context,
                provider,
                currentUser?.id ?? '',
                isAdmin,
                isStrictAdmin,
              ),
              _buildStatusBanner(provider, points),
              if (_viewingEmployee != null) _buildSessionStrip(provider),
              Expanded(child: _buildContent(provider, points)),
              // The map is where the route actually reads as a route. It was
              // admin-only; anyone looking up another employee needs it too.
              if (isStrictAdmin || _viewingEmployee != null)
                _buildViewOnMapButton(provider),
            ],
          );
        },
      ),
    );
  }

  /// Active / Completed per session, with the hours and the ping count.
  /// The timeline below flattens every session into one stream, so without
  /// this there is nothing on screen that answers "is this person still
  /// working, and how much of the day is this?".
  Widget _buildSessionStrip(LocationHistoryProvider provider) {
    final sessions = provider.sessions;
    if (sessions.isEmpty) return const SizedBox.shrink();

    final fmt = DateFormat('h:mm a');

    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        itemCount: sessions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final session = sessions[i];
          final color = session.isActive
              ? AppColors.success
              : (session.isForceClosed ? AppColors.warning : AppColors.info);

          final span = session.startedAt == null
              ? '—'
              : session.endedAt == null
              ? 'since ${fmt.format(session.startedAt!)}'
              : '${fmt.format(session.startedAt!)} – '
                    '${fmt.format(session.endedAt!)}';

          final seconds = session.durationSeconds;
          final worked = seconds == null ? null : _formatDuration(seconds);

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      session.label,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    if (worked != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        worked,
                        style: GoogleFonts.poppins(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$span · ${session.pingCount} pings',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── [1] Top Card ─────────────────────────────────────────────────────────

  Widget _buildTopCard(
    BuildContext context,
    LocationHistoryProvider provider,
    String currentUserId,
    bool isAdmin,
    bool isStrictAdmin,
  ) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        children: [
          // Row A – Whose history. Admin/director only: a search when
          // looking at your own day, a "who you are viewing" bar once you
          // have picked someone.
          if (isAdmin) ...[
            _viewingEmployee == null
                ? _buildEmployeeSearch()
                : _buildViewingBar(),
            const SizedBox(height: 12),
          ],

          // Row B – Date selector
          _buildDateRow(context, provider),

          // Row C – Toggle. Admin-only, and only for your own history: a
          // looked-up employee always comes back with pings, so the switch
          // would be a control that visibly does nothing.
          if (isStrictAdmin && _viewingEmployee == null) ...[
            const SizedBox(height: 12),
            _buildToggleRow(provider, currentUserId),
          ],
        ],
      ),
    );
  }

  /// Name or employee code, matched locally. Same interaction as the
  /// employee picker on the leave screen, so it is already familiar.
  Widget _buildEmployeeSearch() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _employeeError == null ? null : _loadEmployees,
            child: Icon(
              _employeeError == null ? Icons.search : Icons.refresh,
              size: 18,
              color: _employeeError == null ? Colors.black45 : AppColors.error,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RawAutocomplete<UserModel>(
              textEditingController: _searchController,
              focusNode: _searchFocus,
              displayStringForOption: (e) =>
                  '${e.fullName} (#${e.employeeId ?? e.id})',
              optionsBuilder: (value) {
                final q = value.text.trim().toLowerCase();
                if (q.isEmpty) return const Iterable<UserModel>.empty();
                return _allEmployees
                    .where((e) {
                      final code = (e.employeeId ?? '').toLowerCase();
                      return e.fullName.toLowerCase().contains(q) ||
                          code.contains(q);
                    })
                    .take(30);
              },
              onSelected: _viewEmployee,
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) {
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        hintText: _loadingEmployees
                            ? 'Loading employees…'
                            : _employeeError != null
                            ? '$_employeeError — tap ↻ to retry'
                            : 'Search employee by name or code',
                        hintStyle: GoogleFonts.poppins(
                          fontSize: 13,
                          color: _employeeError != null
                              ? AppColors.error
                              : Colors.black38,
                        ),
                      ),
                    );
                  },
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (context, i) {
                          final e = options.elementAt(i);
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: AppColors.primary.withValues(
                                alpha: 0.15,
                              ),
                              child: const Icon(
                                Icons.person,
                                size: 15,
                                color: AppColors.primary,
                              ),
                            ),
                            title: Text(
                              e.fullName,
                              style: GoogleFonts.poppins(fontSize: 13),
                            ),
                            subtitle: Text(
                              '#${e.employeeId ?? e.id}',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.black54,
                              ),
                            ),
                            onTap: () => onSelected(e),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Replaces the search field once an employee is chosen, so it is never
  /// ambiguous whose day is on screen.
  Widget _buildViewingBar() {
    final e = _viewingEmployee!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: AppColors.primary.withValues(alpha: 0.18),
            child: const Icon(Icons.person, size: 15, color: AppColors.primary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  e.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  '#${e.employeeId ?? e.id}',
                  style: GoogleFonts.poppins(
                    fontSize: 10.5,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _viewMyself,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Back to mine',
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateRow(BuildContext context, LocationHistoryProvider provider) {
    final displayDate = _isDateToday
        ? 'Today,  ${DateFormat('dd MMM').format(DateTime.now())}'
        : DateFormat(
            'dd MMM yyyy',
          ).format(DateTime.parse(provider.selectedDate));

    return GestureDetector(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: AppConstants.appStartDate,
          lastDate: DateTime.now(),
        );
        if (date != null) {
          final formatted = DateFormat('yyyy-MM-dd').format(date);
          final isToday = _isSameDay(date, DateTime.now());
          setState(() => _isDateToday = isToday);
          provider.setSelectedDate(formatted);
          if (_selectedEmployeeId != null) {
            _loadForCurrentState();
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8F8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today,
              size: 18,
              color: Color(0xFFFF9800),
            ),
            const SizedBox(width: 10),
            Text(
              displayDate,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleRow(
    LocationHistoryProvider provider,
    String currentUserId,
  ) {
    final isActive = provider.isTrackingEnabled;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFFE8F5E9)
                    : const Color(0xFFF5F5F5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isActive ? Icons.my_location : Icons.location_disabled,
                size: 16,
                color: isActive ? const Color(0xFF4CAF50) : Colors.grey,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Intermediate Tracking',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch.adaptive(
              value: isActive,
              onChanged: _handleToggle,
              activeThumbColor: const Color(0xFFFF9800),
              activeTrackColor: const Color(0xFFFFCC80),
            ),
            const SizedBox(width: 6),
            Text(
              isActive ? 'ON' : 'OFF',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isActive
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFF9E9E9E),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── [2] Status Banner ────────────────────────────────────────────────────

  Widget _buildStatusBanner(
    LocationHistoryProvider provider,
    List<dynamic> points,
  ) {
    Color bgColor;
    Color textColor;
    IconData icon;
    String label;

    // A looked-up employee is always served from stored history, never the
    // live session, so it must not borrow today's "Live" wording.
    final viewing = _viewingEmployee;
    if (viewing != null) {
      final total = provider.totalSeconds;
      final totalLabel = (total != null && total > 0)
          ? ' · ${_formatDuration(total)} worked'
          : '';
      final dayLabel = _isDateToday
          ? 'Today'
          : DateFormat(
              'dd MMM yyyy',
            ).format(DateTime.parse(provider.selectedDate));
      return _bannerShell(
        bgColor: const Color(0xFFE3F2FD),
        textColor: const Color(0xFF1565C0),
        icon: Icons.person_search,
        label:
            '${viewing.fullName} · $dayLabel · '
            '${points.length} points$totalLabel',
      );
    }

    if (!_isDateToday) {
      bgColor = const Color(0xFFE3F2FD);
      textColor = const Color(0xFF1565C0);
      icon = Icons.history;
      final parsed = DateTime.parse(provider.selectedDate);
      final total = provider.totalSeconds;
      final totalLabel = (total != null && total > 0)
          ? ' · ${_formatDuration(total)} worked'
          : '';
      label =
          'History · ${DateFormat('dd MMM yyyy').format(parsed)} · ${points.length} points$totalLabel';
    } else if (provider.isTrackingEnabled) {
      bgColor = const Color(0xFFE8F5E9);
      textColor = const Color(0xFF2E7D32);
      icon = Icons.fiber_manual_record;
      label = 'Live · Showing all ${points.length} points today';
    } else {
      bgColor = const Color(0xFFFFF3E0);
      textColor = const Color(0xFFE65100);
      icon = Icons.location_pin;
      label = 'Latest Location Only';
    }

    return _bannerShell(
      bgColor: bgColor,
      textColor: textColor,
      icon: icon,
      label: label,
    );
  }

  Widget _bannerShell({
    required Color bgColor,
    required Color textColor,
    required IconData icon,
    required String label,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── [3] Content ──────────────────────────────────────────────────────────

  Widget _buildContent(LocationHistoryProvider provider, List<dynamic> points) {
    // Someone else's day is stored history, whatever the date. The checks
    // further down are about *this device* — its GPS permission and the
    // signed-in user's own session — and applying them here would answer a
    // question nobody asked ("you haven't punched in") over another
    // person's data.
    if (_viewingEmployee != null) {
      if (points.isEmpty) {
        return _buildEmptyState(
          icon: Icons.event_busy,
          title: 'Nothing recorded',
          subtitle:
              '${_viewingEmployee!.fullName} has no punches or tracking '
              'points on this day.',
        );
      }
      return _buildTimingList(points.cast<LocationPoint>());
    }

    // Past date → real history from GET /attendance/history?date=. GPS state
    // is irrelevant here (we're reading stored data, not tracking live), so we
    // skip the location-availability / active-session checks below.
    if (!_isDateToday) {
      if (points.isEmpty) {
        return _buildEmptyState(
          icon: Icons.event_busy,
          title: 'No records for this date',
          subtitle: 'No punches or tracking points were recorded on this day.',
        );
      }
      final typedPoints = points.cast<LocationPoint>();
      // OFF → punches only (with the "tracking paused" hint up top).
      // ON  → punches + tracking pings, same row UI as today.
      if (!provider.isTrackingEnabled) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          children: [
            _buildPausedHint(),
            const SizedBox(height: 10),
            for (final p in typedPoints)
              TimingRowCard.fromPoint(p, onTap: _rowTapFor(p)),
          ],
        );
      }
      return _buildTimingList(typedPoints);
    }

    // Device-level location is off or denied — tell the user, per product spec.
    if (_locationAvailable == false) {
      return _buildEmptyState(
        icon: Icons.location_disabled,
        title: 'Turn on location to see tracking',
        subtitle:
            'Enable GPS in your device settings so MECPL HRMS can show '
            'your live punch-in and session pings.',
      );
    }

    final att = context.watch<AttendanceProvider>();
    final hasActiveSession = att.todaySessionId != null;

    if (!hasActiveSession) {
      // User hasn't punched in today → nothing to show.
      return _buildEmptyState(
        icon: Icons.touch_app_outlined,
        title: 'No punches yet today',
        subtitle: 'Punch in from the Attendance screen to start tracking.',
      );
    }

    if (points.isEmpty) {
      // Active session exists but the server returned no points yet
      // (edge case — could happen if the punch-in record is still being
      // written server-side).
      return _buildEmptyState(
        icon: Icons.hourglass_empty,
        title: 'Waiting for today\'s punch-in…',
        subtitle: 'Tap the toggle again in a moment to refresh.',
      );
    }

    // Both modes use the same flat list of timing rows now. OFF shows the
    // day's punch-in and punch-out only; ON includes tracking pings in
    // between. Up top, OFF mode shows a small "Live tracking paused" hint
    // so the user knows the toggle exists.
    final List<LocationPoint> typedPoints = points.cast<LocationPoint>();
    if (!provider.isTrackingEnabled) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        children: [
          _buildPausedHint(),
          const SizedBox(height: 10),
          for (final p in typedPoints)
            TimingRowCard.fromPoint(p, onTap: _rowTapFor(p)),
        ],
      );
    }
    return _buildTimingList(typedPoints);
  }

  Widget _buildTimingList(List<LocationPoint> points) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      itemCount: points.length,
      itemBuilder: (_, index) => TimingRowCard.fromPoint(
        points[index],
        onTap: _rowTapFor(points[index]),
      ),
    );
  }

  /// Tapping a Punch In / Punch Out row opens its full Punch Details page.
  /// Tracking pings have no detail page, so they get no tap handler.
  VoidCallback? _rowTapFor(LocationPoint p) {
    if (p.type != 'In' && p.type != 'Out') return null;
    return () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PunchViewScreen(punchRecord: _pointToPunchRecord(p)),
        ),
      );
    };
  }

  /// Adapts a [LocationPoint] (In/Out) into the [LocalPunchRecord] that
  /// [PunchViewScreen] expects.
  LocalPunchRecord _pointToPunchRecord(LocationPoint p) {
    return LocalPunchRecord(
      id: p.id,
      timestamp: p.timestamp,
      type: p.type == 'Out' ? PunchType.punchOut : PunchType.punchIn,
      latitude: p.latitude,
      longitude: p.longitude,
      address: p.address.isEmpty ? null : p.address,
      selfieImagePath: p.selfiePath,
      isInsideOffice: p.isInside ?? true,
      distanceFromOffice: p.distanceM,
    );
  }

  /// Orange "Live tracking paused" chip shown above the OFF-mode list so
  /// the user knows the Intermediate Tracking toggle exists and what it
  /// does. Mirrors the muted callout style used elsewhere on the screen.
  Widget _buildPausedHint() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFCC80)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.pause_circle_filled,
            size: 16,
            color: Color(0xFFE65100),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Live tracking is paused — toggle ON to see pings between punches.',
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                color: const Color(0xFFE65100),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Shared empty-state layout. Keeps copy consistent across "past-date",
  /// "location off", and "no punch-in" cases.
  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    // Centred when there is room, scrollable when there is not. The plain
    // Center + Column here was MainAxisSize.max with 64px of padding and a
    // 64px icon, so the moment the keyboard shrank the body it overflowed
    // by ~108px — the striped banner. Scrolling makes the overflow
    // impossible at any height rather than tuning the numbers for one phone.
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey[600],
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── [4] View on Google Map — UNCHANGED ───────────────────────────────────

  Widget _buildViewOnMapButton(LocationHistoryProvider provider) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: ElevatedButton.icon(
        onPressed: () {
          final userId = _selectedEmployeeId;
          if (userId == null) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EmployeeLocationMapScreen(
                userId: userId,
                userName:
                    _viewingEmployee?.fullName ??
                    context.read<AuthProvider>().currentUser?.fullName ??
                    'Location',
              ),
            ),
          );
        },
        icon: const Icon(Icons.map, size: 18, color: Color(0xFF4CAF50)),
        label: Text(
          'View On Google Map',
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF4CAF50),
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFF4CAF50), width: 2),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  void _loadLocationData(LocationHistoryProvider provider, String? userId) {
    if (userId == null) return;
    _loadForCurrentState();
  }

  /// Picks the server endpoint based on toggle state and today-vs-past:
  ///   - Today + toggle OFF → `/attendance/today` → active session's
  ///     punch-in only (via `loadLatestPunchIn`).
  ///   - Today + toggle ON  → `/attendance/session/{active_id}/timeline`
  ///     (via `loadFromTodaysSession`), plus a 60-second polling loop.
  ///   - Past date          → `GET /attendance/history?date=<selected>`
  ///     (via `loadHistoryForDate`); toggle OFF shows punches only, ON adds
  ///     tracking pings. No polling — the data is fixed.
  ///
  /// Never reads the local SharedPreferences cache — if the server call
  /// fails the user sees an error, not stale data.
  void _loadForCurrentState() {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final att = context.read<AttendanceProvider>();
    final provider = context.read<LocationHistoryProvider>();
    final currentUserId = auth.currentUser?.id;
    final userId = _selectedEmployeeId ?? currentUserId;
    final token = auth.token;

    // Looking at someone else: /attendance/history is the only endpoint that
    // takes a user_id. The two "today" paths below cannot serve this —
    // /attendance/today is self-only, and the live timeline is keyed by the
    // *admin's* own session id. So an employee's day comes from history
    // whatever the date, with pings always on: the route is the point of
    // looking them up.
    final viewing = _viewingEmployee;
    if (viewing != null) {
      _refreshTimer?.cancel();
      if (token == null) return;
      final adminUserId = int.tryParse(viewing.id);
      if (adminUserId == null) return;
      provider.loadHistoryForDate(
        token: token,
        userId: viewing.id,
        date: provider.selectedDate,
        includePings: true,
        adminUserId: adminUserId,
      );
      return;
    }

    // Past date → fetch stored history via GET /attendance/history?date=.
    // No live polling (the data is fixed). The toggle decides whether pings
    // are included: OFF = punches only, ON = punches + tracking pings.
    if (!_isDateToday) {
      _refreshTimer?.cancel();
      if (userId == null || token == null) return;
      // user_id is admin-only — pass it only when viewing another employee.
      final adminUserId = (userId != currentUserId)
          ? int.tryParse(userId)
          : null;
      provider.loadHistoryForDate(
        token: token,
        userId: userId,
        date: provider.selectedDate,
        includePings: provider.isTrackingEnabled,
        adminUserId: adminUserId,
      );
      return;
    }

    if (userId == null || token == null) {
      _refreshTimer?.cancel();
      return;
    }

    if (provider.isTrackingEnabled) {
      // Toggle ON → full timeline from the active session. The 60s
      // polling loop keeps it fresh. With no resolvable session there is
      // nothing to poll, so stop the timer and tell the user why rather
      // than leaving an unexplained empty list.
      final sessionId = att.todaySessionId;
      if (sessionId == null) {
        _refreshTimer?.cancel();
        provider.reportNoTrackableSession();
        return;
      }
      provider.loadFromTodaysSession(
        token: token,
        sessionId: sessionId,
        userId: userId,
      );
      _startAutoRefresh();
    } else {
      // Toggle OFF → full punch-in/punch-out list for today via
      // /attendance/today (no live polling for closed punches). Pass the
      // in-memory + persisted local cache as a fallback so the screen still
      // shows the punch row when /attendance/today returns no lat/lng
      // (which is what was leaving Today's Timing stuck on "Waiting for
      // today's punch-in…" even after the user punched in).
      _refreshTimer?.cancel();
      provider.loadPunchPairForDate(
        token: token,
        userId: userId,
        localFallback: att.localPunchRecords,
      );
    }
  }

  /// Starts the 60-second auto-refresh loop. Cancels any existing timer so
  /// calling this repeatedly is idempotent. The loop uses
  /// `refreshTimelineSilently` so the UI doesn't flash a spinner every
  /// minute — the timeline list just grows in place as new pings land.
  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final att = context.read<AttendanceProvider>();
      final provider = context.read<LocationHistoryProvider>();
      final userId = _selectedEmployeeId ?? auth.currentUser?.id;
      final token = auth.token;
      final sessionId = att.todaySessionId;
      if (userId == null || token == null || sessionId == null) return;
      if (!provider.isTrackingEnabled) return;
      provider.refreshTimelineSilently(
        token: token,
        sessionId: sessionId,
        userId: userId,
      );
    });
  }

  /// Handler for the "Intermediate Tracking" switch. Flips the provider flag
  /// and re-triggers the data load pipeline so the visible data matches the
  /// new mode immediately.
  void _handleToggle(bool value) {
    final provider = context.read<LocationHistoryProvider>();
    provider.setLivePingsVisible(value);
    _loadForCurrentState();
    // Re-check GPS on every toggle, covering the case where the user turns
    // location on after landing on the screen.
    if (value) _checkLocationAvailability();
  }
}
