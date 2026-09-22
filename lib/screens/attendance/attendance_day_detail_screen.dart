// Per-day attendance detail screen — opens when the user taps a date on
// the calendar in AttendanceScreen.
//
// The calendar API (`/get_calendar_data`) only carries `{status, late, type}`
// per day — no punch times or hours. So when this screen opens it fires a
// second request to `/get_my_attendance` for the same date (single-day window
// via filter=custom + same from/to). That endpoint returns ALL daily records
// including plain Present days, with fields `first_in`, `last_out`,
// `work_hours`, `is_late`, etc. (the regularization endpoint was filtering
// out non-regularizable rows like ordinary Present days, which is why those
// were coming back empty.)
//
// Read-only display matching the screenshot the product owner shared.
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';

class AttendanceDayDetailScreen extends StatefulWidget {
  final DateTime date;

  /// Status/late/type entry from `AttendanceProvider.calendarData` for this
  /// date — pre-fetched on the calendar screen so we can colour the status
  /// card immediately without waiting for the per-day API call.
  final Map<String, dynamic>? data;

  const AttendanceDayDetailScreen({
    super.key,
    required this.date,
    required this.data,
  });

  @override
  State<AttendanceDayDetailScreen> createState() =>
      _AttendanceDayDetailScreenState();
}

class _AttendanceDayDetailScreenState extends State<AttendanceDayDetailScreen> {
  /// Full record from `/get_my_attendance` (single-day window via filter=custom).
  /// `null` until the fetch completes; remains null if the API returns no
  /// record for that date (weekly off, leave, future date, no row yet).
  Map<String, dynamic>? _fetched;
  bool _isLoading = false;
  bool get _isFutureDate {
    final today = DateTime.now();
    return widget.date.isAfter(DateTime(today.year, today.month, today.day));
  }

