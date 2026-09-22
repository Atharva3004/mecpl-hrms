import 'package:flutter/material.dart';
import 'package:mecpl_flutter/models/user_model.dart';
import 'package:mecpl_flutter/models/leave_application_model.dart';
import 'package:mecpl_flutter/models/attendance_model.dart';
import 'package:mecpl_flutter/models/role_model.dart';
import 'package:mecpl_flutter/services/api_service.dart';
import 'package:mecpl_flutter/core/theme/app_colors.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';

class DashboardActivity {
  final String title;
  final DateTime timestamp;
  final IconData icon;
  final Color color;
  final String type;

  DashboardActivity({
    required this.title,
    required this.timestamp,
    required this.icon,
    required this.color,
    required this.type,
  });

  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hours ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else {
      return DateFormat('MMM dd, yyyy').format(timestamp);
    }
  }
}

class DashboardProvider extends ChangeNotifier {
  List<DashboardActivity> _activities = [];
  bool _isLoading = false;
  String? _errorMessage;
  int _unreadCount = 0;
  List<UserModel> _birthdayEmployees = [];
  int _leavePendingCount = 0;
  int _regularizationPendingCount = 0;
  int _onboardingPendingCount = 0;
  int _branchPayrollPendingCount = 0;

  List<DashboardActivity> get activities => _activities;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get unreadCount => _unreadCount;
  List<UserModel> get birthdayEmployees => _birthdayEmployees;
  int get leavePendingCount => _leavePendingCount;
  int get regularizationPendingCount => _regularizationPendingCount;
  int get onboardingPendingCount => _onboardingPendingCount;
  int get branchPayrollPendingCount => _branchPayrollPendingCount;

  void markAllRead() {
    _unreadCount = 0;
    notifyListeners();
  }

  Future<void> fetchRecentActivity({
    required String token,
    required String empId,
    UserRole? role,
    bool canBranchPayroll = false,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 1. Fetch Leave History
      final leaves = await ApiService.getLeaveHistory(
        token: token,
        empId: empId,
      );

      // 2. Fetch Attendance History
      final attendanceResponse = await ApiService.getAttendanceHistory();
      List<AttendanceModel> attendance = [];
      if (attendanceResponse.isSuccess && attendanceResponse.data != null) {
        attendance = ApiService.parseAttendanceFromResponse(
          attendanceResponse.data!,
        );
      }

      // 3. Convert to DashboardActivity
      final List<DashboardActivity> combined = [];

      // Convert Leaves
      for (LeaveApplication leave in leaves) {
        combined.add(
          DashboardActivity(
            title: 'Leave ${leave.status}: ${leave.leaveType.leaveName}',
            timestamp: leave.createdAt,
            icon: _getLeaveIcon(leave.status),
            color: _getLeaveColor(leave.status),
            type: 'leave',
          ),
        );
      }

      // Convert Attendance
      for (AttendanceModel att in attendance) {
        // Clock In Activity
        if (att.checkIn != null) {
          try {
            // Attempt to parse checkIn time. Attendance model doesn't store full DateTime for checkIn/Out,
            // only time string. We combine it with date.
            final checkInTime = _parseTime(att.date, att.checkIn!);
            combined.add(
              DashboardActivity(
                title: 'Clocked In at ${att.location ?? 'Office'}',
                timestamp: checkInTime,
                icon: Iconsax.login,
                color: AppColors.success,
                type: 'attendance',
              ),
            );
          } catch (e) {
            debugPrint('Error parsing check-in time: $e');
          }
        }

        // Clock Out Activity
        if (att.checkOut != null) {
          try {
            final checkOutTime = _parseTime(att.date, att.checkOut!);
            combined.add(
              DashboardActivity(
                title: 'Clocked Out',
                timestamp: checkOutTime,
                icon: Iconsax.logout,
                color: AppColors.error,
                type: 'attendance',
              ),
            );
          } catch (e) {
            debugPrint('Error parsing check-out time: $e');
          }
        }
      }

      // 4. Sort by timestamp descending
      combined.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // 5. Fetch pending approval buckets (role-gated). These surface as
      // notifications so approvers see a bell badge until they act on them.
      final approvalActivities = await _fetchApprovalActivities(
        token,
        role,
        canBranchPayroll,
      );

      // 6. Pending approvals first (most urgent), then recent activity.
      _activities = [...approvalActivities, ...combined.take(10)];
      _unreadCount = _activities.length;
    } catch (e) {
      _errorMessage = 'Error fetching activity: $e';
      debugPrint(_errorMessage);
     } finally {
       _isLoading = false;
       notifyListeners();
     }
   }

