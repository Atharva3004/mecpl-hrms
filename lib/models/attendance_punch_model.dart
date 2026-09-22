// Attendance Punch Model
enum PunchType { punchIn, punchOut }

class AttendancePunch {
  final String id;
  final DateTime timestamp;
  final PunchType type;
  final double latitude;
  final double longitude;
  final String? address;
  final String? selfieImagePath;
  final bool isInsideOffice;
  final double? distanceFromOffice;

  AttendancePunch({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.latitude,
    required this.longitude,
    this.address,
    this.selfieImagePath,
    required this.isInsideOffice,
    this.distanceFromOffice,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'type': type.name,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'selfieImagePath': selfieImagePath,
      'isInsideOffice': isInsideOffice,
      'distanceFromOffice': distanceFromOffice,
    };
  }

  factory AttendancePunch.fromJson(Map<String, dynamic> json) {
    return AttendancePunch(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      type: json['type'] == 'punchIn' ? PunchType.punchIn : PunchType.punchOut,
      latitude: json['latitude'] as double,
      longitude: json['longitude'] as double,
      address: json['address'] as String?,
      selfieImagePath: json['selfieImagePath'] as String?,
      isInsideOffice: json['isInsideOffice'] as bool,
      distanceFromOffice: (json['distanceFromOffice'] as num?)?.toDouble(),
    );
  }

  String get formattedTime {
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String get typeLabel {
    return type == PunchType.punchIn ? 'Punch In' : 'Punch Out';
  }
}
