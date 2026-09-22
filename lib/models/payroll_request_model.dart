// ─────────────────────────────────────────────────────────────────────────
// Branch Payroll Approval models
//
// Mirrors the `/branch-payroll-approvals` API. The list endpoint returns a
// summary per request; richer fields (DOJ, mobile, activity data, the full
// approval timeline) are optional and only populated when the backend sends
// them — the UI hides the corresponding sections when they are absent.
// ─────────────────────────────────────────────────────────────────────────

class PayrollRequest {
  final int id;
  final int empId;
  final String empCode;
  final String empName;
  final String designation;
  final String department;
  final String branch;
  final String doj;
  final String mobile;
  final String activityType;
  final String monthYear;
  final String appliedDate;
  final String status;

  /// Level bucket this request currently sits in (e.g. `level5`), taken from
  /// the API `data` map key. Empty when built outside the API.
  final String levelKey;

  /// Optional activity-specific key/value pairs (e.g. Release Date, Remarks).
  final Map<String, String> activityData;

  /// Optional L1-L5 approval timeline.
  final List<ApprovalStep> timeline;

  const PayrollRequest({
    required this.id,
    this.empId = 0,
    required this.empCode,
    required this.empName,
    required this.designation,
    required this.department,
    required this.branch,
    this.doj = '',
    this.mobile = '',
    required this.activityType,
    required this.monthYear,
    required this.appliedDate,
    required this.status,
    this.levelKey = '',
    this.activityData = const {},
    this.timeline = const [],
  });

  factory PayrollRequest.fromJson(
    Map<String, dynamic> json, {
    String levelKey = '',
  }) {
    String s(dynamic v) => v == null ? '' : v.toString();

    final month = s(json['request_month']);
    final year = s(json['request_year']);
    final monthYear = [month, year].where((e) => e.isNotEmpty).join(' ');

    // Optional richer fields — present only on the detail endpoint.
    final activityData = <String, String>{};
    final rawActivity = json['request_data'] ?? json['activity_data'];
    if (rawActivity is Map) {
      rawActivity.forEach((k, v) {
        final value = s(v);
        if (value.isNotEmpty) activityData[_prettifyKey(k.toString())] = value;
      });
    }

    final timeline = <ApprovalStep>[];
    final rawTimeline =
        json['approval_timeline'] ?? json['timeline'] ?? json['approvals'];
    if (rawTimeline is List) {
      for (final t in rawTimeline) {
        if (t is Map) {
          final label = s(t['label']);
          timeline.add(
            ApprovalStep(
              level: label.isNotEmpty ? label : 'L${s(t['level'])}',
              name: s(t['manager_name'] ?? t['name']),
              status: s(t['status']),
              remarks: s(t['remarks']),
              actionDate: s(t['action_date']),
            ),
          );
        }
      }
    }

    return PayrollRequest(
      id: int.tryParse(s(json['id'])) ?? 0,
      empId: int.tryParse(s(json['emp_id'])) ?? 0,
      empCode: s(json['emp_code']),
      empName: s(json['emp_name']),
      designation: s(json['designation']),
      department: s(json['department']),
      branch: s(json['branch']),
      doj: s(json['doj'] ?? json['date_of_joining']),
      mobile: s(json['mobile'] ?? json['mobile_no']),
      activityType: s(json['activity_type']),
      monthYear: monthYear,
      appliedDate: s(json['applied_date']),
      status: s(json['status']).isEmpty ? 'Pending' : s(json['status']),
      levelKey: levelKey,
      activityData: activityData,
      timeline: timeline,
    );
  }
}

/// Turns a snake_case API key into a Title Case label
/// (e.g. `release_date` → `Release Date`).
String _prettifyKey(String key) {
  return key
      .split(RegExp(r'[_\s]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}

class ApprovalStep {
  final String level;
  final String name;
  final String status;
  final String remarks;
  final String actionDate;

  const ApprovalStep({
    required this.level,
    required this.name,
    required this.status,
    this.remarks = '',
    this.actionDate = '',
  });
}
