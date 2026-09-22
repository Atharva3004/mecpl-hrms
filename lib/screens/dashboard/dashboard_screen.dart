import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/permission_provider.dart';
import 'package:mecpl_flutter/providers/dashboard_provider.dart';
import 'package:mecpl_flutter/models/role_model.dart';
import '../notifications/notification_screen.dart';
import '../attendance/attendance_screen.dart';
import '../attendance/attendance_map_screen.dart';
import '../attendance/team_overview_screen.dart';
import '../attendance/my_attendance_detail_screen.dart';
import '../attendance/punch_history_screen.dart';
import '../leave/leave_screen.dart';
import '../leave/employee_leave_summary_screen.dart';
import '../leave/leave_history_screen.dart';
import '../leave/leave_approval_screen.dart';
import '../employee_details/employee_details_screen.dart';
import '../onboarding/employee_onboarding_approval_screen.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mecpl_flutter/screens/dashboard/celebrations_screen.dart';
import '../payroll/download_slips_screen.dart';
import '../payroll/employee_payslip_screen.dart';
import '../payroll/branch_payroll_approval_screen.dart';
import '../attendance/regularization_approval_screen.dart';
import '../attendance/regularization_list_screen.dart';
import '../attendance/punch_view_screen.dart';
import '../../services/location_permission_service.dart';
import '../tracking/location_history_screen.dart';
import '../tracking/team_location_map_screen.dart';
import '../projects/project_details_screen.dart';
import '../roadmap/roadmap_screen.dart';
import '../pre_recruitment/pre_recruitment_screen.dart';
import '../requisition/requisition_summary_screen.dart';
import '../branch_staff/branch_staff_screen.dart';
import '../petty_contractors/petty_contractors_screen.dart';

class DashboardScreen extends StatefulWidget {
  final GlobalKey<ScaffoldState>? scaffoldKey;

