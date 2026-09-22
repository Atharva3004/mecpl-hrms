// Location Point Model for Background Tracking History
class LocationPoint {
  final String id;
  final String userId;
  final DateTime timestamp;
  final String type; // 'In', 'Out', 'Tracking'
  final double latitude;
  final double longitude;
  final double accuracy;
  final String address;
  final String? selfiePath;
  final double? speed;

  /// Whether this point falls inside the user's branch geofence. Populated
  /// by the provider via [GeofenceRepository.check] when the geofence cache
  /// is hydrated. Null means "unknown" — the UI renders a neutral ribbon
  /// rather than guessing inside/outside.
  final bool? isInside;

  /// Distance in meters from the user's branch geofence center. Same
  /// semantics as [isInside] — null when the geofence cache is empty.
  final double? distanceM;

  /// Device battery level (0-100) when this point was captured, as reported
  /// by the phone that sent the ping.
  ///
  /// Null when unknown — which includes punch rows (the punch endpoints don't
  /// carry it) and any ping the server doesn't return it for. The UI must
  /// omit the badge entirely rather than render "null%": a missing reading is
  /// not the same as a flat battery, and on a location trail that difference
  /// matters when explaining a gap.
  final int? batteryPct;

  LocationPoint({
    required this.id,
    required this.userId,
    required this.timestamp,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.address,
    this.selfiePath,
    this.speed,
    this.isInside,
    this.distanceM,
    this.batteryPct,
  });

  LocationPoint copyWith({
    String? address,
    DateTime? timestamp,
    String? selfiePath,
  }) =>
      LocationPoint(
        id: id,
        userId: userId,
        timestamp: timestamp ?? this.timestamp,
        type: type,
        latitude: latitude,
        longitude: longitude,
        accuracy: accuracy,
        address: address ?? this.address,
        selfiePath: selfiePath ?? this.selfiePath,
        speed: speed,
        isInside: isInside,
        distanceM: distanceM,
        batteryPct: batteryPct,
      );

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'timestamp': timestamp.toIso8601String(),
      'type': type,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'address': address,
      'selfiePath': selfiePath,
      'speed': speed,
      'isInside': isInside,
      'distanceM': distanceM,
      'batteryPct': batteryPct,
    };
  }

  factory LocationPoint.fromJson(Map<String, dynamic> json) {
    return LocationPoint(
      id: json['id'] as String,
      userId: json['userId'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      type: json['type'] as String,
      latitude: json['latitude'] as double,
      longitude: json['longitude'] as double,
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0.0,
      address: json['address'] as String? ?? '',
      selfiePath: json['selfiePath'] as String?,
      speed: (json['speed'] as num?)?.toDouble(),
      isInside: json['isInside'] as bool?,
      distanceM: (json['distanceM'] as num?)?.toDouble(),
      batteryPct: (json['batteryPct'] as num?)?.toInt(),
    );
  }

  // Helper method to get formatted time
  String get formattedTime {
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  // Helper method to get truncated address
  String get truncatedAddress {
    if (address.length > 30) {
      return '${address.substring(0, 30)}...';
    }
    return address;
  }

  /// Battery reading for display, e.g. "72%". Null when unknown, so callers
  /// can drop the badge with a simple null check.
  String? get batteryLabel => batteryPct == null ? null : '$batteryPct%';

  /// Formatted "lat, lng" for display next to each row.
  String get coordinates =>
      '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
}
