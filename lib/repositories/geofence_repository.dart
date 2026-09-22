import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../core/config/office_config.dart';

class Geofence {
  final int branchId;
  final String branchName;
  final double? latitude;
  final double? longitude;
  final int? radiusM;
  // Server-side switch. "Yes" → this branch uses geofence-based attendance
  // (user can punch in/out from the app). "No" → feature disabled for this
  // branch → app must hide the punch button.
  final String geofenceAttendance;

  Geofence({
    required this.branchId,
    required this.branchName,
    required this.latitude,
    required this.longitude,
    required this.radiusM,
    this.geofenceAttendance = 'No',
  });

  // Enforced only when branch has coordinates AND a positive radius configured.
  // A branch with null lat/lng/radius (not yet configured on the server) is
  // treated as "no fence" — punches are allowed from anywhere.
  bool get isEnforced =>
      latitude != null && longitude != null && radiusM != null && radiusM! > 0;

  /// True when the backend has opted this branch into app-based punching.
  bool get isAttendanceEnabled =>
      geofenceAttendance.toLowerCase() == 'yes';

  Map<String, dynamic> toJson() => {
        'branch_id': branchId,
        'branch_name': branchName,
        'latitude': latitude,
        'longitude': longitude,
        'radius_m': radiusM,
        'geofence_attendance': geofenceAttendance,
      };

  factory Geofence.fromJson(Map<String, dynamic> json) {
    double? toDOrNull(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    int? toIntOrNull(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    // The server nests the branch fields under `branch` and names the radius
    // `geofence_radius_m` (see docs/geofence-module-guide.md §3.1):
    //
    //   { "geofence_attendance": "Yes",
    //     "branch": { "id": 5, "branch_name": "...", "latitude": ...,
    //                 "longitude": ..., "geofence_radius_m": 200 } }
    //
    // The flat shape below is what `toJson` writes to SharedPreferences, so
    // both forms have to parse — `branch` for a fresh network payload, the
    // top level for the cache round-trip.
    final branch =
        json['branch'] is Map<String, dynamic> ? json['branch'] as Map<String, dynamic> : json;

    // Deliberately tolerant: a single missing or renamed key must never throw,
    // because the caller swallows exceptions and would silently discard the
    // whole geofence (which is exactly what `branch_id` used to do here —
    // it doesn't exist in the server payload, so `as num` threw on null and
    // nothing was ever cached).
    return Geofence(
      branchId: toIntOrNull(branch['id'] ?? json['branch_id']) ?? 0,
      branchName: (branch['branch_name'] ?? json['branch_name'] ?? '').toString(),
      latitude: toDOrNull(branch['latitude']),
      longitude: toDOrNull(branch['longitude']),
      radiusM: toIntOrNull(branch['geofence_radius_m'] ?? branch['radius_m']),
      geofenceAttendance: (json['geofence_attendance'] ?? 'No').toString(),
    );
  }
}

class GeofenceCheckResult {
  final bool inside;
  final double distanceM;
  final int? radiusM;

  GeofenceCheckResult({
    required this.inside,
    required this.distanceM,
    required this.radiusM,
  });
}

class GeofenceRepository {
  static const String _prefsKey = 'my_geofence_cache';

  static final GeofenceRepository _instance = GeofenceRepository._internal();
  factory GeofenceRepository() => _instance;
  GeofenceRepository._internal();

  Geofence? _cached;

  Geofence? get cached => _cached;

  Future<Geofence?> loadCached() async {
    if (_cached != null) return _cached;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      _cached = Geofence.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      return _cached;
    } catch (_) {
      await prefs.remove(_prefsKey);
      return null;
    }
  }

  Future<Geofence?> refresh(String token) async {
    final response = await ApiService.getMyGeofence(token);
    if (!response.isSuccess || response.data == null) return _cached;

    final raw = response.data!;
    final nested = raw['data'];
    final payload = nested is Map<String, dynamic> ? nested : raw;
    try {
      final geofence = Geofence.fromJson(payload);
      _cached = geofence;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(geofence.toJson()));
      return geofence;
    } catch (_) {
      return _cached;
    }
  }

  Future<void> clear() async {
    _cached = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  double distanceTo(double lat, double lng) {
    final g = _cached;
    if (g == null || g.latitude == null || g.longitude == null) {
      return double.infinity;
    }
    return _haversine(g.latitude!, g.longitude!, lat, lng);
  }

  bool isInside(double lat, double lng) {
    final g = _cached;
    if (g == null || !g.isEnforced) return true;
    return distanceTo(lat, lng) <= g.radiusM!;
  }

  GeofenceCheckResult check(double lat, double lng) {
    final g = _cached;

    // Office coordinates to measure against: prefer the server-provided branch
    // geofence; fall back to the legacy hard-coded office so we can still report
    // a real distance before /me/geofence has hydrated, or when the branch has
    // coordinates but no radius configured. Previously this returned a hardcoded
    // distance of 0 in those cases, which is why Punch History showed "0 m".
    // ignore: deprecated_member_use_from_same_package
    final double officeLat = g?.latitude ?? OfficeConfig.officeLatitude;
    // ignore: deprecated_member_use_from_same_package
    final double officeLng = g?.longitude ?? OfficeConfig.officeLongitude;

    final d = _haversine(officeLat, officeLng, lat, lng);

    // "Inside" is only meaningful when a positive radius is configured. With no
    // enforced fence the punch is still allowed, but we now report the real
    // measured distance instead of 0.
    final inside = (g != null && g.isEnforced) ? d <= g.radiusM! : true;

    return GeofenceCheckResult(inside: inside, distanceM: d, radiusM: g?.radiusM);
  }

  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRadians(double d) => d * pi / 180;
}
