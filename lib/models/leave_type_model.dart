class LeaveType {
  final int id;
  final String leaveName;
  final String shortName;
  final String gender;
  final double maxLeave;
  final double presentDays;
  final double completeHours;
  final double minService;
  final String leaveCaFw;
  final double? caFwMaxLeave;
  final String leaveEncashment;
  final double? encashMinLeave;
  final double? encashMaxLeave;
  final double? encashMinService;
  final int aId;
  final int delete;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  LeaveType({
    required this.id,
    required this.leaveName,
    required this.shortName,
    required this.gender,
    required this.maxLeave,
    required this.presentDays,
    required this.completeHours,
    required this.minService,
    required this.leaveCaFw,
    this.caFwMaxLeave,
    required this.leaveEncashment,
    this.encashMinLeave,
    this.encashMaxLeave,
    this.encashMinService,
    required this.aId,
    required this.delete,
    this.createdAt,
    this.updatedAt,
  });

  factory LeaveType.fromJson(Map<String, dynamic> json) {
    return LeaveType(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id'].toString()) ?? 0,
      leaveName: json['leave_name']?.toString() ?? '',
      shortName: json['short_name']?.toString() ?? '',
      gender: json['gender']?.toString() ?? '',
      maxLeave: double.tryParse(json['max_leave']?.toString() ?? '0') ?? 0.0,
      presentDays:
          double.tryParse(json['present_days']?.toString() ?? '0') ?? 0.0,
      completeHours:
          double.tryParse(json['complete_hours']?.toString() ?? '0') ?? 0.0,
      minService:
          double.tryParse(json['min_service']?.toString() ?? '0') ?? 0.0,
      leaveCaFw: json['leave_ca_fw']?.toString() ?? '',
      caFwMaxLeave: json['ca_fw_max_leave'] != null
          ? double.tryParse(json['ca_fw_max_leave'].toString())
          : null,
      leaveEncashment: json['leave_encashment']?.toString() ?? '',
      encashMinLeave: json['encash_min_leave'] != null
          ? double.tryParse(json['encash_min_leave'].toString())
          : null,
      encashMaxLeave: json['encash_max_leave'] != null
          ? double.tryParse(json['encash_max_leave'].toString())
          : null,
      encashMinService: json['encash_min_service'] != null
          ? double.tryParse(json['encash_min_service'].toString())
          : null,
      aId: json['a_id'] is int
          ? json['a_id']
          : int.tryParse(json['a_id'].toString()) ?? 0,
      delete: json['delete'] is int
          ? json['delete']
          : int.tryParse(json['delete'].toString()) ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }
}
