// Today Attendance Model for HRMS
import 'package:intl/intl.dart';

class TodayAttendanceModel {
  final int id;
  final int empId;
  final String attendanceDate;
  final int? shiftId;
  final String? firstIn;
  final String? lastOut;
  final String? totalWorkHours;
  final String? breakHours;
  final String? otHours;
  final String status; // P, A, HD
  final int lateMinutes;
  final int earlyGoingMinutes;
  final bool isLate;
  final bool isEarlyGoing;
  final int? leaveTypeId;
  final String? remarks;
  final bool isRegularized;
  final int? punchCount;

  TodayAttendanceModel({
    required this.id,
    required this.empId,
    required this.attendanceDate,
    this.shiftId,
    this.firstIn,
    this.lastOut,
    this.totalWorkHours,
    this.breakHours,
    this.otHours,
    required this.status,
    this.lateMinutes = 0,
    this.earlyGoingMinutes = 0,
    this.isLate = false,
    this.isEarlyGoing = false,
    this.leaveTypeId,
    this.remarks,
    this.isRegularized = false,
    this.punchCount,
  });

  factory TodayAttendanceModel.fromJson(Map<String, dynamic> json) {
    return TodayAttendanceModel(
      id: json['id'] ?? 0,
      empId: json['emp_id'] ?? 0,
      attendanceDate: json['attendance_date']?.toString() ?? '',
      shiftId: json['shift_id'],
      firstIn: json['first_in']?.toString(),
      lastOut: json['last_out']?.toString(),
      totalWorkHours: json['total_work_hours']?.toString(),
      breakHours: json['break_hours']?.toString(),
      otHours: json['ot_hours']?.toString(),
      status: json['status']?.toString() ?? 'A',
      lateMinutes: json['late_minutes'] ?? 0,
      earlyGoingMinutes: json['early_going_minutes'] ?? 0,
      isLate: (json['is_late'] ?? 0) == 1,
      isEarlyGoing: (json['is_early_going'] ?? 0) == 1,
      leaveTypeId: json['leave_type_id'],
      remarks: json['remarks']?.toString(),
      isRegularized: (json['is_regularized'] ?? 0) == 1,
      punchCount: json['punch_count'],
    );
  }

  /// Convert "09:25:13" → "09:25 AM"
  String? get formattedFirstIn => _formatTime(firstIn);

  /// Convert "16:34:46" → "04:34 PM"
  String? get formattedLastOut => _formatTime(lastOut);

  String? _formatTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return null;
    try {
      final parts = timeStr.split(':');
      if (parts.length >= 2) {
        int hour = int.parse(parts[0]);
        int minute = int.parse(parts[1]);
        final dt = DateTime(2000, 1, 1, hour, minute);
        return DateFormat('hh:mm a').format(dt);
      }
    } catch (_) {}
    return timeStr;
  }

  /// Map status code to readable label
  String get statusLabel {
    switch (status.toUpperCase()) {
      case 'P':
        return 'Present';
      case 'A':
        return 'Absent';
      case 'HD':
        return 'Half Day';
      default:
        return status;
    }
  }

  /// Check if employee has punched in
  bool get hasPunchedIn => firstIn != null && firstIn!.isNotEmpty;

  /// Check if employee has punched out
  bool get hasPunchedOut => lastOut != null && lastOut!.isNotEmpty;
}