  const DashboardScreen({super.key, this.scaffoldKey});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _refreshKey = 0;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  void _fetchData() {
    if (mounted) {
      setState(() {
        _refreshKey++;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.token != null) {
        final dashboardProvider = context.read<DashboardProvider>();
        // Branch Payroll Approval is available to admins and managers — only
        // fetch its pending count for those roles.
        final role = auth.currentUser?.role;
        final canBranchPayroll =
            role == UserRole.admin || role == UserRole.manager;
        dashboardProvider.fetchRecentActivity(
          token: auth.token!,
          empId: auth.currentUser?.id ?? '',
          role: role,
          canBranchPayroll: canBranchPayroll,
        );
        dashboardProvider.fetchBirthdays(auth.token!);

        // Bell-icon badge count from the in-app notifications API. Cheap —
        // returns just the integer, not the full list.
        context.read<NotificationProvider>().refreshUnreadCount(
          authToken: auth.token!,
        );

        // Fetch today attendance for punch card
        final attendanceProvider = context.read<AttendanceProvider>();
        // Geofence-gated bootstrap: reads /me/geofence, and only hits
        // /attendance/today when the user is a geofence-enabled employee.
        attendanceProvider.bootstrapForGeofenceUser(
          auth.token!,
          userId: auth.currentUser?.id,
        );
        // Legacy attendance summary still runs for every user.
        attendanceProvider.fetchTodayAttendance(auth.token!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerColor = isDark ? AppColors.primaryDark : AppColors.primary;

    return Consumer<AuthProvider>(
      builder: (context, auth, child) {
        return Scaffold(
          backgroundColor: isDark
              ? AppColors.darkBackground
              : AppColors.background,
          body: RefreshIndicator(
            onRefresh: () async {
              _fetchData();
            },
            child: SafeArea(
              top: false,
              bottom: false,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // Custom App Bar
                  SliverAppBar(
                    pinned: true,
                    floating: false,
                    backgroundColor: isDark
                        ? AppColors.darkBackground
                        : Colors.white,
                    elevation: 0,
                    automaticallyImplyLeading: false,
                    titleSpacing: 0,
                    toolbarHeight: 50,
                    title: _buildNewHeader(
                      context,
                      isDark,
                      onMenuTap: widget.scaffoldKey != null
                          ? () => widget.scaffoldKey!.currentState?.openDrawer()
                          : null,
                    ),
                  ),

                  // Top Curved Section with Punch Card
                  SliverToBoxAdapter(
                    child: _buildTopSection(headerColor, isDark),
                  ),

                  // Quick Access Section
                  SliverToBoxAdapter(child: _buildQuickAccessSection(isDark)),

                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNewHeader(
    BuildContext context,
    bool isDark, {
    VoidCallback? onMenuTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.paddingMD),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (onMenuTap != null)
                IconButton(
                  onPressed: onMenuTap,
                  icon: Icon(
                    Icons.menu,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                    size: AppConstants.iconMD,
                  ),
                ),
            ],
          ),
          Image.asset('assets/Mecpl_logo.png', height: 36),
          Consumer<NotificationProvider>(
            builder: (context, notif, _) {
              final count = notif.unreadCount;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    onPressed: () {
                      // Don't pre-clear the badge — NotificationScreen will
                      // refresh and the per-tap mark-as-read calls drive the
                      // count down accurately as the user reads each item.
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NotificationScreen(),
                        ),
                      );
                    },
                    icon: Icon(
                      Iconsax.notification,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                  if (count > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          count > 9 ? '9+' : '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) {
      return 'Good Morning ☀️';
    } else if (hour >= 12 && hour < 17) {
      return 'Good Afternoon 🌤️';
    } else if (hour >= 17 && hour < 21) {
      return 'Good Evening 🌇';
    } else {
      return 'Good Night 🌙';
    }
  }

  Widget _buildTopSection(Color headerColor, bool isDark) {
    // The director has no biometric/geofence punch flow. Instead of the
    // overlapping punch card, the director gets a compact, non-overlapping
    // executive snapshot rendered in normal flow below the greeting header.
    final isDirector =
        context.read<AuthProvider>().currentUser?.role == UserRole.director;
    if (isDirector) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.paddingMD,
          6,
          AppConstants.paddingMD,
          4,
        ),
        child: _buildDirectorOverviewCard(),
      );
    }
    return Stack(
      children: [
        // Colored header behind the card — fixed height, curved bottom-left.
        // Positioned (not in normal flow) so the Stack's height is driven by
        // the card below. That lets the section grow with the card's real
        // height instead of clipping it under the next section on any device.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 100,
            width: double.infinity,
            decoration: BoxDecoration(
              color: headerColor,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(50),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(
                left: AppConstants.paddingLG,
                top: 10,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getGreeting(),
                    style: AppTextStyles.titleMedium.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  // Map icon in the header is geofence-only — employees
                  // without `geofence_attendance: "Yes"` don't use the
                  // session-based punch flow and shouldn't see the live
                  // map shortcut.
                  Consumer<AttendanceProvider>(
                    builder: (context, att, _) {
                      if (!att.isGeofenceAttendanceEnabled) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(
                          right: AppConstants.paddingLG,
                        ),
                        child: Transform.translate(
                          offset: const Offset(0, -9),
                          child: IconButton(
                            icon: const Icon(
                              Icons.location_pin,
                              color: Color.fromARGB(255, 235, 230, 230),
                              size: 25,
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AttendanceMapScreen(),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        // Punch card in normal flow, pushed down to overlap the header. As
        // the non-positioned child it defines the Stack's height, so the
        // following section can never paint over it on any screen size.
        Padding(
          padding: const EdgeInsets.only(
            top: 40,
            left: AppConstants.paddingMD,
            right: AppConstants.paddingMD,
            bottom: 12,
          ),
          child: Consumer<AttendanceProvider>(
            builder: (context, attProvider, _) {
              final isClockedIn = attProvider.isClockedIn;
              // Hide the arrow button when the user has no geofence flag OR
              // has already completed today's cycle.
              final canPunch =
                  attProvider.isGeofenceAttendanceEnabled &&
                  !attProvider.todayCycleCompleted;
              final todayAtt = attProvider.todayAttendance;
              // Punch times on the card are now driven by the biometric
              // `/today-employee-attendance` endpoint as the authoritative
              // source for both user types. Session-based values are kept
              // as a fallback so the card updates instantly after an in-app
              // punch, before the biometric backend re-aggregates.
              final isGeofence = attProvider.isGeofenceAttendanceEnabled;
              final punchInTime =
                  todayAtt?.formattedFirstIn ??
                  attProvider.lastPunchInDisplay ??
                  '--:--';
              final punchOutTime =
                  todayAtt?.formattedLastOut ??
                  attProvider.lastPunchOutDisplay ??
                  '--:--';
              final todayStatus = todayAtt?.status.toUpperCase() ?? '';
              // Work hours: prefer biometric aggregate so the card matches
              // what HR sees. Session total is a fallback until biometric
              // resyncs.
              final workHours =
                  todayAtt?.totalWorkHours ??
                  (isGeofence ? attProvider.todayWorkHoursDisplay : null) ??
                  '--';

              // Status badge colors
              Color statusBadgeColor;
              Color statusBadgeBg;
              String statusText;
              switch (todayStatus) {
                case 'P':
                  statusBadgeColor = const Color(0xFF2E7D32);
                  statusBadgeBg = const Color(0xFFE8F5E9);
                  statusText = 'Present';
                  break;
                case 'A':
                  statusBadgeColor = const Color(0xFFC62828);
                  statusBadgeBg = const Color(0xFFFFEBEE);
                  statusText = 'Absent';
                  break;
                case 'HD':
                  statusBadgeColor = const Color(0xFFE65100);
                  statusBadgeBg = const Color(0xFFFFF3E0);
                  statusText = 'Half Day';
                  break;
                default:
                  statusBadgeColor = Colors.grey.shade600;
                  statusBadgeBg = Colors.grey.shade100;
                  statusText = todayStatus.isNotEmpty ? todayStatus : '--';
              }

              return GestureDetector(
                    onTap: (attProvider.isLoading || !canPunch)
                        ? null
                        : () async {
                            // 1. Location permission
                            final hasPermission =
                                await LocationPermissionService.showPermissionDialog(
                                  context,
                                );
                            if (!hasPermission) return;

                            // 2. Selfie
                            final selfiePath = await attProvider
                                .capturePunchSelfie();
                            if (selfiePath == null) return;

                            // 3. Loading dialog
                            if (!context.mounted) return;
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                              ),
                            );

                            // 4. Session-based punch
                            final auth = context.read<AuthProvider>();
                            final userId = auth.currentUser?.id ?? '';
                            final token = auth.token ?? '';
                            final bool success = isClockedIn
                                ? await attProvider.punchOutWithLocation(
                                    time: DateFormat(
                                      'hh:mm a',
                                    ).format(DateTime.now()),
                                    token: token,
                                  )
                                : await attProvider.punchInWithLocation(
                                    time: DateFormat(
                                      'hh:mm a',
                                    ).format(DateTime.now()),
                                    location: "Office",
                                    userId: userId,
                                    token: token,
                                  );

                            // 5. Close loading dialog
                            if (context.mounted) Navigator.pop(context);

                            if (!context.mounted) return;

                            if (attProvider.localPunchRecords.isEmpty) return;

                            final lastPunch =
                                attProvider.localPunchRecords.last;
                            final refreshToken = context
                                .read<AuthProvider>()
                                .token;
                            if (refreshToken != null) {
                              attProvider.fetchTodayAttendance(refreshToken);
                            }

                            // 6. Status snackbar
                            final messenger = ScaffoldMessenger.of(context);
                            if (success) {
                              final g = attProvider.lastPunchGeofence;
                              if (g != null && g['inside'] == false) {
                                final distance =
                                    (g['distanceM'] as num?)?.toInt() ?? 0;
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Punched ${distance}m outside fence — flagged for review',
                                    ),
                                    backgroundColor: Colors.orange,
                                    duration: const Duration(seconds: 4),
                                  ),
                                );
                              }
                            } else if (attProvider.sessionConflict != null) {
                              final data =
                                  attProvider.sessionConflict!['data']
                                      as Map<String, dynamic>? ??
                                  attProvider.sessionConflict!;
                              final openId = data['session_id'];
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    attProvider.errorMessage ??
                                        'You already have an open session (id $openId). Punch out first.',
                                  ),
                                  backgroundColor: Colors.red,
                                  duration: const Duration(seconds: 4),
                                ),
                              );
                              attProvider.clearSessionConflict();
                            } else {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    attProvider.errorMessage ??
                                        'Saved locally. API sync failed.',
                                  ),
                                  backgroundColor: Colors.orange,
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            }

                            // 7. Open punch view
                            if (context.mounted) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      PunchViewScreen(punchRecord: lastPunch),
                                ),
                              );
                            }
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Status & Work Hours row
                          Padding(
                            padding: const EdgeInsets.only(
                              top: 8,
                              left: 6,
                              right: 6,
                            ),
                            child: Row(
                              children: [
                                // Today's status badge — shown only when the
                                // user actually has a punch today (from
                                // whichever source applies: geofence for
                                // geofence-enabled users, biometric
                                // otherwise). Uses the same gate as the
                                // punch-in time above.
                                if (punchInTime != '--:--')
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: statusBadgeBg,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: statusBadgeColor.withOpacity(
                                          0.5,
                                        ),
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
                                Icon(
                                  Iconsax.timer_1,
                                  size: 14,
                                  color: Colors.grey.shade600,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$workHours hrs',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
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
                              // Punch In — flexible half. Both halves share the
                              // row width evenly, so neither label wraps on a
                              // narrow screen or at a large system font scale.
                              Expanded(
                                child: Row(
                                  children: [
                                    Icon(
                                      Iconsax.clock,
                                      size: 22,
                                      color: Colors.grey.shade500,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "Punch In",
                                            maxLines: 1,
                                            softWrap: false,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.poppins(
                                              fontSize: 12,
                                              color: Colors.grey.shade500,
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
                                              color: Colors.black87,
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
                                    Icon(
                                      Iconsax.clock,
                                      size: 22,
                                      color: Colors.grey.shade500,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "Punch Out",
                                            maxLines: 1,
                                            softWrap: false,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.poppins(
                                              fontSize: 12,
                                              color: Colors.grey.shade500,
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
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Arrow icon button - Opens camera & punches.
                              // Hidden when:
                              //   - geofence_attendance == "No", OR
                              //   - today's cycle is already complete (then
                              //     a small "Done" chip replaces it).
                              if (canPunch)
                                GestureDetector(
                                  onTap: attProvider.isLoading
                                      ? null
                                      : () async {
                                          print('🚪 Dashboard arrow tapped');

                                          // 1. Show location permission dialog FIRST
                                          print(
                                            '📍 Showing location permission dialog...',
                                          );
                                          final hasPermission =
                                              await LocationPermissionService.showPermissionDialog(
                                                context,
                                              );

                                          // User denied - just close dialog and return
                                          if (!hasPermission) {
                                            print(
                                              '❌ User denied location permission',
                                            );
                                            return;
                                          }

                                          print(
                                            '✅ User allowed location permission',
                                          );

                                          // 2. Open camera for selfie
                                          String? selfiePath = await attProvider
                                              .capturePunchSelfie();

                                          // User cancelled or no selfie
                                          if (selfiePath == null) {
                                            print('❌ Camera cancelled');
                                            return;
                                          }

                                          print('✅ Selfie captured');

                                          // 2. Show loading dialog
                                          if (context.mounted) {
                                            showDialog(
                                              context: context,
                                              barrierDismissible: false,
                                              builder: (_) => Center(
                                                child: Container(
                                                  padding: const EdgeInsets.all(
                                                    24,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          16,
                                                        ),
                                                  ),
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      const CircularProgressIndicator(
                                                        color: Color(
                                                          0xFF6C63FF,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 16,
                                                      ),
                                                      Text(
                                                        isClockedIn
                                                            ? 'Punching Out...'
                                                            : 'Punching In...',
                                                        style:
                                                            GoogleFonts.poppins(
                                                              fontSize: 14,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          }

                                          // 3. Punch with location
                                          print('🔄 Starting punch process...');
                                          final authP = context
                                              .read<AuthProvider>();
                                          final userId =
                                              authP.currentUser?.id ?? '';
                                          final token = authP.token ?? '';
                                          bool success;
                                          if (isClockedIn) {
                                            success = await attProvider
                                                .punchOutWithLocation(
                                                  time: DateFormat(
                                                    'hh:mm a',
                                                  ).format(DateTime.now()),
                                                  token: token,
                                                );
                                          } else {
                                            success = await attProvider
                                                .punchInWithLocation(
                                                  time: DateFormat(
                                                    'hh:mm a',
                                                  ).format(DateTime.now()),
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

                                          // 5. Navigate to View screen
                                          if (context.mounted &&
                                              attProvider
                                                  .localPunchRecords
                                                  .isNotEmpty) {
                                            final lastPunch = attProvider
                                                .localPunchRecords
                                                .last;
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => PunchViewScreen(
                                                  punchRecord: lastPunch,
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF6C63FF,
                                      ).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: const Color(
                                          0xFF6C63FF,
                                        ).withOpacity(0.2),
                                      ),
                                    ),
                                    child: attProvider.isLoading
                                        ? const SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              color: Color(0xFF6C63FF),
                                              strokeWidth: 2.5,
                                            ),
                                          )
                                        : Icon(
                                            isClockedIn
                                                ? Iconsax.logout
                                                : Iconsax.login,
                                            size: 24,
                                            color: const Color(0xFF6C63FF),
                                          ),
                                  ),
                                )
                              else if (attProvider
                                      .isGeofenceAttendanceEnabled &&
                                  attProvider.todayCycleCompleted)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF6C63FF,
                                    ).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: const Color(
                                        0xFF6C63FF,
                                      ).withOpacity(0.2),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.check_circle,
                                        size: 16,
                                        color: Color(0xFF6C63FF),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Done',
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF6C63FF),
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
                  )
                  .animate(key: ValueKey('punch_$_refreshKey'))
                  .fadeIn(duration: 700.ms)
                  .slideY(
                    begin: -0.3,
                    end: 0,
                    duration: 600.ms,
                    curve: Curves.easeOutCubic,
                  );
            },
          ),
        ),
      ],
    );
  }

  // ─── Director Overview ───────────────────────────────────────────────
  // Executive snapshot card — replaces the punch card for the director.
  // Four KPI tiles in a 2×2 grid: headcount, attendance, active projects and
  // the combined pending-approval queue.
  //
  // TODO: wire staff / attendance / project counts to real values once the
  // backend exposes them (e.g. DashboardProvider.staffCount).
  static const int _staffCount = 248;
  static const int _contractorCount = 36;
  static const int _attendancePercent = 92;
  static const int _activeProjectCount = 18;

  Widget _buildDirectorOverviewCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Consumer3<DashboardProvider, PermissionProvider, AuthProvider>(
      builder: (context, dashboard, perms, auth, _) {
        // Pending approvals is the one KPI the backend already gives us. Only
        // the queues this director can actually open are counted, so the
        // number on the tile always matches what tapping it offers.
        final buckets = _pendingApprovalBuckets(dashboard, perms, auth);
        final pendingApprovals = buckets.fold<int>(
          0,
          (sum, b) => sum + b.count,
        );
        return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isDark
                      ? AppColors.darkBorder
                      : const Color(0xFFEEF0F6),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.35 : 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header: title block + total-headcount pill.
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(
                            isDark ? 0.22 : 0.10,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Iconsax.task_square,
                          color: AppColors.primary,
                          size: 17,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Director Overview',
                              style: GoogleFonts.poppins(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              'Your organisation at a glance',
                              style: GoogleFonts.poppins(
                                fontSize: 9.5,
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Total headcount = staff + petty contractors.
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(
                            isDark ? 0.22 : 0.09,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Iconsax.people,
                              color: AppColors.primary,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${_staffCount + _contractorCount}',
                              style: GoogleFonts.poppins(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // KPI grid — 2×2.
                  Row(
                    children: [
                      _kpiTile(
                        index: 0,
                        icon: Iconsax.profile_2user,
                        colors: const [Color(0xFF6366F1), Color(0xFF4F46E5)],
                        value: '$_staffCount',
                        label: 'Staff',
                        onTap: () => Navigator.push(
                          context,
                          _slideFadeRoute(const BranchStaffScreen()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _kpiTile(
                        index: 1,
                        icon: Iconsax.clock,
                        colors: const [Color(0xFF2DD4BF), Color(0xFF0D9488)],
                        value: '$_attendancePercent%',
                        label: 'Attendance',
                        onTap: () => Navigator.push(
                          context,
                          _slideFadeRoute(const TeamOverviewScreen()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _kpiTile(
                        index: 2,
                        icon: Iconsax.briefcase,
                        colors: const [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                        value: '$_activeProjectCount',
                        label: 'Active Projects',
                        onTap: () => Navigator.push(
                          context,
                          _slideFadeRoute(const ProjectDetailsScreen()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _kpiTile(
                        index: 3,
                        icon: Iconsax.task_square,
                        colors: const [Color(0xFFFBA43A), Color(0xFFF07C0A)],
                        value: '$pendingApprovals',
                        label: 'Pending Approvals',
                        onTap: () => _openPendingApprovals(buckets),
                      ),
                    ],
                  ),
                ],
              ),
            )
            .animate(key: ValueKey('overview_$_refreshKey'))
            .fadeIn(duration: 600.ms)
            .slideY(
              begin: -0.2,
              end: 0,
              duration: 550.ms,
              curve: Curves.easeOutCubic,
            );
      },
    );
  }

  // Every approval queue the signed-in director may open, in the order they
  // appear in the Approvals section. Gating mirrors that section exactly, so a
  // queue the director can't act on is never counted or offered.
  List<_PendingBucket> _pendingApprovalBuckets(
    DashboardProvider dashboard,
    PermissionProvider perms,
    AuthProvider auth,
  ) {
    final role = auth.currentUser?.role ?? UserRole.director;
    return [
      if (perms.isEnabled('leave_approvals'))
        _PendingBucket(
          label: 'Leave Approvals',
          count: dashboard.leavePendingCount,
          icon: Iconsax.document_text_1,
          colors: const [Color(0xFF10B981), Color(0xFF059669)],
          builder: () => const LeaveApprovalScreen(),
        ),
      if (perms.isEnabled('regularize_approvals'))
        _PendingBucket(
          label: 'Regularize Approvals',
          count: dashboard.regularizationPendingCount,
          icon: Iconsax.tick_square,
          colors: const [Color(0xFFFBBF24), Color(0xFFF59E0B)],
          builder: () => const RegularizationApprovalScreen(),
        ),
      if (role.canApproveOnboarding)
        _PendingBucket(
          label: 'Onboarding Approvals',
          count: dashboard.onboardingPendingCount,
          icon: Iconsax.add,
          colors: const [Color(0xFF34D399), Color(0xFF10B981)],
          builder: () => const EmployeeOnboardingApprovalScreen(),
        ),
    ];
  }

  // Opens an approval queue and re-pulls the pending counts on the way back —
  // they go stale the moment the director approves something. Deliberately not
  // a full _fetchData(): that bumps _refreshKey and replays every entry
  // animation, which is jarring when you're just popping back.
  void _pushApprovalScreen(Widget screen) {
    Navigator.push(context, _slideFadeRoute(screen)).then((_) {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final token = auth.token;
      if (token == null) return;
      final role = auth.currentUser?.role;
      context.read<DashboardProvider>().fetchRecentActivity(
        token: token,
        empId: auth.currentUser?.id ?? '',
        role: role,
        canBranchPayroll: role == UserRole.admin || role == UserRole.manager,
      );
    });
  }

  // Tapping the Pending Approvals KPI goes straight to work:
  //   • nothing pending  → say so, don't open an empty screen
  //   • one queue pending → open it directly, no intermediate step
  //   • several pending   → let the director pick, counts shown
  void _openPendingApprovals(List<_PendingBucket> buckets) {
    final pending = buckets.where((b) => b.count > 0).toList();

    if (pending.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            content: Row(
              children: [
                const Icon(Iconsax.tick_circle, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No pending approvals',
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      return;
    }

    if (pending.length == 1) {
      _pushApprovalScreen(pending.first.builder());
      return;
    }

    _showPendingApprovalPicker(pending);
  }

  void _showPendingApprovalPicker(List<_PendingBucket> pending) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = pending.fold<int>(0, (sum, b) => sum + b.count);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                child: Row(
                  children: [
                    Text(
                      'Pending Approvals',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$total waiting',
                      style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              ...pending.map(
                (bucket) => ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: bucket.colors,
                      ),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(bucket.icon, color: Colors.white, size: 19),
                  ),
                  title: Text(
                    bucket.label,
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    bucket.count == 1
                        ? '1 request waiting'
                        : '${bucket.count} requests waiting',
                    style: GoogleFonts.poppins(
                      fontSize: 10.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${bucket.count}',
                      style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  onTap: () {
                    // Close the sheet first so back from the approval screen
                    // returns to the dashboard, not to a stale sheet.
                    Navigator.pop(sheetContext);
                    _pushApprovalScreen(bucket.builder());
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  // One KPI tile inside the director overview card. [colors] is a 2-stop
  // gradient (light → deep) used for the fill and its glow.
  Widget _kpiTile({
    required int index,
    required IconData icon,
    required List<Color> colors,
    required String value,
    required String label,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child:
            Container(
                  padding: const EdgeInsets.fromLTRB(11, 12, 11, 11),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: colors,
                    ),
                    borderRadius: BorderRadius.circular(17),
                    boxShadow: [
                      BoxShadow(
                        color: colors.last.withOpacity(0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.22),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(icon, color: Colors.white, size: 15),
                          ),
                          const Spacer(),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                value,
                                maxLines: 1,
                                softWrap: false,
                                style: GoogleFonts.poppins(
                                  fontSize: 23,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  height: 1,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                label,
                                maxLines: 1,
                                softWrap: false,
                                style: GoogleFonts.poppins(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withOpacity(0.95),
                                ),
                              ),
                            ),
                          ),
                          if (onTap != null)
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 9,
                              color: Colors.white.withOpacity(0.85),
                            ),
                        ],
                      ),
                    ],
                  ),
                )
                .animate(
                  key: ValueKey('kpitile_${_refreshKey}_$index'),
                  delay: (250 + index * 110).ms,
                )
                .fadeIn(duration: 450.ms)
                .slideY(begin: 0.25, end: 0, curve: Curves.easeOutCubic)
                .scale(
                  begin: const Offset(0.88, 0.88),
                  end: const Offset(1, 1),
                  curve: Curves.easeOutBack,
                ),
      ),
    );
  }

  // ─── Director menu ───────────────────────────────────────────────────
  // The director gets its own layout: Approvals first, then Teams, both
  // rendered as filled gradient tiles rather than the plain quick-access
  // icons the other roles use. No punch/leave "My Menu" and no celebrations
  // strip — the overview card carries the whole story.
  Widget _buildDirectorMenu(
    BuildContext context,
    PermissionProvider perms,
    DashboardProvider dashboard,
    AuthProvider auth,
    bool isDark,
  ) {
    final role = auth.currentUser?.role ?? UserRole.director;
    bool canSee(String key) => perms.isEnabled(key);

    final approvals = <Widget>[
      if (canSee('leave_approvals'))
        _DirectorActionItem(
          icon: Iconsax.document_text_1,
          label: 'Leave\nApprovals',
          colors: const [Color(0xFF10B981), Color(0xFF059669)],
          badgeCount: dashboard.leavePendingCount,
          isDark: isDark,
          onTap: () => _pushApprovalScreen(const LeaveApprovalScreen()),
        ),
      if (canSee('regularize_approvals'))
        _DirectorActionItem(
          icon: Iconsax.tick_square,
          label: 'Regularize\nApprovals',
          colors: const [Color(0xFFFBBF24), Color(0xFFF59E0B)],
          badgeCount: dashboard.regularizationPendingCount,
          isDark: isDark,
          onTap: () =>
              _pushApprovalScreen(const RegularizationApprovalScreen()),
        ),
      if (role.canApproveOnboarding)
        _DirectorActionItem(
          icon: Iconsax.add,
          label: 'Onboarding\nApprovals',
          colors: const [Color(0xFF34D399), Color(0xFF10B981)],
          badgeCount: dashboard.onboardingPendingCount,
          isDark: isDark,
          onTap: () =>
              _pushApprovalScreen(const EmployeeOnboardingApprovalScreen()),
        ),
      // Where the whole team is right now. Gated on role alone: the server
      // admits exactly ADMIN and DIRECTOR (see
      // docs/geofence-live-dashboard-api.md), which is what
      // canViewLocationHistory encodes. It used to also require the
      // 'location_history' permission — a self-service flag about seeing
      // your *own* trail, which could only hide a tile the API would have
      // answered. The admin gets the same screen from the Teams grid.
      if (role.canViewLocationHistory)
        _DirectorActionItem(
          icon: Iconsax.location,
          label: 'Team\nLocation',
          colors: const [Color(0xFFFB923C), Color(0xFFEA580C)],
          isDark: isDark,
          onTap: () => Navigator.push(
            context,
            _slideFadeRoute(const TeamLocationMapScreen()),
          ),
        ),
    ];

    final teams = <Widget>[
      _DirectorActionItem(
        icon: Iconsax.map_1,
        label: 'Employee\nLifecycle',
        colors: const [Color(0xFF818CF8), Color(0xFF6366F1)],
        isDark: isDark,
        onTap: () =>
            Navigator.push(context, _slideFadeRoute(const RoadmapScreen())),
      ),
      _DirectorActionItem(
        icon: Iconsax.clipboard_text,
        label: 'Requisition\nSummary',
        colors: const [Color(0xFF60A5FA), Color(0xFF3B82F6)],
        isDark: isDark,
        onTap: () => Navigator.push(
          context,
          _slideFadeRoute(const RequisitionSummaryScreen()),
        ),
      ),
      // canAccessTeamOverview hides this entry for users with no department
      // scope — the director always qualifies, but the permission flag can
      // still switch it off.
      if (canSee('team_overview') &&
          TeamOverviewScreen.canAccessTeamOverview(auth.currentUser))
        _DirectorActionItem(
          icon: Iconsax.category,
          label: 'Team\nOverview',
          colors: const [Color(0xFF2DD4BF), Color(0xFF0D9488)],
          isDark: isDark,
          onTap: () => Navigator.push(
            context,
            _slideFadeRoute(const TeamOverviewScreen()),
          ),
        ),
      if (role.canViewAllEmployees && canSee('employee_details'))
        _DirectorActionItem(
          icon: Iconsax.user,
          label: 'Employee\nDetails',
          colors: const [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
          isDark: isDark,
          onTap: () => Navigator.push(
            context,
            _slideFadeRoute(const EmployeeDetailsScreen()),
          ),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.paddingMD),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (approvals.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildSectionHeader('Approvals', isDark),
            const SizedBox(height: 10),
            _buildDirectorGrid(approvals),
          ],
          if (teams.isNotEmpty) ...[
            const SizedBox(height: 18),
            _buildSectionHeader('Teams', isDark),
            const SizedBox(height: 10),
            _buildDirectorGrid(teams),
          ],
          const SizedBox(height: AppConstants.paddingXL),
        ],
      ),
    );
  }

  // Lays the director tiles out four-per-row.
  //
  // A group that fits on one row spreads its items evenly across the full
  // width, so a three-item row stays balanced instead of hugging the left edge
  // like a Wrap would. Once a group wraps, the short final row is padded with
  // empty cells instead — otherwise a lone trailing tile would drift to the
  // middle of the screen and break the column alignment with the row above.
  Widget _buildDirectorGrid(List<Widget> items) {
    final padShortRow = items.length > 4;
    final rows = <Widget>[];
    for (var start = 0; start < items.length; start += 4) {
      final chunk = items.sublist(
        start,
        start + 4 > items.length ? items.length : start + 4,
      );
      final cells = <Widget>[
        ...chunk.asMap().entries.map((entry) {
          return Expanded(
            child: entry.value
                .animate(
                  key: ValueKey('dirtile_${_refreshKey}_${start + entry.key}'),
                  delay: ((start + entry.key) * 90).ms,
                )
                .fadeIn(duration: 400.ms)
                .slideY(begin: 0.25, end: 0, curve: Curves.easeOutCubic)
                .scale(
                  begin: const Offset(0.85, 0.85),
                  end: const Offset(1, 1),
                  curve: Curves.easeOutBack,
                ),
          );
        }),
        if (padShortRow)
          for (var i = chunk.length; i < 4; i++)
            const Expanded(child: SizedBox.shrink()),
      ];
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: start == 0 ? 0 : 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: cells,
          ),
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _buildQuickAccessSection(bool isDark) {
    return Consumer2<AuthProvider, PermissionProvider>(
      builder: (context, auth, perms, _) {
        final role = auth.currentUser?.role ?? UserRole.employee;
        final isAdmin = role == UserRole.admin;
        bool canSee(String key) => isAdmin || perms.isEnabled(key);
        // Gating for session-based attendance features: Punch History,
        // Location History, and Live Attendance only make sense for
        // geofence-enabled employees (biometric-only users never produce
        // session or ping data for these screens to show).
        final isGeofenceEnabled = context
            .watch<AttendanceProvider>()
            .isGeofenceAttendanceEnabled;
        final dashboard = context.watch<DashboardProvider>();
        // The director has a dedicated layout (Approvals → Teams) built from
        // gradient tiles; none of the sections below apply.
        if (role == UserRole.director) {
          return _buildDirectorMenu(context, perms, dashboard, auth, isDark);
        }
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.paddingMD,
            vertical: 0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── MY Section ─── (hidden for Director) ───────────────
              if (role != UserRole.director) ...[
                _buildSectionHeader('My Menu', isDark),
                const SizedBox(height: 2),
                _buildGridRow([
                  if (canSee('my_attendance'))
                    _buildQuickAccessItem(
                      icon: Iconsax.user_tick,
                      label: 'My Attendance',
                      color: AppColors.secondary,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AttendanceScreen(),
                        ),
                      ),
                      isDark: isDark,
                    ),
                  if (canSee('regularize_attendance'))
                    _buildQuickAccessItem(
                      icon: Iconsax.calendar_tick,
                      label: 'Attendance\nSummary',
                      color: AppColors.secondary,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MyAttendanceDetailScreen(),
                        ),
                      ),
                      isDark: isDark,
                    ),
                  if (canSee('regularization_list'))
                    _buildQuickAccessItem(
                      icon: Iconsax.clipboard_text,
                      label: 'Regularize\nList',
                      color: AppColors.secondary,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RegularizationListScreen(),
                        ),
                      ),
                      isDark: isDark,
                    ),
                  // if (canSee('punch_history') && isGeofenceEnabled)
                  //   _buildQuickAccessItem(
                  //     icon: Iconsax.clock,
                  //     label: 'Punch\nHistory',
                  //     color: AppColors.secondary,
                  //     onTap: () => Navigator.push(
                  //       context,
                  //       MaterialPageRoute(
                  //         builder: (_) => const PunchHistoryScreen(),
                  //       ),
                  //     ),
                  //     isDark: isDark,
                  //   ),
                  if (canSee('location_history') && isGeofenceEnabled)
                    _buildQuickAccessItem(
                      icon: Iconsax.location,
                      label: 'Location\nHistory',
                      color: const Color(0xFFFF9800),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LocationHistoryScreen(),
                        ),
                      ),
                      isDark: isDark,
                    ),
                  if (canSee('apply_leave'))
                    _buildQuickAccessItem(
                      icon: Iconsax.add,
                      label: 'Apply Leave',
                      color: AppColors.warning,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LeaveScreen()),
                      ),
                      isDark: isDark,
                    ),
                  if (canSee('leave_history'))
                    _buildQuickAccessItem(
                      icon: Iconsax.clipboard_text,
                      label: 'Leave History',
                      color: const Color.fromARGB(255, 230, 172, 71),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LeaveHistoryScreen(),
                        ),
                      ),
                      isDark: isDark,
                    ),
                  if (canSee('my_payslip'))
                    _buildQuickAccessItem(
                      icon: Iconsax.receipt_2,
                      label: 'My Payslip',
                      color: AppColors.success,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DownloadSlipsScreen(),
                        ),
                      ),
                      isDark: isDark,
                    ),
                  // Pre-Recruitment — under My Menu, for every role except
                  // plain staff / employee (and Director, whose My Menu is
                  // hidden; Director still reaches it via the side drawer).
                  if (role.canViewPreRecruitment)
                    _buildQuickAccessItem(
                      icon: Iconsax.profile_add,
                      label: 'Pre-\nRecruitment',
                      color: AppColors.info,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PreRecruitmentScreen(),
                        ),
                      ),
                      isDark: isDark,
                    ),
                ]),
              ],

              // ─── TEAMS Section ──────────────────────────────────────
              if (canSee('team_overview') ||
                  role.canViewLocationHistory ||
                  (role.canApplyEmployeeLeave &&
                      canSee('apply_employee_leave')) ||
                  (role.canViewAllEmployees && canSee('employee_details')) ||
                  (role.canViewEmployeePayslip &&
                      canSee('employee_payslip'))) ...[
                // My Menu always precedes Teams, so always show the leading
                // divider.
                const SizedBox(height: AppConstants.paddingSM),
                Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: AppConstants.paddingSM,
                      ),
                      child: Divider(
                        color: isDark
                            ? AppColors.darkBorder
                            : Colors.grey.shade300,
                        thickness: 1,
                        height: 18,
                      ),
                    )
                    .animate(key: ValueKey('div_teams_$_refreshKey'))
                    .scaleX(
                      begin: 0,
                      end: 1,
                      alignment: Alignment.centerLeft,
                      duration: 600.ms,
                      curve: Curves.easeOutCubic,
                    ),
                const SizedBox(height: 5),
                _buildSectionHeader('Teams', isDark),
                const SizedBox(height: 2),
                _buildGridRow([
                  // Where the whole team is right now. The director reaches
                  // this from its own menu; this is the same screen for the
                  // admin, who never renders that menu.
                  //
                  // Gated on role alone, deliberately: the server admits
                  // exactly ADMIN and DIRECTOR (see
                  // docs/geofence-live-dashboard-api.md), which is precisely
                  // what canViewLocationHistory encodes. Adding a permission
                  // flag on top could only ever hide a tile the API would
                  // have answered.
                  if (role.canViewLocationHistory)
                    _buildQuickAccessItem(
                      icon: Iconsax.location,
                      label: 'Team\nLocation',
                      color: const Color(0xFFEA580C),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TeamLocationMapScreen(),
                        ),
                      ),
                      isDark: isDark,
                    ),
                  // canAccessTeamOverview hides this entry for dept-scoped
                  // users (Manager / HR Admin / etc.) who have no department
                  // set on their profile — they'd land on an empty list.
                  // Admin always qualifies.
                  if (canSee('team_overview') &&
                      TeamOverviewScreen.canAccessTeamOverview(
                        auth.currentUser,
                      ))
                    _buildQuickAccessItem(
                      icon: Iconsax.people,
                      label: 'Team Overview',
                      color: AppColors.secondary,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TeamOverviewScreen(),
                        ),
                      ),
                      isDark: isDark,
                    ),
                  if (role.canApplyEmployeeLeave &&
                      canSee('apply_employee_leave'))
                    _buildQuickAccessItem(
                      icon: Iconsax.user_add,
                      label: 'Apply\nEmployee',
                      color: AppColors.warning,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const EmployeeLeaveSummaryScreen(),
                        ),
                      ),
                      isDark: isDark,
                    ),
                  if (role.canViewAllEmployees && canSee('employee_details'))
                    _buildQuickAccessItem(
                      icon: Iconsax.user_search,
                      label: 'Employee\nDetails',
                      color: AppColors.primary,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const EmployeeDetailsScreen(),
                        ),
                      ),
                      isDark: isDark,
                    ),
                  if (role.canViewEmployeePayslip && canSee('employee_payslip'))
                    _buildQuickAccessItem(
                      icon: Iconsax.receipt_1,
                      label: 'Employee\nPayslip',
                      color: AppColors.success,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const EmployeePayslipScreen(),
                        ),
                      ),
                      isDark: isDark,
                    ),
                ]),
              ],

              // ─── APPROVALS Section ──────────────────────────────────
              if (canSee('regularize_approvals') ||
                  ((role == UserRole.manager || role == UserRole.admin) &&
                      canSee('leave_approvals')) ||
                  role == UserRole.admin ||
                  role.canApproveOnboarding) ...[
                const SizedBox(height: AppConstants.paddingSM),
                Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: AppConstants.paddingSM,
                  ),
                  child: Divider(
                    color: isDark ? AppColors.darkBorder : Colors.grey.shade300,
                    thickness: 1,
                    height: 18,
                  ),
                ),
                const SizedBox(height: 5),
                _buildSectionHeader('Approvals', isDark),
                const SizedBox(height: 2),
                _buildGridRow([
                  if (canSee('regularize_approvals'))
                    _buildQuickAccessItem(
                      icon: Iconsax.task_square,
                      label: 'Regularize\nApprovals',
                      color: AppColors.secondary,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RegularizationApprovalScreen(),
                        ),
                      ),
                      isDark: isDark,
                      badgeCount: dashboard.regularizationPendingCount,
                    ),
                  if ((role == UserRole.manager || role == UserRole.admin) &&
                      canSee('leave_approvals'))
                    _buildQuickAccessItem(
                      icon: Iconsax.task_square,
                      label: 'Leave\nApprovals',
                      color: const Color.fromARGB(255, 232, 208, 88),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LeaveApprovalScreen(),
                        ),
                      ),
                      isDark: isDark,
                      badgeCount: dashboard.leavePendingCount,
                    ),
                  if (role == UserRole.admin || role == UserRole.manager)
                    _buildQuickAccessItem(
                      icon: Iconsax.money_recive,
                      label: 'Payroll\nApprovals',
                      color: const Color(0xFF22A06B),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const BranchPayrollApprovalScreen(),
                        ),
                      ),
                      isDark: isDark,
                      badgeCount: dashboard.branchPayrollPendingCount,
                    ),
                  if (role.canApproveOnboarding)
                    _buildQuickAccessItem(
                      icon: Iconsax.user_add,
                      label: 'Onboarding\nApprovals',
                      color: AppColors.success,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const EmployeeOnboardingApprovalScreen(),
                        ),
                      ),
                      isDark: isDark,
                      badgeCount: dashboard.onboardingPendingCount,
                    ),
                ]),
              ],

              // Celebrations Today Section
              const SizedBox(height: 5),
              Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: AppConstants.paddingSM,
                ),
                child: Divider(
                  color: isDark ? AppColors.darkBorder : Colors.grey.shade300,
                  thickness: 1,
                  height: 18,
                ),
              ),
              const SizedBox(height: AppConstants.paddingSM),
              _buildCelebrationsHeader(context, 'Celebrations Today', isDark),
              const SizedBox(height: AppConstants.paddingSM),
              _buildCelebrationsCard(context, isDark),
              const SizedBox(height: AppConstants.paddingXL),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCelebrationsHeader(
    BuildContext context,
    String title,
    bool isDark,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: AppTextStyles.headlineSmall.copyWith(
            color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
          ),
        ).animate().fadeIn().slideX(begin: -0.2, end: 0),
        TextButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CelebrationsScreen()),
            );
          },
          child: Text(
            'View All',
            style: GoogleFonts.inter(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ).animate().fadeIn(delay: 300.ms),
      ],
    );
  }

  Widget _buildCelebrationsCard(BuildContext context, bool isDark) {
    return Consumer<DashboardProvider>(
      builder: (context, provider, child) {
        final birthdayBoys = provider.birthdayEmployees;

        String title = "Today's Birthdays";
        String subtitle = "No birthdays today";

        if (birthdayBoys.isNotEmpty) {
          final firstName = birthdayBoys[0].fullName;
          if (birthdayBoys.length == 1) {
            subtitle = firstName;
          } else {
            subtitle = '$firstName & ${birthdayBoys.length - 1} others';
          }
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                  : [Colors.white, const Color(0xFFF8FAFC)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : Colors.grey.shade200,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              // Birthday Icon / Animation
              Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Iconsax.cake,
                      color: AppColors.warning,
                      size: 28,
                    ),
                  )
                  .animate(
                    onPlay: (controller) => controller.repeat(reverse: true),
                  )
                  .scale(
                    begin: const Offset(0.9, 0.9),
                    end: const Offset(1.1, 1.1),
                    duration: 1000.ms,
                  ),

              const SizedBox(width: 16),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: isDark ? Colors.white60 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),

              // Avatars Stack
              if (birthdayBoys.isNotEmpty)
                SizedBox(
                  width: 80,
                  height: 35,
                  child: Stack(
                    children: List.generate(
                      birthdayBoys.length > 3 ? 3 : birthdayBoys.length,
                      (index) {
                        if (index == 2 && birthdayBoys.length > 3) {
                          return Positioned(
                            left: index * 20.0,
                            child: _buildMiniAvatar(
                              '+${birthdayBoys.length - 2}',
                              Colors.grey,
                            ),
                          );
                        }
                        return Positioned(
                          left: index * 20.0,
                          child: _buildMiniAvatar(
                            birthdayBoys[index].initials,
                            [Colors.blue, Colors.orange, Colors.green][index %
                                3],
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildMiniAvatar(String text, Color color) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // Slide-up + fade page transition used by the director tiles and the
  // Requisition Summary screen.
  Route<T> _slideFadeRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 350),
      reverseTransitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
              title,
              style: AppTextStyles.titleSmall.copyWith(
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontStyle: FontStyle.normal,
              ),
            )
            .animate(key: ValueKey('text_${_refreshKey}_$title'))
            .fadeIn(duration: 500.ms)
            .slideX(begin: -0.2, end: 0, curve: Curves.easeOutCubic)
            .shimmer(
              delay: 400.ms,
              duration: 1200.ms,
              color: isDark ? Colors.white24 : Colors.black12,
            ),
        const SizedBox(height: 4),
        // Container(
        //       // height: 3,
        //       // width: 32, // Small line length
        //       decoration: BoxDecoration(
        //         color: AppColors.primary,
        //         borderRadius: BorderRadius.circular(3),
        //       ),
        //     )
        // .animate(key: ValueKey('line_${_refreshKey}_$title'))
        // .fadeIn(delay: 300.ms)
        // .scaleX(
        //   alignment: Alignment.centerLeft,
        //   curve: Curves.easeOutCubic,
        //   duration: 600.ms,
        // ),
      ],
    );
  }

  Widget _buildGridRow(List<Widget> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate width for 4 items per row, accounting for spacing
        final spacing = 8.0;
        final itemWidth = (constraints.maxWidth - (spacing * 3)) / 4;

        return Wrap(
          spacing: spacing,
          runSpacing: AppConstants.paddingMD,
          children: items.asMap().entries.map((entry) {
            final item = entry.value;
            // Inject the calculated width if it's our quick access item
            Widget responsiveItem = item;
            if (item is _QuickAccessItemWidget) {
              responsiveItem = item.copyWithWidth(itemWidth);
            }

            return responsiveItem
                .animate(
                  key: ValueKey('grid_${_refreshKey}_${entry.key}'),
                  delay: (entry.key * 120).ms,
                )
                .fadeIn(duration: 400.ms)
                .scale(
                  begin: const Offset(0.5, 0.5),
                  duration: 700.ms,
                  curve: Curves.elasticOut,
                )
                .rotate(
                  begin: -0.05,
                  end: 0,
                  duration: 500.ms,
                  curve: Curves.easeOutCubic,
                );
          }).toList(),
        );
      },
    );
  }

  Widget _buildQuickAccessItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required bool isDark,
    int? badgeCount,
  }) {
    return _QuickAccessItemWidget(
      icon: icon,
      label: label,
      color: color,
      onTap: onTap,
      isDark: isDark,
      refreshKey: _refreshKey,
      badgeCount: badgeCount,
    );
  }
}

