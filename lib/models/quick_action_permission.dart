// Catalog of dashboard quick-action buttons that an admin can toggle per user.
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

class QuickActionPermission {
  final String key;
  final String label;
  final IconData icon;
  final String section;

  const QuickActionPermission({
    required this.key,
    required this.label,
    required this.icon,
    required this.section,
  });
}

class QuickActionCatalog {
  static const List<QuickActionPermission> all = [
    // Attendance
    QuickActionPermission(
      key: 'my_attendance',
      label: 'My Attendance',
      icon: Iconsax.user_tick,
      section: 'Attendance',
    ),
    QuickActionPermission(
      key: 'regularize_attendance',
      label: 'Regularize Attendance',
      icon: Iconsax.calendar_tick,
      section: 'Attendance',
    ),
    QuickActionPermission(
      key: 'team_overview',
      label: 'Team Overview',
      icon: Iconsax.people,
      section: 'Attendance',
    ),
    QuickActionPermission(
      key: 'regularize_approvals',
      label: 'Regularize Approvals',
      icon: Iconsax.task_square,
      section: 'Attendance',
    ),
    QuickActionPermission(
      key: 'regularization_list',
      label: 'Regularization List',
      icon: Iconsax.clipboard_text,
      section: 'Attendance',
    ),
    QuickActionPermission(
      key: 'punch_history',
      label: 'Punch History',
      icon: Iconsax.clock,
      section: 'Attendance',
    ),
    QuickActionPermission(
      key: 'location_history',
      label: 'Location History',
      icon: Iconsax.location,
      section: 'Attendance',
    ),

    // Leave
    QuickActionPermission(
      key: 'apply_leave',
      label: 'Apply Leave',
      icon: Iconsax.add,
      section: 'Leave',
    ),
    QuickActionPermission(
      key: 'apply_employee_leave',
      label: 'Apply Employee Leave',
      icon: Iconsax.user_add,
      section: 'Leave',
    ),
    QuickActionPermission(
      key: 'leave_history',
      label: 'Leave History',
      icon: Iconsax.clipboard_text,
      section: 'Leave',
    ),
    QuickActionPermission(
      key: 'leave_approvals',
      label: 'Leave Approvals',
      icon: Iconsax.task_square,
      section: 'Leave',
    ),

    // Payroll
    QuickActionPermission(
      key: 'my_payslip',
      label: 'My Payslip',
      icon: Iconsax.receipt_2,
      section: 'Payroll',
    ),
    QuickActionPermission(
      key: 'employee_payslip',
      label: 'Employee Payslip',
      icon: Iconsax.receipt_1,
      section: 'Payroll',
    ),

    // Employee
    QuickActionPermission(
      key: 'employee_details',
      label: 'Employee Details',
      icon: Iconsax.user_search,
      section: 'Employee',
    ),
    QuickActionPermission(
      key: 'employee_onboarding',
      label: 'Employee Onboarding',
      icon: Iconsax.user_add,
      section: 'Employee',
    ),
  ];

  static Map<String, List<QuickActionPermission>> groupedBySection() {
    final Map<String, List<QuickActionPermission>> grouped = {};
    for (final action in all) {
      grouped.putIfAbsent(action.section, () => []).add(action);
    }
    return grouped;
  }
}
