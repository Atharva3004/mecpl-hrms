// Main Shell - Container with Bottom Navigation
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/permission_provider.dart';
import '../../services/notification_service.dart';
import '../../models/role_model.dart';
import '../../widgets/navigation/animated_bottom_nav.dart';
import '../../widgets/navigation/app_drawer.dart';
import '../dashboard/dashboard_screen.dart';
import '../attendance/attendance_screen.dart';
// import '../payroll/payroll_screen.dart';
import '../leave/leave_screen.dart';
import '../profile/profile_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncPermissions();
      // Drain any notification route the user tapped while logged out / on
      // the biometric lock / mid-bootstrap. Has to run after the first frame
      // so the navigator and providers below us are fully built.
      NotificationService.markShellReady();
    });
  }

  @override
  void dispose() {
    // Logout / forced logout unmounts MainShell. Subsequent notification
    // taps will be persisted instead of dropped on the login screen.
    NotificationService.markShellGone();
    super.dispose();
  }

  void _syncPermissions() {
    final auth = context.read<AuthProvider>();
    final perms = context.read<PermissionProvider>();
    final user = auth.currentUser;
    final token = auth.token;
    if (user == null || token == null) return;
    if (perms.isCurrentUser(user.id)) return;
    perms.loadForUser(userId: user.id, token: token);
    perms.loadGlobal(token: token);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<NavigationProvider, AuthProvider>(
      builder: (context, navProvider, authProvider, child) {
        final role = authProvider.currentUser?.role;
        final canViewReports = role?.canViewReports ?? false;
        final isDirector = role == UserRole.director;

        // Body children keep fixed indices (0=Dashboard, 1=Attendance,
        // 2=Leave, 3=Profile) so notification tab routing stays valid.
        // For the director we simply hide the Attendance & Leave tabs from
        // the bottom bar by mapping each visible slot back to its body index.
        final allItems = NavItems.getItemsForRole(canViewReports);
        final visibleIndices = <int>[
          0, // Dashboard
          if (!isDirector) 1, // Attendance
          if (!isDirector) 2, // Leave
          3, // Profile
        ];
        final navItems = [for (final i in visibleIndices) allItems[i]];
        final selectedSlot = visibleIndices.indexOf(navProvider.currentIndex);

        return Scaffold(
          key: _scaffoldKey,
          drawer: const AppDrawer(),
          body: IndexedStack(
            index: navProvider.currentIndex,
            children: [
              DashboardScreen(
                key: const ValueKey('dashboard'),
                scaffoldKey: _scaffoldKey,
              ),
              const AttendanceScreen(key: ValueKey('attendance')),
              // const PayrollScreen(key: ValueKey('payroll')),
              const LeaveScreen(key: ValueKey('leave')),
              const ProfileScreen(key: ValueKey('profile')),
            ],
          ),
          extendBody: true,
          bottomNavigationBar: AnimatedBottomNavBar(
            currentIndex: selectedSlot < 0 ? 0 : selectedSlot,
            items: navItems,
            onTap: (slot) => navProvider.setIndex(visibleIndices[slot]),
          ),
        );
      },
    );
  }
}
