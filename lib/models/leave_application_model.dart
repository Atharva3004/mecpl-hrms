import 'leave_type_model.dart';
import 'user_model.dart';

class LeaveApplication {
  final int id;
  final int empId;
  final int leaveTypeId;
  final String category;
  final DateTime fromDate;
  final DateTime toDate;
  final String halfDay;
  final String reason;
  final String status;
  final String? rejectionReason;
  final DateTime createdAt;
  final LeaveType leaveType;
  final UserModel? employee;
  final double netLeaveDays;

  LeaveApplication({
    required this.id,
    required this.empId,
    required this.leaveTypeId,
    required this.category,
    required this.fromDate,
    required this.toDate,
    required this.halfDay,
    required this.reason,
    required this.status,
    this.rejectionReason,
    required this.createdAt,
    required this.leaveType,
    this.employee,
    required this.netLeaveDays,
  });

  factory LeaveApplication.fromJson(Map<String, dynamic> json) {
    return LeaveApplication(
      id: json['id'] as int,
      empId: json['emp_id'] is int
          ? json['emp_id']
          : int.parse(json['emp_id'].toString()),
      leaveTypeId: json['leave_type_id'] is int
          ? json['leave_type_id']
          : int.parse(json['leave_type_id'].toString()),
      category:
          (json['leave_category'] ?? json['category'])?.toString() ?? 'Paid',
      fromDate: DateTime.parse(json['from_date'] as String),
      toDate: DateTime.parse(json['to_date'] as String),
      halfDay: json['half_day']?.toString() ?? 'Full Day',
      reason: json['reason']?.toString() ?? '',
      status: json['status']?.toString() ?? 'Pending',
      rejectionReason: json['rejection_reason']?.toString(),
      createdAt: DateTime.parse(json['created_at'] as String),
      leaveType: json['leave_type'] != null
          ? LeaveType.fromJson(json['leave_type'] as Map<String, dynamic>)
          : LeaveType(
              id: json['leave_type_id'] is int
                  ? json['leave_type_id']
                  : int.tryParse(json['leave_type_id']?.toString() ?? '0') ?? 0,
              leaveName: json['leave_name']?.toString() ?? 'Leave',
              shortName: json['short_name']?.toString() ?? 'L',
              gender: 'All',
              maxLeave: 0,
              presentDays: 0,
              completeHours: 0,
              minService: 0,
              leaveCaFw: 'No',
              leaveEncashment: 'No',
              aId: 0,
              delete: 0,
            ),
      employee: json['employee'] != null
          ? UserModel.fromJson(json['employee'] as Map<String, dynamic>)
          : (json['emp_name'] != null || json['name'] != null
              ? UserModel.fromJson(json)
              : null),
      netLeaveDays:
          double.tryParse(json['net_leave_days']?.toString() ?? '0') ?? 0.0,
    );
  }

  int get days {
    return toDate.difference(fromDate).inDays + 1;
  }
}