  @override
  void initState() {
    super.initState();
    if (!_isFutureDate) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchDetail());
    }
  }

  Future<void> _fetchDetail() async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null) return;

    setState(() => _isLoading = true);
    final apiDate = DateFormat('yyyy-MM-dd').format(widget.date);

    // Use /get_my_attendance with a single-day custom window — returns every
    // attendance row (Present, Half Day, Absent, etc.), not just the ones
    // needing regularization.
    final response = await ApiService.getMyAttendance(
      token: token,
      filter: 'custom',
      fromDate: apiDate,
      toDate: apiDate,
    );

    if (!mounted) return;

    Map<String, dynamic>? record;
    if (response.isSuccess && response.data is Map) {
      final body = response.data as Map;
      final list = body['data'];
      if (list is List && list.isNotEmpty && list.first is Map) {
        record = Map<String, dynamic>.from(list.first as Map);
      }
    }

    setState(() {
      _fetched = record;
      _isLoading = false;
    });
  }

  // ---- Status mapping (from calendar pre-fetched data) -------------------

  _StatusVisual _statusVisualFor() {
    final raw = widget.data?['status']?.toString().toLowerCase() ?? '';
    final isLate = (widget.data?['late'] ?? 0).toString() == '1';
    switch (raw) {
      case 'p':
        return _StatusVisual(
          label: isLate ? 'Present (Late)' : 'Present',
          icon: Iconsax.tick_circle,
          color: const Color(0xFF22A06B),
          bg: const Color(0xFFE6F6EE),
        );
      case 'a':
        return _StatusVisual(
          label: 'Absent',
          icon: Iconsax.close_circle,
          color: const Color(0xFFC62828),
          bg: const Color(0xFFFFEBEE),
        );
      case 'hd':
        return _StatusVisual(
          label: 'Half Day',
          icon: Iconsax.clock,
          color: const Color(0xFFE65100),
          bg: const Color(0xFFFFF3E0),
        );
      case 'wo':
        return _StatusVisual(
          label: 'Weekly Off',
          icon: Iconsax.calendar_remove,
          color: const Color(0xFF1565C0),
          bg: const Color(0xFFE3F2FD),
        );
      case 'l':
        return _StatusVisual(
          label: 'On Leave',
          icon: Iconsax.calendar_tick,
          color: const Color(0xFF6A1B9A),
          bg: const Color(0xFFF3E5F5),
        );
      case 'ph':
        return _StatusVisual(
          label: 'Paid Holiday',
          icon: Iconsax.gift,
          color: const Color(0xFFAD1457),
          bg: const Color(0xFFFCE4EC),
        );
      default:
        return _StatusVisual(
          label: 'No record',
          icon: Iconsax.minus_cirlce,
          color: const Color(0xFF6B7280),
          bg: const Color(0xFFF1F5F9),
        );
    }
  }

  // ---- Field lookup with fallbacks ---------------------------------------

  /// Looks up the first non-empty / non-'null' value across [keys] in the
  /// fetched record. Returns null if nothing usable is present.
  String? _lookupString(List<String> keys) {
    final rec = _fetched;
    if (rec == null) return null;
    for (final k in keys) {
      final v = rec[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isEmpty || s.toLowerCase() == 'null' || s == 'NA') continue;
      return s;
    }
    return null;
  }

  /// Tries to format a time-ish string as "hh:mm a". Accepts many shapes:
  /// "09:30:00", "09:30", "9:30 AM", "2026-05-13 09:30:00", ISO datetime.
  /// Returns "—" if input is null/empty/'NA'.
  String _formatTime(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    final lower = raw.toLowerCase();
    if (lower == 'null' || lower == 'na' || lower == 'n/a') return '—';

    final dt = DateTime.tryParse(raw);
    if (dt != null) return DateFormat('hh:mm a').format(dt);
    try {
      final t = DateFormat('HH:mm:ss').parseStrict(raw);
      return DateFormat('hh:mm a').format(t);
    } catch (_) {}
    try {
      final t = DateFormat('HH:mm').parseStrict(raw);
      return DateFormat('hh:mm a').format(t);
    } catch (_) {}
    return raw;
  }

  /// Hours worked — prefer an explicit hours field; if missing, compute
  /// from `first_in` and `last_out`.
  String _hoursWorked(String? firstInRaw, String? lastOutRaw) {
    // /get_my_attendance returns `work_hours` directly as "9.00" — checked
    // first for cheap rendering. Other names kept as fallbacks for safety.
    final explicit = _lookupString([
      'work_hours',
      'hours_worked',
      'total_hours',
      'worked_hours',
      'hours',
      'duration',
      'working_hours',
    ]);
    if (explicit != null && explicit != '0' && explicit != '0.00') {
      final asNum = double.tryParse(explicit);
      if (asNum != null) return '${asNum.toStringAsFixed(2)} hrs';
      return explicit;
    }

    // Compute from punch times if both available.
    final inT = _parseTimeForCalc(firstInRaw);
    final outT = _parseTimeForCalc(lastOutRaw);
    if (inT == null || outT == null) return '—';
    final diff = outT.difference(inT);
    if (diff.isNegative) return '—';
    final hours = diff.inMinutes / 60.0;
    return '${hours.toStringAsFixed(2)} hrs';
  }

  DateTime? _parseTimeForCalc(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty || s.toLowerCase() == 'null' || s == 'NA') {
      return null;
    }
    final dt = DateTime.tryParse(s);
    if (dt != null) return dt;
    try {
      return DateFormat('HH:mm:ss').parseStrict(s);
    } catch (_) {}
    try {
      return DateFormat('HH:mm').parseStrict(s);
    } catch (_) {}
    return null;
  }

  String? _notes() =>
      _lookupString(['notes', 'note', 'remarks', 'comment', 'comments']);

  // ---- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusVisual = _statusVisualFor();

    final firstInRaw = _lookupString([
      'first_in',
      'punch_in',
      'in_time',
      'first_punch_in',
      'firstPunchIn',
      'clock_in',
      'check_in',
    ]);
    final lastOutRaw = _lookupString([
      'last_out',
      'punch_out',
      'out_time',
      'last_punch_out',
      'lastPunchOut',
      'clock_out',
      'check_out',
    ]);
    final punchIn = _formatTime(firstInRaw);
    final punchOut = _formatTime(lastOutRaw);
    final hours = _hoursWorked(firstInRaw, lastOutRaw);
    final notes = _notes();

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Iconsax.arrow_left_2, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          DateFormat('MMMM dd, yyyy').format(widget.date),
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('EEEE').format(widget.date),
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ).animate().fadeIn(duration: 250.ms),
              const SizedBox(height: 1),
              Text(
                    DateFormat('MMMM dd, yyyy').format(widget.date),
                    style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                    ),
                  )
                  .animate(delay: 40.ms)
                  .fadeIn(duration: 280.ms)
                  .slideY(begin: 0.05, end: 0),

              const SizedBox(height: 10),

              _StatusCard(visual: statusVisual)
                  .animate(delay: 80.ms)
                  .fadeIn(duration: 280.ms)
                  .slideY(begin: 0.06, end: 0),

              const SizedBox(height: 10),

              // Punch In / Punch Out side-by-side.
              Row(
                    children: [
                      Expanded(
                        child: _PunchTile(
                          label: 'Punch In',
                          time: punchIn,
                          icon: Iconsax.login,
                          color: const Color(0xFF22A06B),
                          bg: const Color(0xFFE6F6EE),
                          isDark: isDark,
                          isLoading: _isLoading,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _PunchTile(
                          label: 'Punch Out',
                          time: punchOut,
                          icon: Iconsax.logout,
                          color: const Color(0xFFC62828),
                          bg: const Color(0xFFFFEBEE),
                          isDark: isDark,
                          isLoading: _isLoading,
                        ),
                      ),
                    ],
                  )
                  .animate(delay: 140.ms)
                  .fadeIn(duration: 280.ms)
                  .slideY(begin: 0.06, end: 0),

              const SizedBox(height: 10),

              _HoursTile(value: hours, isDark: isDark, isLoading: _isLoading)
                  .animate(delay: 200.ms)
                  .fadeIn(duration: 280.ms)
                  .slideY(begin: 0.06, end: 0),

              const SizedBox(height: 10),

              _NotesCard(notes: notes, isDark: isDark)
                  .animate(delay: 260.ms)
                  .fadeIn(duration: 280.ms)
                  .slideY(begin: 0.06, end: 0),

              if (_isFutureDate) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      Iconsax.info_circle,
                      size: 14,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Future date — no attendance yet.',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Sub-widgets ----------------------------------------------------------

class _StatusVisual {
  final String label;
  final IconData icon;
  final Color color;
  final Color bg;

  _StatusVisual({
    required this.label,
    required this.icon,
    required this.color,
    required this.bg,
  });
}

class _StatusCard extends StatelessWidget {
  final _StatusVisual visual;
  const _StatusCard({required this.visual});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: visual.bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: visual.color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(visual.icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Status',
                  style: GoogleFonts.poppins(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  visual.label,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: visual.color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PunchTile extends StatelessWidget {
  final String label;
  final String time;
  final IconData icon;
  final Color color;
  final Color bg;
  final bool isDark;
  final bool isLoading;

  const _PunchTile({
    required this.label,
    required this.time,
    required this.icon,
    required this.color,
    required this.bg,
    required this.isDark,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.white12 : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, color: color, size: 14),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          isLoading
              ? _SkeletonBar(width: 60, height: 15, isDark: isDark)
              : Text(
                  time,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
        ],
      ),
    );
  }
}

class _HoursTile extends StatelessWidget {
  final String value;
  final bool isDark;
  final bool isLoading;

  const _HoursTile({
    required this.value,
    required this.isDark,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.white12 : AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1E0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Iconsax.timer_1,
              color: Color(0xFFE69500),
              size: 15,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Hours Worked',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          isLoading
              ? _SkeletonBar(width: 60, height: 13, isDark: isDark)
              : Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
        ],
      ),
    );
  }
}

class _NotesCard extends StatelessWidget {
  final String? notes;
  final bool isDark;

  const _NotesCard({required this.notes, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final hasNotes = notes != null && notes!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.white12 : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Iconsax.note_text,
                size: 13,
                color: hasNotes ? AppColors.primary : AppColors.textTertiary,
              ),
              const SizedBox(width: 6),
              Text(
                'Notes',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hasNotes ? notes! : 'No notes for this day.',
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              fontStyle: hasNotes ? FontStyle.normal : FontStyle.italic,
              color: hasNotes
                  ? (isDark ? Colors.white70 : AppColors.textPrimary)
                  : AppColors.textTertiary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Simple placeholder bar for fields that are still fetching. Plain coloured
/// rectangle — keeps the build cheap (no shimmer animation).
class _SkeletonBar extends StatelessWidget {
  final double width;
  final double height;
  final bool isDark;
  const _SkeletonBar({
    required this.width,
    required this.height,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.08)
            : AppColors.border.withOpacity(0.6),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
