import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';
import '../../models/local_punch_record.dart';
import '../../core/theme/app_colors.dart';
import 'attendance_map_screen.dart';

class PunchViewScreen extends StatelessWidget {
  final LocalPunchRecord punchRecord;

  const PunchViewScreen({super.key, required this.punchRecord});

  static const _green = Color(0xFF2E9E5B);
  static const _red = Color(0xFFE53935);
  static const _border = Color(0xFFECECEC);

  @override
  Widget build(BuildContext context) {
    final isIn = punchRecord.type == PunchType.punchIn;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Punch Details',
          style: GoogleFonts.poppins(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 17,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatusCard(isIn),
                  const SizedBox(height: 14),
                  // Selfie (left) + Location Details (right)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSelfie(),
                      const SizedBox(width: 12),
                      Expanded(child: _buildDetailsSection()),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Office status — full width
                  _buildOfficeStatus(),
                ],
              ),
            ),
          ),
          _buildActionButtons(context),
        ],
      ),
    );
  }

  // ── Status header ──────────────────────────────────────────────────────────
  Widget _buildStatusCard(bool isIn) {
    final accent = isIn ? _green : _red;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isIn ? Icons.login_rounded : Icons.logout_rounded,
              color: accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isIn ? 'Punch In' : 'Punch Out',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('EEEE, dd MMM yyyy').format(punchRecord.timestamp),
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Text(
            punchRecord.formattedTime,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  // ── Selfie ───────────────────────────────────────────────────────────────
  Widget _buildSelfie() {
    const w = 130.0;
    const h = 170.0;
    final source = punchRecord.selfieImagePath;
    final isUrl =
        source != null && (source.startsWith('http://') || source.startsWith('https://'));

    Widget image;
    if (source == null || source.isEmpty) {
      image = _buildImagePlaceholder(w, h);
    } else if (isUrl) {
      image = Image.network(
        source,
        width: w,
        height: h,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _buildImagePlaceholder(w, h),
      );
    } else {
      image = Image.file(
        File(source),
        width: w,
        height: h,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _buildImagePlaceholder(w, h),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: image,
    );
  }

  Widget _buildImagePlaceholder(double w, double h) {
    return Container(
      width: w,
      height: h,
      color: Colors.grey[200],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person, size: 44, color: Colors.grey[400]),
          const SizedBox(height: 6),
          Text(
            'No Selfie',
            style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  // ── Location details ───────────────────────────────────────────────────────
  Widget _buildDetailsSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Iconsax.location, color: AppColors.primary, size: 17),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Location Details',
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDetailRow(
            icon: Icons.location_on,
            label: 'GPS Coordinates',
            value: punchRecord.coordinates,
          ),
          if (punchRecord.address != null) ...[
            const SizedBox(height: 12),
            _buildDetailRow(
              icon: Icons.place,
              label: 'Address',
              value: punchRecord.address!,
            ),
          ],
          if (punchRecord.distanceFromOffice != null) ...[
            const SizedBox(height: 12),
            _buildDetailRow(
              icon: Icons.straighten,
              label: 'Distance from Office',
              value: '${punchRecord.distanceFromOffice!.toInt()} meters',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: AppColors.primary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOfficeStatus() {
    final inside = punchRecord.isInsideOffice;
    final accent = inside ? _green : _red;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            inside ? Icons.check_circle : Icons.warning_rounded,
            color: accent,
            size: 20,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Office Status',
                style: GoogleFonts.poppins(
                  fontSize: 10.5,
                  color: Colors.grey[600],
                ),
              ),
              Text(
                inside ? 'Inside Office' : 'Outside Office',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Bottom action ───────────────────────────────────────────────────────────
  Widget _buildActionButtons(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AttendanceMapScreen(
                  targetLat: punchRecord.latitude,
                  targetLng: punchRecord.longitude,
                ),
              ),
            );
          },
          icon: const Icon(Icons.map, size: 18),
          label: Text(
            'View on Map',
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary, width: 1.5),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }
}