class _QuickAccessItemWidget extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool isDark;
  final double width;
  final int refreshKey;
  final int? badgeCount;

  const _QuickAccessItemWidget({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    required this.isDark,
    required this.refreshKey,
    this.width = 75,
    this.badgeCount,
  });

  _QuickAccessItemWidget copyWithWidth(double newWidth) {
    return _QuickAccessItemWidget(
      icon: icon,
      label: label,
      color: color,
      onTap: onTap,
      isDark: isDark,
      refreshKey: refreshKey,
      width: newWidth,
      badgeCount: badgeCount,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 22)
                      .animate(key: ValueKey('icon_$refreshKey'))
                      .scale(
                        begin: const Offset(0.0, 0.0),
                        end: const Offset(1.0, 1.0),
                        duration: 600.ms,
                        curve: Curves.elasticOut,
                      )
                      .fadeIn(duration: 300.ms)
                      .shimmer(
                        delay: 500.ms,
                        duration: 1000.ms,
                        color: color.withOpacity(0.3),
                      ),
                ),
                if (badgeCount != null && badgeCount! > 0)
                  Positioned(
                    right: 0,
                    top: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF1C1C1E)
                              : Colors.white,
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        badgeCount! > 9 ? '9+' : '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            //  for text and icon gap
            const SizedBox(height: 0),
            Text(
              label,
              style: AppTextStyles.labelSmall.copyWith(
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.textPrimary,
                fontWeight: FontWeight.w500,
                fontSize: 11, // Smaller font to fit 4 per row
                height: 1.1,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// One approval queue behind the Pending Approvals KPI: how many are waiting
/// and how to open it.
class _PendingBucket {
  final String label;
  final int count;
  final IconData icon;
  final List<Color> colors;
  final Widget Function() builder;

  const _PendingBucket({
    required this.label,
    required this.count,
    required this.icon,
    required this.colors,
    required this.builder,
  });
}

/// A director menu entry: a filled gradient square with a white glyph, an
/// optional pending-count badge, and a two-line caption underneath.
class _DirectorActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<Color> colors;
  final VoidCallback onTap;
  final bool isDark;
  final int? badgeCount;

  const _DirectorActionItem({
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
    required this.isDark,
    this.badgeCount,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: colors,
                  ),
                  borderRadius: BorderRadius.circular(17),
                  boxShadow: [
                    BoxShadow(
                      color: colors.last.withOpacity(0.32),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              if (badgeCount != null && badgeCount! > 0)
                Positioned(
                  right: -5,
                  top: -5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 19,
                      minHeight: 19,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark ? AppColors.darkBackground : Colors.white,
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      badgeCount! > 9 ? '9+' : '$badgeCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
              fontWeight: FontWeight.w500,
              fontSize: 10.5,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
