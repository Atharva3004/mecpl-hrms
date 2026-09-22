import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';

class SessionTimelineScreen extends StatefulWidget {
  final int sessionId;

  const SessionTimelineScreen({super.key, required this.sessionId});

  @override
  State<SessionTimelineScreen> createState() => _SessionTimelineScreenState();
}

class _SessionTimelineScreenState extends State<SessionTimelineScreen> {
  GoogleMapController? _mapController;
  bool _isLoading = true;
  String? _errorMessage;

  Map<String, dynamic>? _session;
  Map<String, dynamic>? _punchIn;
  Map<String, dynamic>? _punchOut;
  List<Map<String, dynamic>> _pings = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token = context.read<AuthProvider>().token;
    if (token == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Not logged in.';
      });
      return;
    }

    final response = await ApiService.getSessionTimeline(
      token: token,
      sessionId: widget.sessionId,
    );

    if (!mounted) return;

    if (!response.isSuccess || response.data == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = response.error ?? 'Failed to load timeline.';
      });
      return;
    }

    final raw = response.data!;
    final body = raw['data'] is Map<String, dynamic>
        ? raw['data'] as Map<String, dynamic>
        : raw;

    setState(() {
      _session = body['session'] as Map<String, dynamic>?;
      _punchIn = body['punch_in'] as Map<String, dynamic>?;
      _punchOut = body['punch_out'] as Map<String, dynamic>?;
      final pings = body['pings'];
      _pings = pings is List
          ? pings.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      _isLoading = false;
    });

    _fitMapToRoute();
  }

  // -------- Map helpers --------

  List<LatLng> get _routePoints {
    final pts = <LatLng>[];
    final inPt = _latLngFrom(_punchIn);
    if (inPt != null) pts.add(inPt);
    for (final p in _pings) {
      final pt = _latLngFrom(p);
      if (pt != null) pts.add(pt);
    }
    final outPt = _latLngFrom(_punchOut);
    if (outPt != null) pts.add(outPt);
    return pts;
  }

  LatLng? _latLngFrom(Map<String, dynamic>? m) {
    if (m == null) return null;
    final lat = (m['latitude'] as num?)?.toDouble();
    final lng = (m['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};
    final inPt = _latLngFrom(_punchIn);
    if (inPt != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('punch_in'),
          position: inPt,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(
            title: 'Punch In',
            snippet: _fmtTime(_punchIn?['captured_at'] ?? _punchIn?['timestamp']),
          ),
        ),
      );
    }
    final outPt = _latLngFrom(_punchOut);
    if (outPt != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('punch_out'),
          position: outPt,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: 'Punch Out',
            snippet:
                _fmtTime(_punchOut?['captured_at'] ?? _punchOut?['timestamp']),
          ),
        ),
      );
    }
    for (int i = 0; i < _pings.length; i++) {
      final pt = _latLngFrom(_pings[i]);
      if (pt == null) continue;
      markers.add(
        Marker(
          markerId: MarkerId('ping_$i'),
          position: pt,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(
            title: 'Ping ${i + 1}',
            snippet: _fmtTime(_pings[i]['captured_at']),
          ),
        ),
      );
    }
    return markers;
  }

  Set<Polyline> _buildPolylines() {
    final pts = _routePoints;
    if (pts.length < 2) return {};
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: pts,
        color: AppColors.primary,
        width: 4,
      ),
    };
  }

  void _fitMapToRoute() {
    final ctrl = _mapController;
    final pts = _routePoints;
    if (ctrl == null || pts.isEmpty) return;

    if (pts.length == 1) {
      ctrl.animateCamera(CameraUpdate.newLatLngZoom(pts.first, 16));
      return;
    }

    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    ctrl.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        60,
      ),
    );
  }

  // -------- Formatters --------

  String _fmtTime(dynamic raw) {
    if (raw == null) return '—';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      return DateFormat('hh:mm a').format(dt);
    } catch (_) {
      return raw.toString();
    }
  }

  String _fmtDateTime(dynamic raw) {
    if (raw == null) return '—';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
    } catch (_) {
      return raw.toString();
    }
  }

  /// Server names these `started_at` / `ended_at`
  /// (docs/geofence-module-guide.md §3.8); the `opened_at` / `closed_at`
  /// spellings are the older contract, kept as a fallback.
  dynamic get _sessionOpenedRaw =>
      _session?['started_at'] ?? _session?['opened_at'];
  dynamic get _sessionClosedRaw =>
      _session?['ended_at'] ?? _session?['closed_at'];

  String _durationStr() {
    final openedRaw = _sessionOpenedRaw;
    final closedRaw = _sessionClosedRaw;
    if (openedRaw == null) return '—';
    try {
      final opened = DateTime.parse(openedRaw.toString()).toLocal();
      final closed = closedRaw != null
          ? DateTime.parse(closedRaw.toString()).toLocal()
          : DateTime.now();
      final d = closed.difference(opened);
      final h = d.inHours;
      final m = d.inMinutes.remainder(60);
      return h > 0 ? '${h}h ${m}m' : '${m}m';
    } catch (_) {
      return '—';
    }
  }

  // -------- Build --------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBackground : AppColors.background;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Session #${widget.sessionId}',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _load,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildError(_errorMessage!)
              : _buildBody(isDark),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    final hasRoute = _routePoints.isNotEmpty;

    return Column(
      children: [
        // Map (top third)
        SizedBox(
          height: 260,
          child: hasRoute
              ? GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _routePoints.first,
                    zoom: 14,
                  ),
                  markers: _buildMarkers(),
                  polylines: _buildPolylines(),
                  zoomControlsEnabled: false,
                  myLocationButtonEnabled: false,
                  onMapCreated: (c) {
                    _mapController = c;
                    _fitMapToRoute();
                  },
                )
              : Container(
                  color: Colors.grey.shade200,
                  alignment: Alignment.center,
                  child: Text(
                    'No location data for this session',
                    style: GoogleFonts.poppins(color: Colors.grey.shade700),
                  ),
                ),
        ),
        // Timeline list
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSessionHeader(isDark),
              const SizedBox(height: 12),
              if (_punchIn != null)
                _buildPunchCard(
                  title: 'Punch In',
                  iconColor: AppColors.success,
                  icon: Iconsax.login,
                  data: _punchIn!,
                  isDark: isDark,
                ),
              const SizedBox(height: 12),
              _buildPingsSection(isDark),
              const SizedBox(height: 12),
              if (_punchOut != null)
                _buildPunchCard(
                  title: 'Punch Out',
                  iconColor: AppColors.error,
                  icon: Iconsax.logout,
                  data: _punchOut!,
                  isDark: isDark,
                )
              else
                _buildActiveBadge(isDark),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSessionHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Iconsax.clock, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                'Session Details',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _durationStr(),
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _headerRow(
            'Opened',
            _fmtDateTime(_sessionOpenedRaw),
          ),
          const SizedBox(height: 4),
          _headerRow(
            'Closed',
            _sessionClosedRaw == null
                ? 'In progress'
                : _fmtDateTime(_sessionClosedRaw),
          ),
          const SizedBox(height: 4),
          _headerRow(
            'Total Pings',
            _pings.length.toString(),
          ),
        ],
      ),
    );
  }

  Widget _headerRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: GoogleFonts.poppins(
              color: Colors.white.withOpacity(0.8),
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPunchCard({
    required String title,
    required Color iconColor,
    required IconData icon,
    required Map<String, dynamic> data,
    required bool isDark,
  }) {
    final lat = (data['latitude'] as num?)?.toDouble();
    final lng = (data['longitude'] as num?)?.toDouble();
    final address = data['address']?.toString();
    final time = data['captured_at'] ?? data['timestamp'];
    final insideGeofence = data['inside_geofence'];
    final distanceM = (data['distance_m'] as num?)?.toDouble();
    final selfieUrl = data['selfie_url']?.toString();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _fmtTime(time),
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (address != null && address.isNotEmpty)
                  Text(
                    address,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.textSecondary,
                    ),
                  ),
                if (lat != null && lng != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: isDark
                          ? AppColors.darkTextTertiary
                          : AppColors.textTertiary,
                    ),
                  ),
                ],
                if (insideGeofence != null) ...[
                  const SizedBox(height: 8),
                  _geofenceChip(insideGeofence == true, distanceM),
                ],
              ],
            ),
          ),
          if (selfieUrl != null && selfieUrl.isNotEmpty) ...[
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                selfieUrl,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 56,
                  height: 56,
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.broken_image, color: Colors.grey),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _geofenceChip(bool inside, double? distanceM) {
    final color = inside ? AppColors.success : AppColors.warning;
    final bg = inside ? AppColors.successLight : AppColors.warningLight;
    final label = inside
        ? 'Inside office'
        : distanceM != null
            ? '${distanceM.toInt()}m away'
            : 'Outside office';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildPingsSection(bool isDark) {
    if (_pings.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Iconsax.location_slash,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No location pings recorded for this session.',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Iconsax.routing, color: AppColors.info, size: 18),
              const SizedBox(width: 8),
              Text(
                'Location Pings (${_pings.length})',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._pings.asMap().entries.map((e) {
            final i = e.key;
            final p = e.value;
            final lat = (p['latitude'] as num?)?.toDouble();
            final lng = (p['longitude'] as num?)?.toDouble();
            final accuracy = (p['accuracy_m'] as num?)?.toDouble();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.infoLight,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${i + 1}',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.info,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _fmtTime(p['captured_at']),
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.textPrimary,
                          ),
                        ),
                        if (lat != null && lng != null)
                          Text(
                            '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'
                            '${accuracy != null ? '  ·  ±${accuracy.toInt()}m' : ''}',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: isDark
                                  ? AppColors.darkTextTertiary
                                  : AppColors.textTertiary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildActiveBadge(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Iconsax.flash_1, color: AppColors.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Session is still active. Punch-out will appear here once completed.',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: AppColors.warning,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
