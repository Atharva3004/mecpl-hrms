class LeaveInfoResponse {
  final bool success;
  final LeaveInfoEmployee? employee;
  final LeaveInfoData? leave;
  final List<ApprovalTrailItem> approvalTrail;
  final List<LeaveHistoryItem> history;
  final List<dynamic> othersOnLeave;
  final String? yearType;
  final List<LeaveHistoryItem> previousHistory;

  /// Returns history items, falling back to previousHistory if history is empty.
  List<LeaveHistoryItem> get allHistory =>
      history.isNotEmpty ? history : previousHistory;

  LeaveInfoResponse({
    required this.success,
    this.employee,
    this.leave,
    required this.approvalTrail,
    required this.history,
    required this.othersOnLeave,
    this.yearType,
    required this.previousHistory,
  });

  factory LeaveInfoResponse.fromJson(Map<String, dynamic> json) {
    return LeaveInfoResponse(
      success: json['success'] ?? false,
      employee: json['employee'] != null
          ? LeaveInfoEmployee.fromJson(json['employee'])
          : null,
      leave: json['leave'] != null
          ? LeaveInfoData.fromJson(json['leave'])
          : null,
      approvalTrail: (json['approvalTrail'] as List? ?? [])
          .map((item) {
            try {
              return ApprovalTrailItem.fromJson(item);
            } catch (_) {
              return null;
            }
          })
          .whereType<ApprovalTrailItem>()
          .toList(),
      history: (json['history'] as List? ?? [])
          .map((item) {
            try {
              return LeaveHistoryItem.fromJson(item);
            } catch (_) {
              return null;
            }
          })
          .whereType<LeaveHistoryItem>()
          .toList(),
      othersOnLeave: json['othersOnLeave'] as List? ?? [],
      yearType: json['yearType']?.toString(),
      previousHistory: (json['previousHistory'] as List? ?? [])
          .map((item) {
            try {
              return LeaveHistoryItem.fromJson(item);
            } catch (_) {
              return null;
            }
          })
          .whereType<LeaveHistoryItem>()
          .toList(),
    );
  }
}

class LeaveInfoEmployee {
  final int id;
  final String name;
  final String? photo;
  final String gender;
  final String empCode;
  final String designation;
  final String department;
  final String branch;
  final int branchId;
  final List<dynamic> balances;

  LeaveInfoEmployee({
    required this.id,
    required this.name,
    this.photo,
    required this.gender,
    required this.empCode,
    required this.designation,
    required this.department,
    required this.branch,
    required this.branchId,
    required this.balances,
  });

  factory LeaveInfoEmployee.fromJson(Map<String, dynamic> json) {
    return LeaveInfoEmployee(
      id: json['id'] ?? 0,
      name: json['name']?.toString() ?? '',
      photo: json['photo']?.toString(),
      gender: json['gender']?.toString() ?? '',
      empCode: json['emp_code']?.toString() ?? '',
      designation: json['designation']?.toString() ?? '',
      department: json['department']?.toString() ?? '',
      branch: json['branch']?.toString() ?? '',
      branchId: json['branch_id'] ?? 0,
      balances: json['balances'] as List? ?? [],
    );
  }
}

class LeaveInfoData {
  final int id;
  final String type;
  final String typeShort;
  final String category;
  final String fromDate;
  final String toDate;
  final int days;
  final double netLeaveDays;
  final String paidDays;
  final String unpaidDays;
  final String halfDay;
  final String reason;
  final String appliedOn;
  final int currentLevel;
  final String status;

  LeaveInfoData({
    required this.id,
    required this.type,
    required this.typeShort,
    required this.category,
    required this.fromDate,
    required this.toDate,
    required this.days,
    required this.netLeaveDays,
    required this.paidDays,
    required this.unpaidDays,
    required this.halfDay,
    required this.reason,
    required this.appliedOn,
    required this.currentLevel,
    required this.status,
  });

  factory LeaveInfoData.fromJson(Map<String, dynamic> json) {
    return LeaveInfoData(
      id: json['id'] ?? 0,
      type: json['type']?.toString() ?? '',
      typeShort: json['type_short']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      fromDate: json['from_date']?.toString() ?? '',
      toDate: json['to_date']?.toString() ?? '',
      days: json['days'] ?? 0,
      netLeaveDays:
          double.tryParse(json['net_leave_days']?.toString() ?? '0') ?? 0.0,
      paidDays: json['paid_days']?.toString() ?? '0.0',
      unpaidDays: json['unpaid_days']?.toString() ?? '0.0',
      halfDay: json['half_day']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '',
      appliedOn: json['applied_on']?.toString() ?? '',
      currentLevel: json['current_level'] ?? 0,
      status: json['status']?.toString() ?? '',
    );
  }
}

class ApprovalTrailItem {
  final int level;
  final int approverId;
  final String approverName;
  final String status;
  final String? actionAt;
  final String? remarks;
  final bool isCurrent;

  ApprovalTrailItem({
    required this.level,
    required this.approverId,
    required this.approverName,
    required this.status,
    this.actionAt,
    this.remarks,
    required this.isCurrent,
  });

  factory ApprovalTrailItem.fromJson(Map<String, dynamic> json) {
    return ApprovalTrailItem(
      level: json['level'] ?? 0,
      approverId: json['approver_id'] ?? 0,
      approverName: json['approver_name']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      actionAt: json['action_at']?.toString(),
      remarks: json['remarks']?.toString(),
      isCurrent: json['is_current'] ?? false,
    );
  }
}

class LeaveHistoryItem {
  final String fromDate;
  final String toDate;
  final String type;
  final int days;
  final double netLeaveDays;
  final String status;
  final String reason;

  LeaveHistoryItem({
    required this.fromDate,
    required this.toDate,
    required this.type,
    required this.days,
    required this.netLeaveDays,
    required this.status,
    required this.reason,
  });

  factory LeaveHistoryItem.fromJson(Map<String, dynamic> json) {
    return LeaveHistoryItem(
      fromDate: json['from_date']?.toString() ?? '',
      toDate: json['to_date']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      days: json['days'] ?? 0,
      netLeaveDays:
          double.tryParse(json['net_leave_days']?.toString() ?? '0') ?? 0.0,
      status: json['status']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '',
    );
  }
}
