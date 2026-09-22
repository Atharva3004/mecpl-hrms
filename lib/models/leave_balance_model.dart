import 'leave_type_model.dart';

class LeaveBalance {
  final int id;
  final int empId;
  final int leaveTypeId;
  final String year;
  final double balance;
  final double used;
  final double encashed;
  final DateTime createdAt;
  final DateTime updatedAt;
  final LeaveType leaveType;

  LeaveBalance({
    required this.id,
    required this.empId,
    required this.leaveTypeId,
    required this.year,
    required this.balance,
    required this.used,
    required this.encashed,
    required this.createdAt,
    required this.updatedAt,
    required this.leaveType,
  });

  factory LeaveBalance.fromJson(Map<String, dynamic> json) {
    return LeaveBalance(
      id: json['id'] as int,
      empId: json['emp_id'] is int
          ? json['emp_id']
          : int.parse(json['emp_id'].toString()),
      leaveTypeId: json['leave_type_id'] is int
          ? json['leave_type_id']
          : int.parse(json['leave_type_id'].toString()),
      year: json['year']?.toString() ?? '',
      balance: double.tryParse(json['balance']?.toString() ?? '0') ?? 0.0,
      used: double.tryParse(json['used']?.toString() ?? '0') ?? 0.0,
      encashed: double.tryParse(json['encashed']?.toString() ?? '0') ?? 0.0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      leaveType: LeaveType.fromJson(json['leave_type'] as Map<String, dynamic>),
    );
  }
}
