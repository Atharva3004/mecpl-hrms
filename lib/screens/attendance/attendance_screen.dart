import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/holiday_provider.dart';
import '../../models/attendance_model.dart';
import '../../widgets/attendance/punch_detail_card.dart';
import 'holiday_data.dart';
import 'holiday_calendar_screen.dart';
import 'attendance_map_screen.dart';
import 'attendance_day_detail_screen.dart';
import 'punch_view_screen.dart';
import 'punch_history_screen.dart';
import '../../services/location_permission_service.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  // My Attendance tab state
  String _dateFilter = 'Custom'; // 'Last 7 Days', 'This Month', 'Custom'
  String _statusFilter = 'All'; // 'All', 'Present', 'Absent', 'Half Day'
  final Set<int> _selectedRecords = {};
  int? _expandedIndex;
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();

    // Fetch real data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<AttendanceProvider>();
      provider.fetchHistory();
      provider.checkGeofence();

      // Fetch today's attendance and holidays
      final authProvider = context.read<AuthProvider>();
      final holidayProvider = context.read<HolidayProvider>();
      final token = authProvider.token;
      if (token != null) {
        // Geofence-gated bootstrap: reads /me/geofence, and only hits
        // /attendance/today when the user is a geofence-enabled employee.
        provider.bootstrapForGeofenceUser(
          token,
          userId: authProvider.currentUser?.id,
        );
        // Legacy attendance summary still runs for every user (status
        // badge, work hours).
        provider.fetchTodayAttendance(token);
        final year = DateTime.now().year.toString();
        holidayProvider.fetchHolidays(token: token, year: year);
        // Fetch calendar data for current month
        _fetchCalendarData();
      } else {
        // Not yet logged in — try the cached value so any earlier session
        // still hides the button correctly.
        provider.loadGeofenceConfig();
      }
    });
  }

  void _fetchCalendarData() {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    final monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final monthName = monthNames[_calendarMonth.month - 1];
    final year = _calendarMonth.year.toString();
    context.read<AttendanceProvider>().fetchCalendarData(
      token: token,
      month: monthName,
      year: year,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.white,
      appBar: _buildAppBar(context, isDark),
      body: _buildMyAttendanceTab(isDark),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, bool isDark) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.chevron_left, color: Colors.black87),
        onPressed: () {
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          } else {
            Provider.of<NavigationProvider>(context, listen: false).setIndex(0);
          }
        },
      ),
      title: Text(
        "My Attendance",
        style: GoogleFonts.poppins(
          color: Colors.black87,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
      ),
    );
  }

  // Compute filtered records for My Attendance tab
  List<AttendanceModel> _getFilteredRecords(AttendanceProvider provider) {
    // Date range
    final now = DateTime.now();
    DateTime startDate;
    if (_dateFilter == 'Last 7 Days') {
      startDate = now.subtract(const Duration(days: 7));
    } else if (_dateFilter == 'This Month') {
      startDate = DateTime(now.year, now.month, 1);
    } else {
      startDate = now.subtract(const Duration(days: 60));
    }
    final endDate = now;

    var records = provider.history.where((h) {
      return !h.date.isBefore(startDate) && !h.date.isAfter(endDate);
    }).toList();

    // Status filter
    if (_statusFilter != 'All') {
      records = records.where((h) {
        final s = h.status.toLowerCase();
        switch (_statusFilter) {
          case 'Present':
            return s.contains('present') || s == 'p';
          case 'Absent':
            return s.contains('absent') || s == 'a';
          case 'Half Day':
            return s.contains('half') || s == 'hd' || s == 'l/p' || s == 'p/l';
          default:
            return true;
        }
      }).toList();
    }

    records.sort((a, b) => b.date.compareTo(a.date));
    return records;
  }

  Widget _buildLegend() {
    final List<Map<String, dynamic>> legendItems = [
      {
        'label': 'P',
        'bg': const Color(0xFFE8F5E9),
        'text': const Color(0xFF2E7D32),
      },
      {
        'label': 'A',
        'bg': const Color(0xFFFFEBEE),
        'text': const Color(0xFFC62828),
      },
      {
        'label': 'HD',
        'bg': const Color(0xFFFFF3E0),
        'text': const Color(0xFFE65100),
      },
      {
        'label': 'WO',
        'bg': const Color(0xFFE3F2FD),
        'text': const Color(0xFF1565C0),
      },
      {
        'label': 'PH',
        'bg': const Color(0xFFFCE4EC),
        'text': const Color(0xFFAD1457),
      },
      {
        'label': 'L',
        'bg': const Color(0xFFF3E5F5),
        'text': const Color(0xFF6A1B9A),
      },
      {
        'label': 'L/P',
        'bg': const Color(0xFFE0F2F1),
        'text': const Color(0xFF00796B),
      },
    ];

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: legendItems.map((item) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: item['bg'] as Color,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              item['label'] as String,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: item['text'] as Color,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // Status badge info helper
  Map<String, dynamic> _getStatusBadge(String status) {
    final s = status.toLowerCase();
    if (s.contains('present') || s == 'p') {
      return {
        'label': 'P',
        'color': const Color(0xFF4CAF50),
        'bgColor': const Color(0xFFE8F5E9),
      };
    } else if (s.contains('absent') || s == 'a') {
      return {
        'label': 'A',
        'color': const Color(0xFFE53935),
        'bgColor': const Color(0xFFFFEBEE),
      };
    } else if (s.contains('half') || s == 'hd') {
      return {
        'label': 'HD',
        'color': const Color(0xFFFF9800),
        'bgColor': const Color(0xFFFFF3E0),
      };
    } else if (s.contains('weekly') || s == 'wo') {
      return {
        'label': 'WO',
        'color': const Color(0xFF1565C0),
        'bgColor': const Color(0xFFE3F2FD),
      };
    } else if (s.contains('leave') || s == 'l') {
      return {
        'label': 'L',
        'color': const Color(0xFF6A1B9A),
        'bgColor': const Color(0xFFF3E5F5),
      };
    } else if (s.contains('paid') || s == 'ph') {
      return {
        'label': 'PH',
        'color': const Color(0xFFAD1457),
        'bgColor': const Color(0xFFFCE4EC),
      };
    } else if (s.contains('late')) {
      return {
        'label': 'Late',
        'color': const Color(0xFF795548),
        'bgColor': const Color(0xFFEFEBE9),
      };
    } else if (s.contains('l/p') ||
        s == 'l/p' ||
        s.contains('p/l') ||
        s == 'p/l') {
      return {
        'label': 'L/P',
        'color': const Color(0xFF00796B),
        'bgColor': const Color(0xFFE0F2F1),
      };
    } else {
      return {
        'label': 'MIS',
        'color': const Color(0xFFFF9800),
        'bgColor': const Color(0xFFFFF3E0),
      };
    }
  }

  Widget _buildMyAttendanceTab(bool isDark) {
    final provider = context.watch<AttendanceProvider>();
    final filteredRecords = _getFilteredRecords(provider);

    // Count stats from full history (not filtered by status)
    final now = DateTime.now();
    DateTime startDate;
    if (_dateFilter == 'Last 7 Days') {
      startDate = now.subtract(const Duration(days: 7));
    } else if (_dateFilter == 'This Month') {
      startDate = DateTime(now.year, now.month, 1);
    } else {
      startDate = now.subtract(const Duration(days: 60));
    }
    final allInRange = provider.history.where((h) {
      return !h.date.isBefore(startDate) && !h.date.isAfter(now);
    }).toList();
    final presentCount = allInRange.where((h) {
      final s = h.status.toLowerCase();
      return s.contains('present') || s == 'p';
    }).length;
    final absentCount = allInRange.where((h) {
      final s = h.status.toLowerCase();
      return s.contains('absent') || s == 'a';
    }).length;
    final halfDayCount = allInRange.where((h) {
      final s = h.status.toLowerCase();
      return s.contains('half') || s == 'hd';
    }).length;

    return Column(
      children: [
        Expanded(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            children: [
              // Title
              // Text(
              //   "My Attendance",
              //   style: GoogleFonts.poppins(
              //     fontSize: 20,
              //     fontWeight: FontWeight.bold,
              //     color: Colors.black87,
              //   ),
              // ),
              // const SizedBox(height: 16),

              // Punch In/Out card
              _buildPunchCard(provider),
              const SizedBox(height: 12),

              // "View Live Session Timeline" entry intentionally hidden on
              // this screen — users access the live timeline from
              // Dashboard → Location History (toggle ON).
              const SizedBox(height: 16),

              // Date filter bar
              // _buildDateFilterBar(),
              const SizedBox(height: 16),

              // Legend Display
              _buildLegend(),
              const SizedBox(height: 16),

              // Calendar
              _buildCalendar(),
              const SizedBox(height: 20),

              // Upcoming Holidays
              _buildUpcomingHolidays(),
              const SizedBox(height: 16),

              // Status filter chips
              // _buildStatusFilterChips(presentCount, absentCount, halfDayCount),
              const SizedBox(height: 16),

              // Table header
              // _buildTableHeader(),
              const SizedBox(height: 4),

              // Attendance rows
              if (provider.isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (filteredRecords.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text(
                      "No records found",
                      style: GoogleFonts.poppins(
                        color: AppColors.textTertiary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                )
              else
                ...List.generate(filteredRecords.length, (index) {
                  return _buildAttendanceRow(filteredRecords[index], index);
                }),
              const SizedBox(height: 20),
            ],
          ),
        ),
        // Regularize button
        // _buildRegularizeButton(),
      ],
    );
  }

  Widget _buildPunchCard(AttendanceProvider provider) {
    final isClockedIn = provider.isClockedIn;
    // Hide the punch button when the user has no geofence flag OR has
    // already completed today's cycle (backend enforces one per day).
    final canPunch =
        provider.isGeofenceAttendanceEnabled && !provider.todayCycleCompleted;
    final todayAtt = provider.todayAttendance;

    // Punch times on the card:
    // Punch times on the card are now driven by the legacy biometric
    // endpoint `/today-employee-attendance` as the authoritative source
    // (it aggregates biometric swipes + any session-based punches on the
    // server side). Session-based `lastPunchInDisplay` / `lastPunchOutDisplay`
    // are kept as a fallback so the card updates immediately after an
    // in-app punch, before the biometric system re-aggregates on the server.
    final isGeofence = provider.isGeofenceAttendanceEnabled;
    final punchInTime =
        todayAtt?.formattedFirstIn ?? provider.lastPunchInDisplay ?? "--:--";
    final punchOutTime =
        todayAtt?.formattedLastOut ?? provider.lastPunchOutDisplay ?? "--:--";
    final todayStatus = todayAtt?.status.toUpperCase() ?? '';
    // Work hours: prefer the biometric endpoint's aggregate so the number
    // matches what HR sees. Session-based total is a fallback for the
    // immediate post-punch case (biometric hasn't resynced yet).
    final workHours =
        todayAtt?.totalWorkHours ??
        (isGeofence ? provider.todayWorkHoursDisplay : null) ??
        '--';

    // Status badge colors
    Color statusBadgeColor;
    Color statusBadgeBg;
    String statusText;
    switch (todayStatus) {
      case 'P':
        statusBadgeColor = const Color(0xFF4CAF50);
        statusBadgeBg = Colors.white.withOpacity(0.2);
        statusText = 'Present';
        break;
      case 'A':
        statusBadgeColor = const Color.fromARGB(255, 255, 255, 255);
        statusBadgeBg = const Color.fromARGB(255, 239, 106, 106);
        statusText = 'Absent';
        break;
      case 'HD':
        statusBadgeColor = const Color(0xFFFFD740);
        statusBadgeBg = Colors.white.withOpacity(0.2);
        statusText = 'Half Day';
        break;
      default:
        statusBadgeColor = Colors.white70;
        statusBadgeBg = Colors.white.withOpacity(0.1);
        statusText = todayStatus.isNotEmpty ? todayStatus : '--';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Punch In Out",
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            // Geofence Status Badge
            Builder(
              builder: (context) {
                final geofenceStatus = provider.geofenceStatus;
                final isInside = geofenceStatus['isInside'] ?? false;
                final distance = geofenceStatus['distance'] ?? 0;

                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isInside
                        ? const Color(0xFFE8F5E9)
                        : const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isInside
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFE53935),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isInside ? Icons.check_circle : Icons.location_off,
                        color: isInside
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFFE53935),
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isInside
                            ? 'Inside Office'
                            : '${distance.toInt()}m away',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isInside
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFE53935),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color.fromARGB(255, 108, 99, 255),
                Color.fromARGB(255, 140, 130, 255),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color.fromARGB(
                  255,
                  108,
                  99,
                  255,
                ).withOpacity(0.35),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: GestureDetector(
            onTap: (provider.isLoading || !canPunch)
                ? null
                : () async {
                    // 1. Show location permission dialog FIRST
                    print('📍 Showing location permission dialog...');
                    final hasPermission =
                        await LocationPermissionService.showPermissionDialog(
                          context,
                        );

                    // User denied - just close dialog and return
                    if (!hasPermission) {
                      print('❌ User denied location permission');
                      return;
                    }

                    print('✅ User allowed location permission');

                    // 2. Open camera for selfie
                    print('📸 Opening camera...');
                    String? selfiePath = await provider.capturePunchSelfie();
                    print('📸 Selfie path: $selfiePath');

                    // User cancelled or no selfie
                    if (selfiePath == null) {
                      print('❌ User cancelled camera');
                      return;
                    }

                    // 2. Show loading dialog
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    );

                    // 3. Punch with location
                    print('🔄 Starting punch process...');
                    final auth = context.read<AuthProvider>();
                    final userId = auth.currentUser?.id ?? '';
                    final token = auth.token ?? '';
                    bool success;
                    if (isClockedIn) {
                      success = await provider.punchOutWithLocation(
                        time: DateFormat('hh:mm a').format(DateTime.now()),
                        token: token,
                      );
                    } else {
                      success = await provider.punchInWithLocation(
                        time: DateFormat('hh:mm a').format(DateTime.now()),
                        location: "Office",
                        userId: userId,
                        token: token,
                      );
                    }
                    print('✅ Punch result: $success');

                    // 4. Hide loading
                    if (context.mounted) {
                      Navigator.pop(context);
                    }

                    // 5. Handle result
                    if (context.mounted) {
                      // Always show View screen if we have local record
                      if (provider.localPunchRecords.isNotEmpty) {
                        final lastPunch = provider.localPunchRecords.last;
                        print('📊 Punch record: ${lastPunch.coordinates}');

                        // Refresh today attendance in background
                        final token = context.read<AuthProvider>().token;
                        if (token != null) {
                          provider.fetchTodayAttendance(token);
                        }

                        // Show success or warning message
                        if (success) {
                          print('🎉 Punch successful (API + Local)');
                          // Non-blocking out-of-fence warning (spec §5.2).
                          final g = provider.lastPunchGeofence;
                          if (g != null && g['inside'] == false) {
                            final distance =
                                (g['distanceM'] as num?)?.toInt() ?? 0;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Punched ${distance}m outside fence — flagged for review',
                                ),
                                backgroundColor: Colors.orange,
                                duration: const Duration(seconds: 4),
                              ),
                            );
                          }
                        } else if (provider.sessionConflict != null) {
                          final data =
                              provider.sessionConflict!['data']
                                  as Map<String, dynamic>? ??
                              provider.sessionConflict!;
                          final openId = data['session_id'];
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                provider.errorMessage ??
                                    'You already have an open session (id $openId). Punch out first.',
                              ),
                              backgroundColor: Colors.red,
                              duration: const Duration(seconds: 4),
                            ),
                          );
                          provider.clearSessionConflict();
                        } else {
                          print('⚠️ Punch saved locally (API failed)');
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                provider.errorMessage ??
                                    'Saved locally. API sync failed.',
                              ),
                              backgroundColor: Colors.orange,
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }

                        // Navigate to View screen
                        if (context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  PunchViewScreen(punchRecord: lastPunch),
                            ),
                          );
                        }
                      } else {
                        print('⚠️ No punch records found');
                      }
                    }
                  },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status & Work Hours row
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 6, right: 6),
                  child: Row(
                    children: [
                      // Today's status badge
                      if (punchInTime != "--:--")
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: statusBadgeBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: statusBadgeColor.withOpacity(0.5),
                            ),
                          ),
                          child: Text(
                            statusText,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: statusBadgeColor,
                            ),
                          ),
                        ),
                      const Spacer(),
                      // Total work hours
                      Icon(Iconsax.timer_1, size: 14, color: Colors.white70),
                      const SizedBox(width: 4),
                      Text(
                        '$workHours hrs',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Punch In / Punch Out / Button in one row
                Row(
                  children: [
                    // Punch In — flexible half. Both halves share the row
                    // width evenly, so neither label wraps on a narrow screen
                    // or at a large system font scale.
                    Expanded(
                      child: Row(
                        children: [
                          Icon(Iconsax.clock, size: 22, color: Colors.white70),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Punch In",
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  punchInTime,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Punch Out — flexible half.
                    Expanded(
                      child: Row(
                        children: [
                          Icon(Iconsax.clock, size: 22, color: Colors.white70),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Punch Out",
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  punchOutTime,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Door icon button — hidden when:
                    //   - geofence_attendance == "No", OR
                    //   - today's cycle is already complete (then we show
                    //     a small "Done" chip in its place).
                    if (canPunch)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.25),
                          ),
                        ),
                        child: provider.isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Icon(
                                isClockedIn ? Iconsax.logout : Iconsax.login,
                                size: 24,
                                color: Colors.white,
                              ),
                      )
                    else if (provider.isGeofenceAttendanceEnabled &&
                        provider.todayCycleCompleted)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.check_circle,
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Done',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPunchTimeline(AttendanceProvider provider) {
    final records = provider.localPunchRecords;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Row(
          children: [
            Icon(Icons.history, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              'Today\'s Punch History',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const Spacer(),
            TextButton(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PunchHistoryScreen()),
                );
              },
              child: Text(
                'View All >',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Punch Records List
        if (records.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 28.0),
            child: Text(
              'No punches recorded yet today.',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[500]),
            ),
          )
        else
          ...records.reversed.map((record) {
            return PunchDetailCard(record: record);
          }).toList(),
      ],
    );
  }

  Widget _buildUpcomingHolidays() {
    final holidayProvider = context.watch<HolidayProvider>();
    final upcoming = holidayProvider.upcomingHolidays;
    final grouped = groupHolidaysByMonth(upcoming);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Text(
              'Upcoming Holidays',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const HolidayCalendarScreen(),
                  ),
                );
              },
              child: Text(
                'View',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF3949AB),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Month grouped cards in 2-column layout
        ...grouped.entries.map((entry) {
          final monthName = entry.value.first.monthName;
          final monthHolidays = entry.value;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 2-column row of cards per month
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left column
                  Expanded(
                    child: _buildMonthHolidayCard(
                      monthName,
                      monthHolidays.length > 0
                          ? monthHolidays.sublist(
                              0,
                              (monthHolidays.length / 2).ceil(),
                            )
                          : [],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Right column
                  Expanded(
                    child:
                        monthHolidays.length > (monthHolidays.length / 2).ceil()
                        ? _buildMonthHolidayCard(
                            '',
                            monthHolidays.sublist(
                              (monthHolidays.length / 2).ceil(),
                            ),
                          )
                        : const SizedBox(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildMonthHolidayCard(String monthLabel, List<Holiday> holidays) {
    if (holidays.isEmpty) return const SizedBox();
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (monthLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                monthLabel,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  // color: const Color(0xFFFF7043),
                  color: Color.fromARGB(255, 100, 112, 243),
                ),
              ),
            ),
          ...holidays.map(
            (h) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.grey[100],

                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      // color: Color(0xFFFF7043),
                      color: Color.fromARGB(255, 100, 112, 243),

                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        h.day.toString().padLeft(2, '0'),
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: const Color.fromARGB(255, 255, 255, 255),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          h.name,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                h.dayName,
                                style: GoogleFonts.poppins(
                                  fontSize: 9,
                                  color: Colors.grey.shade600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (h.isOptional) ...[
                              const SizedBox(width: 3),
                              Text(
                                'Optional',
                                style: GoogleFonts.poppins(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  // color: const Color(0xFFFF7043),
                                  color: Color.fromARGB(255, 100, 112, 243),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final year = _calendarMonth.year;
    final month = _calendarMonth.month;
    // `watch`, not `read` — when the user navigates to a different month and
    // `_fetchCalendarData()` updates `provider.calendarData`, we need this
    // widget to rebuild so status colours appear. `read` is one-shot and
    // misses post-fetch updates, which is why past months previously
    // rendered without colours.
    final provider = context.watch<AttendanceProvider>();

    final firstDayOfMonth = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final startWeekday = firstDayOfMonth.weekday % 7; // Sun=0

    final monthName = DateFormat('MMM yyyy').format(_calendarMonth);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        children: [
          // Header: Month Year + navigation
          Row(
            children: [
              GestureDetector(
                onTap: () async {
                  int selectedYear = _calendarMonth.year;
                  final picked = await showDialog<DateTime>(
                    context: context,
                    builder: (ctx) {
                      return StatefulBuilder(
                        builder: (ctx, setDialogState) {
                          final months = [
                            'Jan',
                            'Feb',
                            'Mar',
                            'Apr',
                            'May',
                            'Jun',
                            'Jul',
                            'Aug',
                            'Sep',
                            'Oct',
                            'Nov',
                            'Dec',
                          ];
                          return Dialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Year selector
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          Icons.chevron_left,
                                          color:
                                              selectedYear <=
                                                  AppConstants.appStartDate.year
                                              ? const Color(0xFFBDBDBD)
                                              : const Color(0xFF3949AB),
                                        ),
                                        // Block stepping below the app start year.
                                        onPressed:
                                            selectedYear <=
                                                AppConstants.appStartDate.year
                                            ? null
                                            : () => setDialogState(
                                                () => selectedYear--,
                                              ),
                                      ),
                                      Text(
                                        '$selectedYear',
                                        style: GoogleFonts.poppins(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.chevron_right,
                                          color: Color(0xFF3949AB),
                                        ),
                                        onPressed: () => setDialogState(
                                          () => selectedYear++,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  // Month grid 4x3. Months before
                                  // AppConstants.appStartDate (only matters
                                  // inside the start year) are greyed out
                                  // and not selectable.
                                  GridView.count(
                                    shrinkWrap: true,
                                    crossAxisCount: 4,
                                    mainAxisSpacing: 8,
                                    crossAxisSpacing: 8,
                                    childAspectRatio: 1.6,
                                    children: List.generate(12, (i) {
                                      final isSelected =
                                          _calendarMonth.year == selectedYear &&
                                          _calendarMonth.month == i + 1;
                                      final isBeforeStart =
                                          selectedYear ==
                                              AppConstants.appStartDate.year &&
                                          (i + 1) <
                                              AppConstants.appStartDate.month;
                                      return GestureDetector(
                                        onTap: isBeforeStart
                                            ? null
                                            : () => Navigator.pop(
                                                ctx,
                                                DateTime(selectedYear, i + 1),
                                              ),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? const Color(0xFF3F51B5)
                                                : isBeforeStart
                                                ? const Color(0xFFEEEEEE)
                                                : const Color(0xFFF5F5F5),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Center(
                                            child: Text(
                                              months[i],
                                              style: GoogleFonts.poppins(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: isSelected
                                                    ? Colors.white
                                                    : isBeforeStart
                                                    ? const Color(0xFFBDBDBD)
                                                    : Colors.black87,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                  if (picked != null) {
                    setState(() {
                      _calendarMonth = picked;
                      _fetchCalendarData();
                    });
                  }
                },
                child: Row(
                  children: [
                    Text(
                      monthName,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.keyboard_arrow_down,
                      size: 20,
                      color: Colors.black87,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // ◀ Previous month — disabled when already on the app's earliest
              // month (`AppConstants.appStartDate`'s month). The HRMS has no
              // data before that date, so navigating further back is pointless.
              Builder(
                builder: (_) {
                  final start = AppConstants.appStartDate;
                  final atFloor =
                      _calendarMonth.year == start.year &&
                      _calendarMonth.month == start.month;
                  return GestureDetector(
                    onTap: atFloor
                        ? null
                        : () {
                            setState(() {
                              _calendarMonth = DateTime(year, month - 1);
                              _fetchCalendarData();
                            });
                          },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.chevron_left,
                        size: 24,
                        color: atFloor
                            ? const Color(0xFFBDBDBD)
                            : const Color(0xFF3949AB),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _calendarMonth = DateTime(year, month + 1);
                    _fetchCalendarData();
                  });
                },
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.chevron_right,
                    size: 24,
                    color: Color(0xFF3949AB),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFE0E0E0)),
          const SizedBox(height: 12),

          // Day-of-week headers
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
                .map(
                  (d) => SizedBox(
                    width: 36,
                    child: Center(
                      child: Text(
                        d,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),

          // Date grid
          ...List.generate(6, (weekIndex) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(7, (dayIndex) {
                  final dayNum = weekIndex * 7 + dayIndex - startWeekday + 1;
                  if (dayNum < 1 || dayNum > daysInMonth) {
                    return const SizedBox(width: 36, height: 36);
                  }

                  final date = DateTime(year, month, dayNum);
                  final isToday = date == today;
                  final isFuture = date.isAfter(today);
                  final isSunday = dayIndex == 0;

                  // Look up attendance status from calendar API data
                  final dateKey =
                      '${year.toString()}-${month.toString().padLeft(2, '0')}-${dayNum.toString().padLeft(2, '0')}';
                  final calData = provider.calendarData[dateKey];
                  final status =
                      calData?['status']?.toString().toLowerCase() ?? '';
                  final isLate = (calData?['late'] ?? 0) == 1;
                  final isAbsent = status == 'a';
                  final isHalfDay = status == 'hd';
                  final isPresent = status == 'p';
                  final isWeeklyOff = status == 'wo';
                  final isLeave = status == 'l';
                  final isPaidHoliday = status == 'ph';

                  Color bgColor = Colors.transparent;
                  Color textColor = Colors.black87;

                  final isUpcomingHoliday = context
                      .read<HolidayProvider>()
                      .holidays
                      .any(
                        (h) =>
                            !h.isOptional &&
                            h.date.year == year &&
                            h.date.month == month &&
                            h.date.day == dayNum,
                      );

                  if (isToday) {
                    bgColor = const Color(0xFF3F51B5);
                    textColor = Colors.white;
                  } else if (isAbsent) {
                    bgColor = const Color(0xFFFFEBEE);
                    textColor = const Color(0xFFC62828);
                  } else if (isHalfDay) {
                    bgColor = const Color(0xFFFFF3E0);
                    textColor = const Color(0xFFE65100);
                  } else if (isPresent && isLate) {
                    bgColor = const Color(0xFFE8F5E9);
                    textColor = const Color(0xFF795548);
                  } else if (isPresent) {
                    bgColor = const Color(0xFFE8F5E9);
                    textColor = const Color(0xFF2E7D32);
                  } else if (isWeeklyOff) {
                    bgColor = const Color(0xFFE3F2FD);
                    textColor = const Color(0xFF1565C0);
                  } else if (isLeave) {
                    bgColor = const Color(0xFFF3E5F5);
                    textColor = const Color(0xFF6A1B9A);
                  } else if (isPaidHoliday) {
                    // API explicitly says paid holiday
                    bgColor = const Color(0xFFFCE4EC);
                    textColor = const Color(0xFFAD1457);
                  } else if (isUpcomingHoliday) {
                    // Holiday from the holiday calendar
                    bgColor = const Color(0xFFFFEBEE);
                    textColor = const Color(0xFFC62828);
                  } else if (isFuture) {
                    textColor = Colors.grey.shade400;
                  } else if (isSunday) {
                    bgColor = const Color(0xFFEEEEEE);
                    textColor = const Color(0xFF9E9E9E);
                  }

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      // Push the per-day detail screen. Future dates still
                      // navigate — the detail screen explains the empty state.
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AttendanceDayDetailScreen(
                              date: date,
                              data: calData,
                            ),
                          ),
                        );
                      },
                      borderRadius: isToday ? null : BorderRadius.circular(4),
                      customBorder: isToday ? const CircleBorder() : null,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: bgColor,
                          shape: isToday ? BoxShape.circle : BoxShape.rectangle,
                          borderRadius: isToday
                              ? null
                              : BorderRadius.circular(4),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              dayNum.toString(),
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: isToday
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: textColor,
                                height: 1.0,
                              ),
                            ),
                            if (isUpcomingHoliday || isPaidHoliday) ...[
                              const SizedBox(height: 2),
                              Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: isPaidHoliday
                                      ? const Color(0xFFAD1457)
                                      : const Color(0xFFD32F2F),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
        ],
      ),
    );
  }

  // Widget _buildDateFilterBar() {
  //   final filters = ['Last 7 Days', 'This Month', 'Custom'];
  //   return Row(
  //     children: filters.map((filter) {
  //       final isSelected = _dateFilter == filter;
  //       return Expanded(
  //         child: GestureDetector(
  //           onTap: () => setState(() => _dateFilter = filter),
  //           child: Container(
  //             margin: EdgeInsets.only(right: filter != filters.last ? 8 : 0),
  //             padding: const EdgeInsets.symmetric(vertical: 10),
  //             decoration: BoxDecoration(
  //               color: isSelected
  //                   ? const Color.fromARGB(255, 92, 92, 233)
  //                   : Colors.white,
  //               borderRadius: BorderRadius.circular(24),
  //               border: Border.all(
  //                 color: isSelected
  //                     ? const Color.fromARGB(255, 92, 92, 233)
  //                     : const Color(0xFFE0E0E0),
  //               ),
  //             ),
  //             child: Center(
  //               child: Text(
  //                 filter,
  //                 style: GoogleFonts.poppins(
  //                   fontSize: 12,
  //                   fontWeight: FontWeight.w600,
  //                   color: isSelected ? Colors.white : Colors.black87,
  //                 ),
  //               ),
  //             ),
  //           ),
  //         ),
  //       );
  //     }).toList(),
  //   );
  // }

  // Widget _buildStatusFilterChips(
  //   int presentCount,
  //   int absentCount,
  //   int halfDayCount,
  // ) {
  //   final chips = [
  //     {'label': 'All', 'count': null},
  //     {'label': 'Present', 'count': presentCount},
  //     {'label': 'Absent', 'count': absentCount},
  //     {'label': 'Half Day', 'count': halfDayCount},
  //   ];

  //   return SingleChildScrollView(
  //     scrollDirection: Axis.horizontal,
  //     child: Row(
  //       children: chips.map((chip) {
  //         final label = chip['label'] as String;
  //         final count = chip['count'] as int?;
  //         final isSelected = _statusFilter == label;

  //         return GestureDetector(
  //           onTap: () => setState(() => _statusFilter = label),
  //           child: Container(
  //             margin: const EdgeInsets.only(right: 8),
  //             padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
  //             decoration: BoxDecoration(
  //               color: isSelected
  //                   ? const Color.fromARGB(255, 98, 98, 246)
  //                   : Colors.white,
  //               borderRadius: BorderRadius.circular(20),
  //               border: Border.all(
  //                 color: isSelected
  //                     ? const Color.fromARGB(255, 98, 98, 246)
  //                     : const Color(0xFFE0E0E0),
  //               ),
  //             ),
  //             child: Row(
  //               mainAxisSize: MainAxisSize.min,
  //               children: [
  //                 Text(
  //                   label,
  //                   style: GoogleFonts.poppins(
  //                     fontSize: 12,
  //                     fontWeight: FontWeight.w600,
  //                     color: isSelected ? Colors.white : Colors.black87,
  //                   ),
  //                 ),
  //                 if (count != null && count > 0) ...[
  //                   const SizedBox(width: 6),
  //                   Container(
  //                     padding: const EdgeInsets.symmetric(
  //                       horizontal: 8,
  //                       vertical: 2,
  //                     ),
  //                     decoration: BoxDecoration(
  //                       color: isSelected
  //                           ? Colors.white.withOpacity(0.2)
  //                           : label == 'Present'
  //                           ? const Color(0xFF4CAF50)
  //                           : label == 'Absent'
  //                           ? const Color(0xFFE53935)
  //                           : const Color(0xFFFF9800),
  //                       borderRadius: BorderRadius.circular(10),
  //                     ),
  //                     child: Text(
  //                       count.toString(),
  //                       style: GoogleFonts.poppins(
  //                         fontSize: 11,
  //                         fontWeight: FontWeight.bold,
  //                         color: Colors.white,
  //                       ),
  //                     ),
  //                   ),
  //                 ],
  //               ],
  //             ),
  //           ),
  //         );
  //       }).toList(),
  //     ),
  //   );
  // }

  // Widget _buildTableHeader() {
  //   return Container(
  //     padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  //     decoration: BoxDecoration(
  //       // color: const Color.fromARGB(255, 108, 99, 255),
  //       color: const Color.fromARGB(238, 228, 135, 13),
  //       borderRadius: BorderRadius.circular(24),
  //     ),
  //     child: Row(
  //       children: [
  //         Expanded(
  //           flex: 3,
  //           child: Text(
  //             "Date",
  //             style: GoogleFonts.poppins(
  //               fontSize: 13,
  //               fontWeight: FontWeight.w600,
  //               color: Colors.white,
  //             ),
  //           ),
  //         ),
  //         Expanded(
  //           flex: 2,
  //           child: Text(
  //             "Work Hours",
  //             style: GoogleFonts.poppins(
  //               fontSize: 13,
  //               fontWeight: FontWeight.w600,
  //               color: Colors.white,
  //             ),
  //           ),
  //         ),
  //         Expanded(
  //           flex: 2,
  //           child: Text(
  //             "Status",
  //             style: GoogleFonts.poppins(
  //               fontSize: 13,
  //               fontWeight: FontWeight.w600,
  //               color: Colors.white,
  //             ),
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  Widget _buildAttendanceRow(AttendanceModel item, int index) {
    final badge = _getStatusBadge(item.status);
    final isSelected = _selectedRecords.contains(index);
    final isExpanded = _expandedIndex == index;
    final workHours = item.workingHours ?? 'NA';
    final isApproved =
        item.status.toLowerCase().contains('approved') ||
        item.status.toLowerCase().contains('regularized');

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            child: Row(
              children: [
                // Checkbox
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedRecords.add(index);
                        } else {
                          _selectedRecords.remove(index);
                        }
                      });
                    },
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    side: BorderSide(color: Colors.grey.shade400),
                    activeColor: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 8),

                // Date
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('dd MMM yyyy').format(item.date),
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                      if (isApproved)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFF4CAF50)),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            "Approved",
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              color: const Color(0xFF4CAF50),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Work Hours
                Expanded(
                  flex: 2,
                  child: Text(
                    workHours,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ),

                // Status badge
                Expanded(
                  flex: 1,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: (badge['bgColor'] as Color),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badge['label'] as String,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: badge['color'] as Color,
                      ),
                    ),
                  ),
                ),

                // Expand chevron
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _expandedIndex = isExpanded ? null : index;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.grey,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Expanded details
          if (isExpanded)
            Container(
              padding: const EdgeInsets.fromLTRB(40, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Iconsax.login,
                              size: 14,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "In: ${item.checkIn ?? '--:--'}",
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(width: 20),
                            const Icon(
                              Iconsax.logout,
                              size: 14,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "Out: ${item.checkOut ?? '--:--'}",
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // Widget _buildRegularizeButton() {
  //   return Container(
  //     width: double.infinity,
  //     padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
  //     color: Colors.white,
  //     child: ElevatedButton(
  //       onPressed: _selectedRecords.isNotEmpty ? () {} : null,
  //       style: ElevatedButton.styleFrom(
  //         backgroundColor: const Color.fromARGB(255, 108, 99, 255),
  //         foregroundColor: Colors.white,
  //         disabledBackgroundColor: const Color.fromARGB(255, 180, 175, 255),
  //         disabledForegroundColor: Colors.white70,
  //         elevation: 0,
  //         shape: RoundedRectangleBorder(
  //           borderRadius: BorderRadius.circular(24),
  //         ),
  //         padding: const EdgeInsets.symmetric(vertical: 14),
  //       ),
  //       child: Text(
  //         "Regularize",
  //         style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
  //       ),
  //     ),
  //  );
  // }
}