  Future<List<DashboardActivity>> _fetchApprovalActivities(
    String token,
    UserRole? role,
    bool canBranchPayroll,
  ) async {
    if (role == null) return const [];

    final now = DateTime.now();
    final results = <DashboardActivity>[];
    final futures = <Future<void>>[];

    final isAdmin = role == UserRole.admin;

    _leavePendingCount = 0;
    _regularizationPendingCount = 0;
    _onboardingPendingCount = 0;
    _branchPayrollPendingCount = 0;

    // Leave approvals — director / manager / admin / hrAdmin / hoHr
    if (role.canApproveLeaves || isAdmin) {
      futures.add(ApiService.getLeaveApprovals(token).then((list) {
        final pending = list
            .where((l) => l.status.toLowerCase() == 'pending')
            .length;
        _leavePendingCount = pending;
        if (pending > 0) {
          results.add(DashboardActivity(
            title:
                '$pending pending leave approval${pending == 1 ? '' : 's'}',
            timestamp: now,
            icon: Iconsax.task_square,
            color: AppColors.warning,
            type: 'leave_approval',
          ));
        }
      }).catchError((e) {
        debugPrint('leave approvals: $e');
      }));
    }

    // Regularization approvals — any approver role (admin, managers, HR).
    // We just try and ignore failures; the API is gated server-side anyway.
    if (role.canApproveLeaves || isAdmin) {
      futures.add(ApiService.getRegularizationApprovals(token).then((resp) {
        if (!resp.isSuccess || resp.data == null) return;
        final data = resp.data!;
        final raw = data['data'] ??
            data['pending_requests'] ??
            data['pending'] ??
            const [];
        final count = raw is List ? raw.length : 0;
        _regularizationPendingCount = count;
        if (count > 0) {
          results.add(DashboardActivity(
            title:
                '$count pending regularization request${count == 1 ? '' : 's'}',
            timestamp: now,
            icon: Iconsax.calendar_tick,
            color: AppColors.warning,
            type: 'regularize_approval',
          ));
        }
      }).catchError((e) {
        debugPrint('regularize approvals: $e');
      }));
    }

    // Onboarding approvals — director / admin / manager
    if (role.canApproveOnboarding) {
      futures.add(ApiService.getOnboardingApprovals(token).then((resp) {
        if (!resp.isSuccess || resp.data == null) return;
        final levelMap =
            resp.data!['levelWiseData'] as Map<String, dynamic>? ?? const {};
        var count = 0;
        for (final v in levelMap.values) {
          if (v is List) count += v.length;
        }
        _onboardingPendingCount = count;
        if (count > 0) {
          results.add(DashboardActivity(
            title:
                '$count pending onboarding approval${count == 1 ? '' : 's'}',
            timestamp: now,
            icon: Iconsax.user_add,
            color: AppColors.warning,
            type: 'onboarding_approval',
          ));
        }
      }).catchError((e) {
        debugPrint('onboarding approvals: $e');
      }));
    }

    // Branch payroll approvals — admins or users with the permission (the
    // dashboard tile is gated the same way). The list length is the pending
    // count surfaced on the tile badge.
    if (canBranchPayroll) {
      futures.add(ApiService.getBranchPayrollApprovals(token).then((list) {
        final count = list.length;
        _branchPayrollPendingCount = count;
        if (count > 0) {
          results.add(DashboardActivity(
            title:
                '$count pending branch payroll approval${count == 1 ? '' : 's'}',
            timestamp: now,
            icon: Iconsax.money_recive,
            color: AppColors.warning,
            type: 'branch_payroll_approval',
          ));
        }
      }).catchError((e) {
        debugPrint('branch payroll approvals: $e');
      }));
    }

    await Future.wait(futures);
    return results;
  }
 
   Future<void> fetchBirthdays(String token) async {
     try {
       final response = await ApiService.getEmployees(token);
       if (response.isSuccess && response.data != null) {
         final allEmployees = ApiService.parseEmployeesFromResponse(response.data!);
         
         final now = DateTime.now();
         _birthdayEmployees = allEmployees.where((emp) {
           if (emp.dob == null) return false;
           return emp.dob!.day == now.day && emp.dob!.month == now.month;
         }).toList();
         
         notifyListeners();
       }
     } catch (e) {
       debugPrint('Error fetching birthdays: $e');
     }
   }

  DateTime _parseTime(DateTime date, String timeStr) {
    try {
      // timeStr is usually "HH:mm:ss" or "HH:mm"
      final parts = timeStr.trim().split(':');
      if (parts.length < 2) return date;
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      return DateTime(date.year, date.month, date.day, hour, minute);
    } catch (e) {
      debugPrint('Error parsing time: $timeStr - $e');
      return date;
    }
  }

  IconData _getLeaveIcon(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Iconsax.tick_circle;
      case 'rejected':
        return Iconsax.close_circle;
      default:
        return Iconsax.calendar_tick;
    }
  }

  Color _getLeaveColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return AppColors.success;
      case 'rejected':
        return AppColors.error;
      default:
        return AppColors.warning;
    }
  }
}
