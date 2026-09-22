// Shared "timing row" card used by Today's Timing and Punch History.
//
// One visual layout, two named constructors so callers can stay model-typed:
//   - TimingRowCard.fromPunch(LocalPunchRecord)  → Punch History / Today OFF
//   - TimingRowCard.fromPoint(LocationPoint)     → Today's Timing ON / OFF
//
// Layout: [ribbon] [photo] [label] | [address+time] | [distance+coords]
//
// Mirrors the visual rules of PunchDetailCard (left ribbon, 56×56 photo,
// label, two text columns) without coupling to LocalPunchRecord. See the
// internal _TimingRowLayout for the shared body.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../models/local_punch_record.dart';
import '../../models/location_point_model.dart';

class TimingRowCard extends StatelessWidget {
  final Color ribbonColor;
  final Widget photo;
  final String label;
  final Color labelColor;
  final String? dateText;
  final String address;
  final String time;

  /// Battery at capture time, e.g. "72%". Null when unknown — punch rows
  /// never carry one, and pings only do once the server returns the field.
  final String? batteryText;
  final String? distanceText;
  final String? coordsText;
  final VoidCallback? onTap;

  const TimingRowCard._({
    required this.ribbonColor,
    required this.photo,
    required this.label,
    required this.labelColor,
    required this.dateText,
    required this.address,
    required this.time,
    this.batteryText,
    required this.distanceText,
    required this.coordsText,
    required this.onTap,
  });

  /// Formats a timestamp as the short date ("03 Jun 2026") shown under the
  /// punch label.
  static String _dateLabel(DateTime t) =>
      DateFormat('dd MMM yyyy').format(t);

  /// Adapts a [LocalPunchRecord] (used by Punch History) to the shared row.
  factory TimingRowCard.fromPunch(
    LocalPunchRecord r, {
    VoidCallback? onTap,
  }) {
    final isIn = r.type == PunchType.punchIn;
    final color = isIn ? _greenIn : _redOut;
    return TimingRowCard._(
      ribbonColor: color,
      photo: _PhotoSlot.selfie(r.selfieImagePath, color),
      label: r.typeLabel,
      labelColor: color,
      dateText: _dateLabel(r.timestamp),
      address: (r.address ?? '').isEmpty ? 'Address unavailable' : r.address!,
      time: r.formattedTime,
      distanceText: r.distanceFromOffice == null
          ? null
          : '${r.distanceFromOffice!.toInt()} m',
      coordsText: r.coordinates,
      onTap: onTap,
    );
  }

  /// Adapts a [LocationPoint] (used by Today's Timing) to the shared row.
  /// [isInside] drives the ribbon color: null → grey (fence cache not
  /// hydrated), true → green, false → red. For punch In/Out the
  /// in/out type wins over the fence color so the row's leading
  /// signal remains the punch direction.
  factory TimingRowCard.fromPoint(
    LocationPoint p, {
    VoidCallback? onTap,
  }) {
    final isIn = p.type == 'In';
    final isOut = p.type == 'Out';

    // Punch In/Out keep their canonical colors. Tracking pings use the fence
    // verdict: green when inside, red when outside, grey when unknown.
    final Color color;
    if (isIn) {
      color = _greenIn;
    } else if (isOut) {
      color = _redOut;
    } else {
      switch (p.isInside) {
        case true:
          color = _greenIn;
          break;
        case false:
          color = _redOut;
          break;
        default:
          color = _neutral;
      }
    }

    final label = isIn
        ? 'Punch In'
        : isOut
            ? 'Punch Out'
            : 'Tracking';

    // Punch In/Out always use the selfie slot. Tracking pings now carry a
    // selfie_url too (the backend stores a per-ping image when one was sent),
    // so show it when present; otherwise fall back to a map-pin tile.
    final hasSelfie = p.selfiePath != null && p.selfiePath!.isNotEmpty;
    final Widget photoWidget = (isIn || isOut || hasSelfie)
        ? _PhotoSlot.selfie(p.selfiePath, color)
        : _PhotoSlot.icon(Icons.location_pin, color);

    return TimingRowCard._(
      ribbonColor: color,
      photo: photoWidget,
      label: label,
      labelColor: color,
      dateText: _dateLabel(p.timestamp),
      address: p.address.isEmpty ? 'Address unavailable' : p.address,
      time: p.formattedTime,
      batteryText: p.batteryLabel,
      distanceText:
          p.distanceM == null ? null : '${p.distanceM!.toInt()} m',
      coordsText: p.coordinates,
      onTap: onTap,
    );
  }

  /// True for readings at or below 20%. Parsed from the display string so the
  /// widget keeps a single source of truth for the label.
  static bool _isLowBattery(String label) {
    final n = int.tryParse(label.replaceAll('%', '').trim());
    return n != null && n <= 20;
  }

  static const _greenIn = Color(0xFF4CAF50);
  static const _redOut = Color(0xFFE53935);
  static const _neutral = Color(0xFF9E9E9E);
  static const _muted = Color(0xFF666666);

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left ribbon — green/red/grey strip flush with the card edge.
            Container(width: 5, color: ribbonColor),

            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: photo,
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: labelColor,
                        ),
                      ),
                      if (dateText != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          dateText!,
                          style: GoogleFonts.poppins(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w500,
                            color: _muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),

            // Middle column — address (top) + time (bottom).
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF222222),
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.access_time, size: 11, color: _muted),
                        const SizedBox(width: 3),
                        Text(
                          time,
                          style: GoogleFonts.poppins(
                            fontSize: 10.5,
                            color: _muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        // Battery at capture time, beside the time it belongs
                        // to. Reads red below 20% — a flat phone is the usual
                        // explanation for a gap in the trail, so it should be
                        // obvious rather than something you go looking for.
                        if (batteryText != null) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.battery_std,
                            size: 11,
                            color: _isLowBattery(batteryText!)
                                ? const Color(0xFFE53935)
                                : _muted,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            batteryText!,
                            style: GoogleFonts.poppins(
                              fontSize: 10.5,
                              color: _isLowBattery(batteryText!)
                                  ? const Color(0xFFE53935)
                                  : _muted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Right column — distance (top) + coordinates (bottom). Hidden
            // when both are null (keeps the right edge tidy).
            if (distanceText != null || coordsText != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 8, 10, 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      distanceText ?? '—',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF222222),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      coordsText ?? '',
                      style: GoogleFonts.poppins(
                        fontSize: 9.5,
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
    );

    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, child: card);
  }
}

/// 42×42 photo slot — either a remote/local selfie or a centered icon
/// placeholder for tracking pings. Both variants degrade to the same grey
/// fallback if the image fails to load.
class _PhotoSlot {
  static const _size = 42.0;

  static Widget selfie(String? source, Color tint) {
    Widget fallback() => _iconBox(Icons.person, tint);
    if (source == null || source.isEmpty) return fallback();
    final isUrl =
        source.startsWith('http://') || source.startsWith('https://');
    if (isUrl) {
      return Image.network(
        source,
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback(),
      );
    }
    return Image.file(
      File(source),
      width: _size,
      height: _size,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback(),
    );
  }

  static Widget icon(IconData icon, Color tint) => _iconBox(icon, tint);

  static Widget _iconBox(IconData icon, Color tint) => Container(
        width: _size,
        height: _size,
        color: const Color(0xFFF1F1F1),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 22,
          color: tint.withValues(alpha: 0.55),
        ),
      );
}
