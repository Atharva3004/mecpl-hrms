// Office Configuration for Geofencing — LEGACY FALLBACK.
//
// Superseded by [GeofenceRepository] which loads per-employee branch geofence
// from `GET /me/geofence`. These hard-coded constants remain only as a fallback
// for first launch (before the repository has hydrated) and will be removed
// once the backend rollout is complete.
//
// See docs/geofencing-backend-integration.md §5.2.

@Deprecated('Use GeofenceRepository (fed by GET /me/geofence) instead.')
class OfficeConfig {
  // Office location coordinates
  static const double officeLatitude = 18.5743404;
  static const double officeLongitude = 73.7736299;
  static const String officeName = 'MECPL Office';
  static const String officeAddress = 'Office Location';

  // Geofence radius in meters
  static const double geofenceRadius = 50.0;

  // Location tracking settings
  static const int trackingIntervalSeconds = 10;
  static const double locationAccuracyThreshold = 50.0;

  // Helper method to get office coordinates
  static Map<String, double> getOfficeCoordinates() {
    return {'latitude': officeLatitude, 'longitude': officeLongitude};
  }
}
