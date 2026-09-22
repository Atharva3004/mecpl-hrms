// Regularization Request Model for HRMS
import 'package:intl/intl.dart';

class RegularizationRequest {
  final int id;
  final String employeeName;
  final String employeeCode;
  final String date;
  final String day;
  final String originalStatus;
  final String requestedInTime;
  final String requestedOutTime;
  final String actualInTime;
  final String actualOutTime;
  final String reasonType;
  final String comments;
  final String appliedOn;
  final String status; // Pending, Approved, Rejected

  RegularizationRequest({
    required this.id,
    required this.employeeName,
    required this.employeeCode,
    required this.date,
    required this.day,
    required this.originalStatus,
    required this.requestedInTime,
    required this.requestedOutTime,
    required this.actualInTime,
    required this.actualOutTime,
    required this.reasonType,
    required this.comments,
    required this.appliedOn,
    required this.status,
  });

  /// Whether the IN time was actually changed by the regularization request
  /// (requested differs from the originally punched time).
  bool get isInRegularized =>
      _shortTime(requestedInTime) != _shortTime(actualInTime);

  /// Whether the OUT time was actually changed by the regularization request.
  bool get isOutRegularized =>
      _shortTime(requestedOutTime) != _shortTime(actualOutTime);

  /// Display-friendly date e.g. "04 Apr 2026"
  String get displayDate {
    try {
      final parsed = DateTime.parse(date);
      return DateFormat('dd MMM yyyy').format(parsed);
    } catch (_) {
      try {
        final parsed = DateFormat('dd-MM-yyyy').parseStrict(date);
        return DateFormat('dd MMM yyyy').format(parsed);
      } catch (_) {
        return date;
      }
    }
  }

  /// Display-friendly applied-on date
  String get displayAppliedOn {
    try {
      final parsed = DateTime.parse(appliedOn);
      return DateFormat('dd MMM yyyy').format(parsed);
    } catch (_) {
      try {
        final parsed = DateFormat('dd-MM-yyyy').parse(appliedOn);
        return DateFormat('dd MMM yyyy').format(parsed);
      } catch (_) {
        return appliedOn;
      }
    }
  }

  /// Strip seconds from "HH:MM:SS" → "HH:MM"
  String _shortTime(String t) {
    if (t.isEmpty) return 'NA';
    final parts = t.split(':');
    if (parts.length >= 2) return '${parts[0]}:${parts[1]}';
    return t;
  }

  /// Requested times formatted as "HH:MM - HH:MM"
  String get requestedTimesDisplay =>
      '${_shortTime(requestedInTime)} - ${_shortTime(requestedOutTime)}';

  factory RegularizationRequest.fromJson(Map<String, dynamic> json) {
    final employee = json['employee'] is Map<String, dynamic>
        ? json['employee'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final companyDetails = employee['company_details'] is Map<String, dynamic>
        ? employee['company_details'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final dailyAttendance = json['daily_attendance'] is Map<String, dynamic>
        ? json['daily_attendance'] as Map<String, dynamic>
        : const <String, dynamic>{};

    final dateStr = (dailyAttendance['attendance_date'] ??
            json['date'] ??
            json['attendance_date'] ??
            '')
        .toString();

    String dayName = (json['day'] ?? dailyAttendance['day_name'] ?? '').toString();
    if (dayName.isEmpty && dateStr.isNotEmpty) {
      try {
        DateTime parsed;
        try {
          parsed = DateTime.parse(dateStr);
        } catch (_) {
          parsed = DateFormat('dd-MM-yyyy').parseStrict(dateStr);
        }
        dayName = DateFormat('EEEE').format(parsed);
      } catch (_) {
        dayName = '';
      }
    }

    final rawReason = (json['reason_type'] ?? json['reason'] ?? '').toString();
    final rawComments = (json['comments'] ?? '').toString();
    String reasonType = rawReason;
    String comments = rawComments;
    if (comments.isEmpty && rawReason.contains(' - ')) {
      final idx = rawReason.indexOf(' - ');
      reasonType = rawReason.substring(0, idx).trim();
      comments = rawReason.substring(idx + 3).trim();
    }

    return RegularizationRequest(
      id: int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      employeeName: (employee['emp_name'] ??
              json['employee_name'] ??
              json['emp_name'] ??
              '')
          .toString(),
      employeeCode: (companyDetails['emp_code'] ??
              json['employee_code'] ??
              json['emp_code'] ??
              '')
          .toString(),
      date: dateStr,
      day: dayName,
      originalStatus: (json['original_status'] ??
              dailyAttendance['status'] ??
              json['status'] ??
              '')
          .toString(),
      requestedInTime: (json['requested_in'] ??
              json['requested_in_time'] ??
              json['modified_in_time'] ??
              '')
          .toString(),
      requestedOutTime: (json['requested_out'] ??
              json['requested_out_time'] ??
              json['modified_out_time'] ??
              '')
          .toString(),
      actualInTime: (dailyAttendance['first_in'] ??
              json['first_in'] ??
              json['actual_in'] ??
              '')
          .toString(),
      actualOutTime: (dailyAttendance['last_out'] ??
              json['last_out'] ??
              json['actual_out'] ??
              '')
          .toString(),
      reasonType: reasonType,
      comments: comments,
      appliedOn: (json['applied_at'] ??
              json['applied_on'] ??
              json['created_at'] ??
              '')
          .toString(),
      status: (json['approval_status'] ??
              json['regularization_status'] ??
              'Pending')
          .toString(),
    );
  }
}
