// Local Punch Record Model - Stores punch data with location (locally only)
enum PunchType { punchIn, punchOut }

class LocalPunchRecord {
  final String id;
  final DateTime timestamp;
  final PunchType type;
  final double latitude;
  final double longitude;
  final String? address;
  final String? selfieImagePath;
  final bool isInsideOffice;
  final double? distanceFromOffice;
  // Backend session this punch belongs to. Null until the API call returns
  // (or for legacy records from before session-based attendance).
  final int? sessionId;

  LocalPunchRecord({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.latitude,
    required this.longitude,
    this.address,
    this.selfieImagePath,
    required this.isInsideOffice,
    this.distanceFromOffice,
    this.sessionId,
  });

  LocalPunchRecord copyWith({int? sessionId, DateTime? timestamp}) =>
      LocalPunchRecord(
        id: id,
        timestamp: timestamp ?? this.timestamp,
        type: type,
        latitude: latitude,
        longitude: longitude,
        address: address,
        selfieImagePath: selfieImagePath,
        isInsideOffice: isInsideOffice,
        distanceFromOffice: distanceFromOffice,
        sessionId: sessionId ?? this.sessionId,
      );

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
      'sessionId': sessionId,
    };
  }

  factory LocalPunchRecord.fromJson(Map<String, dynamic> json) {
    return LocalPunchRecord(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      type: json['type'] == 'punchIn' ? PunchType.punchIn : PunchType.punchOut,
      latitude: json['latitude'] as double,
      longitude: json['longitude'] as double,
      address: json['address'] as String?,
      selfieImagePath: json['selfieImagePath'] as String?,
      isInsideOffice: json['isInsideOffice'] as bool,
      distanceFromOffice: (json['distanceFromOffice'] as num?)?.toDouble(),
      sessionId: (json['sessionId'] as num?)?.toInt(),
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

  String get coordinates {
    return '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
  }
}
