// Location Service - GPS & Geofence
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../core/config/office_config.dart';
import '../models/location_point_model.dart';
import '../repositories/geofence_repository.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  // Check if location services are enabled
  Future<bool> isLocationEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  // Check and request location permission
  Future<bool> checkPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  // Get current position
  Future<Position?> getCurrentPosition() async {
    try {
      bool hasPermission = await checkPermission();
      if (!hasPermission) return null;

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e) {
      print('Error getting position: $e');
      return null;
    }
  }

  // Calculate distance between two coordinates (Haversine formula)
  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // meters
    double dLat = _toRadians(lat2 - lat1);
    double dLon = _toRadians(lon2 - lon1);

    double a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  double _toRadians(double degree) {
    return degree * pi / 180;
  }

  // Check if position is inside the employee's assigned-branch geofence.
  //
  // Source of truth is [GeofenceRepository] (hydrated from `/me/geofence`).
  // Falls back to the legacy [OfficeConfig] constants if the repository has
  // no cached geofence yet — this keeps punch screens working on first launch
  // before the `/me/geofence` call has completed.
  Future<Map<String, dynamic>> checkGeofenceStatus(Position position) async {
    final repo = GeofenceRepository();
    await repo.loadCached();
    final branch = repo.cached;

    double distance;
    bool isInside;
    String branchName;

    if (branch != null) {
      final result = repo.check(position.latitude, position.longitude);
      distance = result.distanceM;
      isInside = result.inside;
      branchName = branch.branchName;
    } else {
      distance = calculateDistance(
        position.latitude,
        position.longitude,
        // ignore: deprecated_member_use_from_same_package
        OfficeConfig.officeLatitude,
        // ignore: deprecated_member_use_from_same_package
        OfficeConfig.officeLongitude,
      );
      // ignore: deprecated_member_use_from_same_package
      isInside = distance <= OfficeConfig.geofenceRadius;
      // ignore: deprecated_member_use_from_same_package
      branchName = OfficeConfig.officeName;
    }

    return {
      'isInside': isInside,
      'distance': distance,
      'message': isInside
          ? 'Inside $branchName'
          : '${distance.toInt()}m away from $branchName',
    };
  }

  // Get address from coordinates
  Future<String?> getAddressFromCoordinates(double lat, double lng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        return '${place.locality}, ${place.administrativeArea}';
      }
    } catch (e) {
      print('Error getting address: $e');
    }
    return null;
  }

  // Get location stream for tracking
  Stream<Position> getLocationStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      ),
    );
  }

  // Calculate total distance from list of points
  double calculateTotalDistance(List<LocationPoint> points) {
    if (points.length < 2) return 0;

    double totalDistance = 0;
    for (int i = 0; i < points.length - 1; i++) {
      totalDistance += calculateDistance(
        points[i].latitude,
        points[i].longitude,
        points[i + 1].latitude,
        points[i + 1].longitude,
      );
    }

    return totalDistance;
  }
}
