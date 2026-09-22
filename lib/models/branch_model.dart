class BranchModel {
  final int id;
  final String branchName;
  final double? latitude;
  final double? longitude;
  final int? geofenceRadiusM;

  BranchModel({
    required this.id,
    required this.branchName,
    this.latitude,
    this.longitude,
    this.geofenceRadiusM,
  });

  factory BranchModel.fromJson(Map<String, dynamic> json) {
    double? toDouble(dynamic v) =>
        v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));
    int? toInt(dynamic v) =>
        v == null ? null : (v is num ? v.toInt() : int.tryParse(v.toString()));

    return BranchModel(
      id: json['id'] as int,
      branchName: (json['branch_name'] ?? json['name'] ?? '').toString(),
      latitude: toDouble(json['latitude']),
      longitude: toDouble(json['longitude']),
      geofenceRadiusM: toInt(json['geofence_radius_m'] ?? json['radius_m']),
    );
  }

  @override
  String toString() => branchName;
}
