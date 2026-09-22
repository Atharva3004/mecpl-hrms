import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../../providers/location_history_provider.dart';

class EmployeeLocationMapScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const EmployeeLocationMapScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<EmployeeLocationMapScreen> createState() =>
      _EmployeeLocationMapScreenState();
}

class _EmployeeLocationMapScreenState extends State<EmployeeLocationMapScreen> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLocationPoints();
  }

  Future<void> _loadLocationPoints() async {
    final provider = Provider.of<LocationHistoryProvider>(
      context,
      listen: false,
    );
    // Reuse the points the list screen already loaded via
    // `loadFromTodaysSession` / `loadLatestPunchIn`. The user tapped "View on
    // Map" from a screen where data is already visible — refetching here
    // would double the round-trip and could race with the 60s polling loop.

    if (provider.locationPoints.isEmpty) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final points = provider.locationPoints;
    final markers = <Marker>{};
    final polylinePoints = <LatLng>[];

    for (int i = 0; i < points.length; i++) {
      final point = points[i];
      // Defensive: skip sentinel (0, 0) coordinates. LocationPoint requires
      // non-null lat/lng so this only fires if a backend response slipped in
      // placeholders. List view still shows the row; the map quietly omits it.
      if (point.latitude == 0 && point.longitude == 0) continue;
      final position = LatLng(point.latitude, point.longitude);
      polylinePoints.add(position);

      // Create marker based on type
      BitmapDescriptor markerColor;
      String markerTitle;

      if (i == points.length - 1) {
        // First point (oldest) - Green
        markerColor = BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueGreen,
        );
        markerTitle = 'Start: ${point.formattedTime}';
      } else if (i == 0) {
        // Last point (newest) - Yellow
        markerColor = BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueYellow,
        );
        markerTitle = 'End: ${point.formattedTime}';
      } else {
        // Intermediate points - Blue
        markerColor = BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueBlue,
        );
        markerTitle = '${point.type}: ${point.formattedTime}';
      }

      // Battery at the moment the ping was captured, Snapchat-style. A
      // Google Maps InfoWindow renders plain text only — no icons or rich
      // markup — so it goes in the title where it reads at a glance, next to
      // the time it belongs to.
      //
      // Omitted entirely when unknown: an absent reading is not a flat
      // battery, and on a location trail that distinction is what explains a
      // gap. Punch rows never carry one (the punch endpoints don't send it).
      final battery = point.batteryLabel;
      if (battery != null) {
        markerTitle = '$markerTitle · 🔋 $battery';
      }

      markers.add(
        Marker(
          markerId: MarkerId('point_${point.id}'),
          position: position,
          icon: markerColor,
          infoWindow: InfoWindow(title: markerTitle, snippet: point.address),
        ),
      );
    }

    // Two polylines stacked so the route reads clearly against any map tile:
    // a wider dark "shadow" underneath, then the saturated blue line on top.
    // Rounded caps + joints stop the corners from looking like sharp Vs.
    final routeShadow = Polyline(
      polylineId: const PolylineId('route_shadow'),
      points: polylinePoints,
      color: const Color(0xFF0D47A1).withValues(alpha: 0.55),
      width: 12,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
      jointType: JointType.round,
      zIndex: 1,
    );
    final route = Polyline(
      polylineId: const PolylineId('route'),
      points: polylinePoints,
      color: const Color(0xFF1976D2),
      width: 7,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
      jointType: JointType.round,
      zIndex: 2,
    );

    setState(() {
      _markers = markers;
      _polylines = {routeShadow, route};
      _isLoading = false;
    });

    // Fit map to show all markers
    if (markers.isNotEmpty && _mapController != null) {
      _fitMapToMarkers(markers);
    }
  }

  void _fitMapToMarkers(Set<Marker> markers) {
    if (markers.isEmpty) return;

    final bounds = _calculateBounds(markers);
    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
  }

  LatLngBounds _calculateBounds(Set<Marker> markers) {
    double minLat = 90;
    double maxLat = -90;
    double minLng = 180;
    double maxLng = -180;

    for (final marker in markers) {
      final lat = marker.position.latitude;
      final lng = marker.position.longitude;

      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2196F3),
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        title: Text(
          widget.userName,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _markers.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.location_off, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'No location data to display',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(18.5204, 73.8567), // Pune coordinates
                    zoom: 12,
                  ),
                  markers: _markers,
                  polylines: _polylines,
                  zoomControlsEnabled: false,
                  mapType: MapType.normal,
                  onMapCreated: (controller) {
                    _mapController = controller;
                    if (_markers.isNotEmpty) {
                      _fitMapToMarkers(_markers);
                    }
                  },
                ),

                // Zoom Controls
                Positioned(
                  right: 16,
                  bottom: 100,
                  child: Column(
                    children: [
                      _buildZoomButton(Icons.add, () {
                        _mapController?.animateCamera(CameraUpdate.zoomIn());
                      }),
                      const SizedBox(height: 8),
                      _buildZoomButton(Icons.remove, () {
                        _mapController?.animateCamera(CameraUpdate.zoomOut());
                      }),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildZoomButton(IconData icon, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.black87),
        iconSize: 24,
      ),
    );
  }
}
