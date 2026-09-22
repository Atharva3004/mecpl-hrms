class LeaveCalculationResponse {
  final bool success;
  final double totalDays;
  final double paidHolidays;
  final double weeklyOffs;
  final double netLeaveDays;
  final double balanceAvailable;
  final bool isExceeded;
  final double paidDays;
  final double unpaidDays;
  final List<dynamic> holidayList;
  final List<String> weeklyOffDates;
  final bool allDatesOff;
  final bool forceUnpaid;
  final bool hasDuplicate;
  final String? duplicateMessage;
  final bool salaryProcessed;
  final String? salaryMessage;
  final List<dynamic> compulsoryHolidays;
  final List<dynamic> optionalHolidays;

  LeaveCalculationResponse({
    required this.success,
    required this.totalDays,
    required this.paidHolidays,
    required this.weeklyOffs,
    required this.netLeaveDays,
    required this.balanceAvailable,
    required this.isExceeded,
    required this.paidDays,
    required this.unpaidDays,
    required this.holidayList,
    required this.weeklyOffDates,
    required this.allDatesOff,
    required this.forceUnpaid,
    required this.hasDuplicate,
    this.duplicateMessage,
    required this.salaryProcessed,
    this.salaryMessage,
    required this.compulsoryHolidays,
    required this.optionalHolidays,
  });

  factory LeaveCalculationResponse.fromJson(Map<String, dynamic> json) {
    return LeaveCalculationResponse(
      success: json['success'] ?? false,
      totalDays: double.tryParse(json['total_days']?.toString() ?? '0') ?? 0.0,
      paidHolidays:
          double.tryParse(json['paid_holidays']?.toString() ?? '0') ?? 0.0,
      weeklyOffs:
          double.tryParse(json['weekly_offs']?.toString() ?? '0') ?? 0.0,
      netLeaveDays:
          double.tryParse(json['net_leave_days']?.toString() ?? '0') ?? 0.0,
      balanceAvailable:
          double.tryParse(json['balance_available']?.toString() ?? '0') ?? 0.0,
      isExceeded: json['is_exceeded'] ?? false,
      paidDays: double.tryParse(json['paid_days']?.toString() ?? '0') ?? 0.0,
      unpaidDays:
          double.tryParse(json['unpaid_days']?.toString() ?? '0') ?? 0.0,
      holidayList: json['holiday_list'] ?? [],
      weeklyOffDates:
          (json['weekly_off_dates'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      allDatesOff: json['all_dates_off'] ?? false,
      forceUnpaid: json['force_unpaid'] ?? false,
      hasDuplicate: json['has_duplicate'] ?? false,
      duplicateMessage: json['duplicate_message']?.toString(),
      salaryProcessed: json['salary_processed'] ?? false,
      salaryMessage: json['salary_message']?.toString(),
      compulsoryHolidays: json['compulsoryHolidays'] ?? [],
      optionalHolidays: json['optionalHolidays'] ?? [],
    );
  }
}
