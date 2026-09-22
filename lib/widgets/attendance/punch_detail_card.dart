import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/local_punch_record.dart';
import '../../screens/attendance/punch_view_screen.dart';

/// One row in the Punch History list.
///
/// Layout:
///   [ribbon] [selfie] [Punch In/Out label] [address]       [distance]
///                    [time]                                [coordinates]
///
/// The ribbon is a 6 px vertical strip on the left edge — green for a
/// punch-in record, red for a punch-out. Tapping anywhere on the card opens
/// the full-detail [PunchViewScreen].
class PunchDetailCard extends StatelessWidget {
  final LocalPunchRecord record;

  const PunchDetailCard({super.key, required this.record});

  static const _greenIn = Color(0xFF4CAF50);
  static const _redOut = Color(0xFFE53935);
  static const _muted = Color(0xFF666666);

  @override
  Widget build(BuildContext context) {
    final isIn = record.type == PunchType.punchIn;
    final accent = isIn ? _greenIn : _redOut;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PunchViewScreen(punchRecord: record),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left ribbon — 6 px green/red strip flush with the card edge.
              Container(width: 6, color: accent),

              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Selfie thumbnail (56×56, rounded). Falls back to a grey
                    // tile when the file is missing / URL is broken.
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _buildSelfieThumb(record.selfieImagePath, accent),
                    ),
                    const SizedBox(width: 12),

                    // Label column: "Punch In" / "Punch Out" on top, with
                    // the time directly underneath. Vertically centered
                    // against the selfie.
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.typeLabel,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.access_time,
                              size: 12,
                              color: _muted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              record.formattedTime,
                              style: GoogleFonts.poppins(
                                fontSize: 11.5,
                                color: _muted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
              ),

              // Middle column — address only (the time moved into the
              // label column on the left, so address sits centered here).
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    record.address ?? 'Address unavailable',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF222222),
                      height: 1.25,
                    ),
                  ),
                ),
              ),

              // Right column — distance (top) + coordinates (bottom),
              // right-aligned. Fixed-ish width so layout stays predictable
              // even when the address wraps to two lines.
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 12, 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      record.distanceFromOffice == null
                          ? '—'
                          : '${record.distanceFromOffice!.toInt()} m',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF222222),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      record.coordinates,
                      style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        color: _muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Renders the 56×56 selfie thumbnail. Accepts a local file path or a
  /// remote URL (set on records that have round-tripped through the backend).
  /// Shows a tinted placeholder when [source] is null/empty or the underlying
  /// image fails to load.
  Widget _buildSelfieThumb(String? source, Color tint) {
    const size = 56.0;
    Widget placeholder() => Container(
          width: size,
          height: size,
          color: const Color(0xFFF1F1F1),
          alignment: Alignment.center,
          child: Icon(
            Icons.person,
            size: 28,
            color: tint.withValues(alpha: 0.55),
          ),
        );

    if (source == null || source.isEmpty) return placeholder();

    final isUrl = source.startsWith('http://') || source.startsWith('https://');
    if (isUrl) {
      return Image.network(
        source,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder(),
      );
    }
    return Image.file(
      File(source),
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => placeholder(),
    );
  }
}
