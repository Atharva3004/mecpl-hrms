import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/location_service.dart';
import '../../services/background_location_service.dart';
import '../../core/config/office_config.dart';
import '../../repositories/geofence_repository.dart';
import '../../core/theme/app_colors.dart';
import 'punch_history_screen.dart';

class AttendanceMapScreen extends StatefulWidget {
  final double? targetLat;
  final double? targetLng;

  const AttendanceMapScreen({super.key, this.targetLat, this.targetLng});

  @override
  State<AttendanceMapScreen> createState() => _AttendanceMapScreenState();
}

class _AttendanceMapScreenState extends State<AttendanceMapScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Circle> _circles = {};
  final Set<Polyline> _polylines = {};
  CameraPosition _initialCameraPosition = const CameraPosition(
    target: LatLng(28.6139, 77.2090),
    zoom: 15,
  );

  @override
  void initState() {
    super.initState();
    if (widget.targetLat != null && widget.targetLng != null) {
      _initialCameraPosition = CameraPosition(
        target: LatLng(widget.targetLat!, widget.targetLng!),
        zoom: 16,
      );
    } else {
      // Center on user's current location when opened from dashboard
      final provider = context.read<AttendanceProvider>();
      final pos = provider.currentPosition;
      if (pos != null) {
        _initialCameraPosition = CameraPosition(
          target: LatLng(pos['latitude']!, pos['longitude']!),
          zoom: 16,
        );
      } else {
        // Position not yet available — fetch then recenter
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final position = await LocationService().getCurrentPosition();
          if (position == null || !mounted) return;
          final p = {
            'latitude': position.latitude,
            'longitude': position.longitude,
          };
          if (_mapController != null) {
            _mapController!.animateCamera(
              CameraUpdate.newLatLngZoom(
                LatLng(p['latitude']!, p['longitude']!),
                16,
              ),
            );
          }
          _addUserMarker(p);
          setState(() {});
        });
      }
    }
    _initializeMap();
  }

  /// Draws the office pin and the geofence ring from the employee's **own
  /// branch** ([GeofenceRepository], fed by `GET /me/geofence`).
  ///
  /// Falls back to the legacy `OfficeConfig` constants only while the
  /// repository is still cold — previously this screen read OfficeConfig
  /// unconditionally, so every employee saw the Pune HQ pin and a 50 m ring
  /// no matter which branch they belonged to.
  ///
  /// When the branch is known but has no radius configured, the pin is drawn
  /// and the ring is omitted: there is no fence to show, and inventing one
  /// would misrepresent where the employee is allowed to punch.
  void _applyBranchGeofence() {
    final fence = GeofenceRepository().cached;
    final hasBranchCoords = fence?.latitude != null && fence?.longitude != null;

    // ignore: deprecated_member_use_from_same_package
    final centerLat = hasBranchCoords ? fence!.latitude! : OfficeConfig.officeLatitude;
    // ignore: deprecated_member_use_from_same_package
    final centerLng = hasBranchCoords ? fence!.longitude! : OfficeConfig.officeLongitude;
    final center = LatLng(centerLat, centerLng);

    final title = (hasBranchCoords && fence!.branchName.isNotEmpty)
        ? fence.branchName
        // ignore: deprecated_member_use_from_same_package
        : OfficeConfig.officeName;

    // Replace rather than add — this runs again once the cache hydrates, and
    // a Marker/Circle with the same id but a different position would
    // otherwise sit alongside the stale one.
    _markers.removeWhere((m) => m.markerId.value == 'office');
    _markers.add(
      Marker(
        markerId: const MarkerId('office'),
        position: center,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: title,
          snippet: hasBranchCoords
              ? 'Your assigned branch'
              // ignore: deprecated_member_use_from_same_package
              : OfficeConfig.officeAddress,
        ),
      ),
    );

    _circles.removeWhere((c) => c.circleId.value == 'geofence');

    // Only ring a fence that actually exists. `isEnforced` requires
    // lat + lng + a positive radius; a branch with no radius configured has
    // no enforceable boundary.
    final double? radius = fence == null
        // ignore: deprecated_member_use_from_same_package
        ? OfficeConfig.geofenceRadius
        : (fence.isEnforced ? fence.radiusM!.toDouble() : null);
    if (radius == null) return;

    _circles.add(
      Circle(
        circleId: const CircleId('geofence'),
        center: center,
        radius: radius,
        fillColor: AppColors.primary.withOpacity(0.1),
        strokeColor: AppColors.primary,
        strokeWidth: 2,
      ),
    );
  }

  void _initializeMap() {
    final provider = context.read<AttendanceProvider>();

    _applyBranchGeofence();

    // The repository may not have been read off disk yet on a cold start.
    // Hydrate it, then redraw so the ring lands on the right branch instead
    // of staying on the OfficeConfig fallback.
    if (GeofenceRepository().cached == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await GeofenceRepository().loadCached();
        if (!mounted || GeofenceRepository().cached == null) return;
        setState(_applyBranchGeofence);
      });
    }

    // Add user location marker if available
    if (provider.currentPosition != null) {
      _addUserMarker(provider.currentPosition!);
    }

    // Add target punch location marker if provided
    if (widget.targetLat != null && widget.targetLng != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('punchLocation'),
          position: LatLng(widget.targetLat!, widget.targetLng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
          infoWindow: const InfoWindow(
            title: 'Punch Location',
            snippet: 'Location where sequence occurred',
          ),
        ),
      );
    }

    // Add route polyline if tracking
    if (provider.trackedRoute.isNotEmpty) {
      _updateRoutePolyline(provider.trackedRoute);
    }

    // Load today's saved tracking + punch points onto the map
    _loadTodaysTrackedPoints();

    setState(() {});
  }

  Future<void> _loadTodaysTrackedPoints() async {
    final userId = context.read<AuthProvider>().currentUser?.id;
    if (userId == null) return;

    final points = await BackgroundLocationService().getLocationPoints(
      userId,
      date: DateTime.now(),
    );
    if (points.isEmpty || !mounted) return;

    final routePoints = <LatLng>[];
    for (final p in points) {
      final pos = LatLng(p.latitude, p.longitude);
      routePoints.add(pos);

      double hue;
      switch (p.type) {
        case 'In':
          hue = BitmapDescriptor.hueGreen;
          break;
        case 'Out':
          hue = BitmapDescriptor.hueRose;
          break;
        default:
          hue = BitmapDescriptor.hueAzure;
      }

      // Battery at the moment this point was captured. A Maps InfoWindow
      // renders plain text only, so it goes in the title beside the time it
      // belongs to. Omitted when unknown — a missing reading is not a flat
      // battery, and on a location trail that difference is what explains a
      // gap.
      final battery = p.batteryLabel;
      final markerTitle = battery == null
          ? '${p.type} · ${p.formattedTime}'
          : '${p.type} · ${p.formattedTime} · 🔋 $battery';

      _markers.add(
        Marker(
          markerId: MarkerId('tracked_${p.id}'),
          position: pos,
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          infoWindow: InfoWindow(
            title: markerTitle,
            snippet: p.address,
          ),
        ),
      );
    }

    if (routePoints.length >= 2) {
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('today_route'),
          points: routePoints,
          color: AppColors.primary,
          width: 3,
        ),
      );
    }

    setState(() {});
  }

  void _addUserMarker(Map<String, double> position) {
    _markers.removeWhere((m) => m.markerId.value == 'user');
    _markers.add(
      Marker(
        markerId: const MarkerId('user'),
        position: LatLng(position['latitude']!, position['longitude']!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: const InfoWindow(
          title: 'Your Location',
          snippet: 'Current position',
        ),
      ),
    );
  }

  void _updateRoutePolyline(List<Map<String, double>> route) {
    if (route.isEmpty) return;

    final points = route
        .map((point) => LatLng(point['latitude']!, point['longitude']!))
        .toList();

    _polylines.clear();
    _polylines.add(
      Polyline(
        polylineId: const PolylineId('route'),
        points: points,
        color: Colors.red,
        width: 4,
      ),
    );

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isTracking = context.watch<AttendanceProvider>().isTrackingLocation;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Live Tracking',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: Colors.black87),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PunchHistoryScreen()),
              );
            },
          ),
          if (isTracking)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'REC',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: GoogleMap(
        initialCameraPosition: _initialCameraPosition,
        markers: _markers,
        circles: _circles,
        polylines: _polylines,
        onMapCreated: (controller) {
          _mapController = controller;
        },
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        zoomControlsEnabled: false,
      ),
    );
  }
}
