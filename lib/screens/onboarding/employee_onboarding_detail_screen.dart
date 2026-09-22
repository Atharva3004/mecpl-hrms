import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import 'employee_onboarding_approval_screen.dart' show OnboardingRequest;

/// Full-screen "Employee Summary" shown when an onboarding card is tapped.
///
/// Renders an ID-card style header, then sectioned details (Personal,
/// Employment, Education, Bank, Emergency), the approval levels, and the
/// Approve / Reject actions. All extra fields are read DEFENSIVELY from
/// [OnboardingRequest.raw] — the exact backend field names aren't fully known,
/// so each logical field probes several likely keys and only sections that
/// actually have data are shown.
class EmployeeOnboardingDetailScreen extends StatelessWidget {
  const EmployeeOnboardingDetailScreen({
    super.key,
    required this.request,
    required this.onAction,
  });

  final OnboardingRequest request;

  /// Called with `true` for Approve, `false` for Reject. The caller is
  /// responsible for the confirmation popup + API submission (we just pop
  /// this screen first so the popup appears over the list).
  final void Function(bool approved) onAction;

  // ─────────────────────────── defensive readers ───────────────────────────

  Map<String, dynamic> _map(dynamic v) =>
      v is Map<String, dynamic> ? v : const <String, dynamic>{};

  /// Coerce a value to a clean display string, or null if it's empty/blank.
  /// Unwraps single-value maps like `{department_name: "..."}`.
  String? _str(dynamic v) {
    if (v == null) return null;
    if (v is Map) {
      for (final k in const [
        'name',
        'department_name',
        'designation_name',
        'branch_name',
        'company_name',
        'value',
      ]) {
        final s = _str(v[k]);
        if (s != null) return s;
      }
      return null;
    }
    final s = v.toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null' || s == 'N/A') return null;
    return s;
  }

  /// Return the first non-empty value found by probing [keys] across [sources].
  String? _pick(List<Map<String, dynamic>> sources, List<String> keys) {
    for (final src in sources) {
      for (final k in keys) {
        if (src.containsKey(k)) {
          final s = _str(src[k]);
          if (s != null) return s;
        }
      }
    }
    return null;
  }

  /// Recursively walk the whole JSON tree and return the first non-empty value
  /// whose key contains any of [keyContains]. Used when the exact nesting of a
  /// field (e.g. UAN/ESIC) isn't known.
  String? _deepPick(dynamic node, List<String> keyContains) {
    if (node is Map) {
      for (final entry in node.entries) {
        final key = entry.key.toString().toLowerCase();
        if (keyContains.any(key.contains)) {
          final s = _str(entry.value);
          if (s != null) return s;
        }
      }
      for (final v in node.values) {
        final s = _deepPick(v, keyContains);
        if (s != null) return s;
      }
    } else if (node is List) {
      for (final v in node) {
        final s = _deepPick(v, keyContains);
        if (s != null) return s;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final raw = request.raw;
    final personal = _map(raw['personal_details']);
    final company = _map(raw['company_details']);
    final statutory = _map(raw['statutory_details']);

    // Sources to probe, most-specific first.
    final personalSrc = [personal, raw];
    final companySrc = [company, raw];

    final companyName =
        _pick(companySrc, ['company_name', 'company']) ?? '';

    final personalRows = <MapEntry<String, String>?>[
      _kv('Date of Birth', request.formattedDob),
      _kv('Age', request.formattedAge),
      _kv(
        'Contact No.',
        _pick(personalSrc, [
          'mobile',
          'mobile_no',
          'phone',
          'phone_no',
          'contact',
          'contact_no',
          'emp_mobile',
        ]),
      ),
    ];

    final employmentRows = <MapEntry<String, String>?>[
      _kv('Gross Salary', request.formattedSalary),
      // UAN / ESI live under `statutory_details`; always shown (N/A fallback).
      MapEntry(
        'UAN No.',
        _pick(
              [statutory, company, raw],
              ['uan_no', 'uan', 'uan_number'],
            ) ??
            _deepPick(raw, ['uan']) ??
            'N/A',
      ),
      MapEntry(
        'ESI No.',
        _pick(
              [statutory, company, raw],
              ['esi_no', 'esic_no', 'esi_number', 'esic'],
            ) ??
            _deepPick(raw, ['esi_no', 'esic']) ??
            'N/A',
      ),
    ];

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        title: Text(
          'Employee Summary',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.chevron_left,
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _buildIdCard(companyName)
              .animate()
              .fadeIn(duration: 400.ms, curve: Curves.easeOut)
              .slideY(
                begin: 0.18,
                end: 0,
                duration: 500.ms,
                curve: Curves.easeOutCubic,
              )
              .scale(
                begin: const Offset(0.96, 0.96),
                end: const Offset(1, 1),
                duration: 500.ms,
                curve: Curves.easeOutCubic,
              ),
          const SizedBox(height: 8),

          // Single merged card: Personal + Employment + Approval Levels
          _buildSummaryCard(context, isDark, personalRows, employmentRows)
              .animate()
              .fadeIn(delay: 160.ms, duration: 400.ms, curve: Curves.easeOut)
              .slideY(
                begin: 0.18,
                end: 0,
                delay: 160.ms,
                duration: 500.ms,
                curve: Curves.easeOutCubic,
              ),
        ],
      ),
      bottomNavigationBar: _buildActionBar(context),
    );
  }

  // ─────────────────────────── ID card header ───────────────────────────

  Widget _buildIdCard(String companyName) {
    const darkBlue = Color(0xFF1E3A8A);
    const blue = Color(0xFF2563EB);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Top blue banner with company name + logo ──
          ClipPath(
            clipper: _BannerClipper(),
            child: Container(
              height: 62,
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [darkBlue, blue],
                ),
              ),
              child: Stack(
                children: [
                  // lighter diagonal accent stripe on the right
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    child: ClipPath(
                      clipper: _AccentClipper(),
                      child: Container(
                        width: 130,
                        color: Colors.white.withOpacity(0.12),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Image.asset(
                            'assets/spinner/spinner_logo.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Onboarding Form',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Body: photo + name/joined/exp/code, then desig/dept/branch ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Photo with blue frame
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: blue,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: _photo(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _cardRow(
                            'Name',
                            request.name,
                            emphasize: true,
                            oneLine: true,
                          ),
                          _cardRow('Joined', request.formattedJoinDate),
                          _cardRow(
                            'Experience',
                            request.formattedExperience == '—'
                                ? ''
                                : request.formattedExperience,
                          ),
                          _cardRow('Emp Code', request.empId),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _cardRow('Designation', request.designation),
                _cardRow('Department', request.department),
                _cardRow('Branch', request.branch),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _photo() {
    final url = request.empImageUrl;
    final initial =
        request.name.isNotEmpty ? request.name[0].toUpperCase() : '?';
    final fallback = Container(
      width: 72,
      height: 84,
      color: AppColors.primary.withOpacity(0.15),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: GoogleFonts.poppins(
          fontSize: 36,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
        ),
      ),
    );
    if (url == null || url.isEmpty) return fallback;
    return Image.network(
      url,
      width: 72,
      height: 84,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : fallback,
    );
  }

  /// One "Label : Value" row inside the ID card. Hidden when [value] is blank.
  Widget _cardRow(
    String label,
    String value, {
    bool emphasize = false,
    bool oneLine = false,
  }) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF6B7280),
              ),
            ),
          ),
          Text(
            ':  ',
            style: GoogleFonts.poppins(
              fontSize: 10.5,
              color: const Color(0xFF6B7280),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: oneLine ? 1 : null,
              overflow: oneLine ? TextOverflow.ellipsis : TextOverflow.clip,
              style: GoogleFonts.poppins(
                fontSize: emphasize ? 12.5 : 11,
                fontWeight: emphasize ? FontWeight.bold : FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── sections ───────────────────────────

  /// A key/value pair; null/blank values are dropped by [_section].
  MapEntry<String, String>? _kv(String label, String? value) {
    final v = value?.trim();
    if (v == null || v.isEmpty) return null;
    return MapEntry(label, v);
  }

  /// The single merged details card: Personal + Employment + Approval Levels,
  /// each a compact sub-section, tightly packed (no per-card gaps).
  Widget _buildSummaryCard(
    BuildContext context,
    bool isDark,
    List<MapEntry<String, String>?> personalRows,
    List<MapEntry<String, String>?> employmentRows,
  ) {
    final children = <Widget>[];

    void addRows(
      String title,
      IconData icon,
      List<MapEntry<String, String>?> rows,
    ) {
      final visible = rows.whereType<MapEntry<String, String>>().toList();
      if (visible.isEmpty) return;
      if (children.isNotEmpty) children.add(_sectionDivider(isDark));
      children.add(_subHeader(title, icon));
      for (var i = 0; i < visible.length; i++) {
        if (i > 0) children.add(_divider(isDark));
        final row = visible[i];
        children.add(_infoRow(isDark, row.key, row.value));
      }
    }

    addRows('Personal Details', Iconsax.user, personalRows);
    addRows('Employment Details', Iconsax.briefcase, employmentRows);

    // Approval Levels sub-section — built from the real `approval_details`.
    // Each level n has an approver id `ecl{n}` (null ⇒ not in this chain) and a
    // `status_ecl{n}` ("Approved" / "Not Initiated" / ...). The level→role map
    // matches the company's onboarding flow.
    final levels = _approvalLevels();
    if (children.isNotEmpty) children.add(_sectionDivider(isDark));
    children.add(
      _subHeader(
        'Approval Levels',
        Iconsax.task_square,
        trailing: levels.isEmpty ? null : 'Tap for details',
      ),
    );
    children.add(
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (levels.isEmpty)
              Text(
                'No approval history available.',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
            for (var i = 0; i < levels.length; i++)
              _animatedApprovalChip(
                levels[i],
                i,
                onTap: () => _showApprovalDetails(context, levels, i),
              ),
          ],
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF3C3C3E) : const Color(0xFFE5E7EB),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  /// Compact sub-section header inside the merged card. [trailing] renders a
  /// muted hint on the right (used by Approval Levels to advertise the tap).
  Widget _subHeader(String title, IconData icon, {String? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(
          children: [
            Icon(icon, size: 14, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            if (trailing != null) ...[
              const Spacer(),
              Text(
                trailing,
                style: GoogleFonts.poppins(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.touch_app_rounded,
                size: 11,
                color: AppColors.textTertiary,
              ),
            ],
          ],
        ),
      );

  /// Full-width divider separating sub-sections in the merged card.
  Widget _sectionDivider(bool isDark) => Divider(
        height: 1,
        thickness: 1,
        color: isDark ? const Color(0xFF3C3C3E) : const Color(0xFFE5E7EB),
      );

  Widget _divider(bool isDark) => Divider(
        height: 1,
        indent: 12,
        endIndent: 12,
        color: isDark ? const Color(0xFF3C3C3E) : const Color(0xFFF1F2F3),
      );

  Widget _infoRow(bool isDark, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Role label shown for each approval level (matches the company flow).
  /// ecl1=PM, ecl2=DH (Dept Head), ecl3=PH, ecl5=HR, ecl6=Director.
  static const Map<int, String> _levelRoles = {
    1: 'PM',
    2: 'DH',
    3: 'PH',
    4: 'L4',
    5: 'HR',
    6: 'Director',
  };

  /// Long-form role names, shown in the approval-details sheet.
  static const Map<int, String> _levelRoleNames = {
    1: 'Project Manager',
    2: 'Department Head',
    3: 'Project Head',
    4: 'Level 4 Approver',
    5: 'HR',
    6: 'Director',
  };

  /// Reads `approval_details` and returns the active levels in level order.
  ///
  /// The row looks like this (verified against a live record):
  /// ```
  /// {id, emp_id, br_id, ecl1..ecl6, status_ecl1..6, remarks_ecl1..4,
  ///  hr_remarks, director_remarks, a_id, created_at, updated_at}
  /// ```
  /// `ecl{n}` is the approver's employee id — null means that level isn't part
  /// of this employee's chain, so it's skipped. Note there is NO per-level
  /// timestamp: only the row's own `created_at` / `updated_at`, which the
  /// details sheet shows as a footer. Approver NAMES aren't in the payload
  /// either; [_ApprovalDetailsSheet] resolves them from the employee directory.
  List<_ApprovalLevel> _approvalLevels() {
    final ad = _map(request.raw['approval_details']);
    final out = <_ApprovalLevel>[];

    for (var n = 1; n <= 6; n++) {
      final approverId = ad['ecl$n'];
      if (approverId == null) continue;

      final status = (ad['status_ecl$n'] ?? '').toString();
      String? name;
      String? remark;
      DateTime? actedAt;

      // Remarks are named per level: remarks_ecl1..4, then hr_remarks and
      // director_remarks for levels 5 and 6.
      remark = _str(ad['remarks_ecl$n']) ??
          _str(n == 5 ? ad['hr_remarks'] : null) ??
          _str(n == 6 ? ad['director_remarks'] : null);

      // The approver id may itself be an object carrying the name.
      name = _pick([
        _map(approverId),
        _map(ad['ecl${n}_details']),
        _map(ad['approver$n']),
      ], const [
        'emp_name',
        'name',
        'employee_name',
        'full_name',
      ]);

      // Today the backend sends neither a name nor a timestamp per level, but
      // it may later. Pick them up if they appear, matching only keys that
      // clearly say what they hold — a loose match would read `remarks_ecl{n}`
      // as the approver's name.
      for (final entry in ad.entries) {
        final key = entry.key.toLowerCase();
        if (!key.contains('ecl$n')) continue;

        final value = _str(entry.value);
        if (value == null) continue;

        if (key.contains('name')) {
          name ??= value;
        } else if (key.contains('date') ||
            key.contains('time') ||
            key.endsWith('_at') ||
            key.endsWith('_on')) {
          actedAt ??= _parseDateTime(value);
        }
      }

      // A remark that just echoes the status adds nothing — drop it.
      if (remark != null &&
          remark.trim().toLowerCase() == status.trim().toLowerCase()) {
        remark = null;
      }

      out.add(
        _ApprovalLevel(
          level: n,
          role: _levelRoles[n] ?? 'L$n',
          roleName: _levelRoleNames[n] ?? 'Level $n Approver',
          status: status,
          approverName: name,
          approverId: approverId is Map ? null : _str(approverId),
          actedAt: actedAt,
          remark: remark,
        ),
      );
    }
    return out;
  }

  /// Parse the assorted timestamp formats the HRMS backend emits.
  DateTime? _parseDateTime(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;

    // Unix timestamps — seconds (10 digits) or milliseconds (13 digits).
    // Shorter all-digit values are row ids, not dates.
    if (RegExp(r'^\d+$').hasMatch(v)) {
      if (v.length == 10) {
        return DateTime.fromMillisecondsSinceEpoch(int.parse(v) * 1000);
      }
      if (v.length == 13) {
        return DateTime.fromMillisecondsSinceEpoch(int.parse(v));
      }
      return null;
    }

    final iso = DateTime.tryParse(v);
    if (iso != null) return iso.isUtc ? iso.toLocal() : iso;
    for (final f in const [
      'dd-MM-yyyy HH:mm:ss',
      'dd/MM/yyyy HH:mm:ss',
      'dd-MM-yyyy hh:mm:ss a',
      'dd/MM/yyyy hh:mm:ss a',
      'dd-MM-yyyy HH:mm',
      'dd/MM/yyyy HH:mm',
      'dd-MM-yyyy hh:mm a',
      'dd/MM/yyyy hh:mm a',
      'dd-MM-yyyy',
      'dd/MM/yyyy',
      'yyyy-MM-dd hh:mm a',
      'yyyy/MM/dd HH:mm:ss',
      'MM/dd/yyyy HH:mm:ss',
      'dd MMM yyyy HH:mm',
      'dd MMM yyyy hh:mm a',
      'dd MMM yyyy',
    ]) {
      try {
        return DateFormat(f).parseStrict(v);
      } catch (_) {
        // try the next pattern
      }
    }
    return null;
  }

  /// Opens the approval-details sheet, highlighting the tapped level.
  void _showApprovalDetails(
    BuildContext context,
    List<_ApprovalLevel> levels,
    int initialIndex,
  ) {
    // The row carries no per-level timestamps, but it does record when the
    // request was raised and when it was last acted on — show both.
    final ad = _map(request.raw['approval_details']);
    final submittedAt = _parseDateTime(_str(ad['created_at']) ?? '');
    final lastActionAt = _parseDateTime(_str(ad['updated_at']) ?? '');

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ApprovalDetailsSheet(
        levels: levels,
        initialIndex: initialIndex,
        submittedAt: submittedAt,
        lastActionAt: lastActionAt,
      ),
    );
  }

  /// One approval chip, coloured by status, animated on entry and tappable to
  /// reveal who approved it and when.
  Widget _animatedApprovalChip(
    _ApprovalLevel level,
    int index, {
    required VoidCallback onTap,
  }) {
    final color = _statusColorOf(level);

    final Widget chip = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: _approvalChipPill(level.role, color, _statusIconOf(level)),
    );

    var anim = chip
        .animate()
        .fadeIn(delay: (350 + 90 * index).ms, duration: 250.ms)
        .scale(
          begin: const Offset(0.4, 0.4),
          end: const Offset(1, 1),
          duration: 600.ms,
          curve: Curves.elasticOut,
        );
    // Draw the eye to the level still awaiting action.
    if (!level.isApproved && !level.isRejected) {
      anim = anim.then().shimmer(
            duration: 1200.ms,
            color: Colors.white.withValues(alpha: 0.6),
          );
    }
    return anim;
  }

  // ─────────────────────────── action bar ───────────────────────────

  Widget _buildActionBar(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  onAction(true);
                },
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('Approve'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  textStyle: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  onAction(false);
                },
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('Reject'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  textStyle: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 300.ms, duration: 350.ms).slideY(
          begin: 1,
          end: 0,
          delay: 300.ms,
          duration: 400.ms,
          curve: Curves.easeOutCubic,
        );
  }
}

/// Slants the bottom edge of the ID-card banner for a dynamic look.
class _BannerClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height - 16)
      ..lineTo(size.width, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// A slanted parallelogram used as a lighter accent stripe on the banner.
class _AccentClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(size.width * 0.45, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width * 0.1, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}


/// Bottom sheet listing who approved each level and when. Opened by tapping
/// any approval chip; the tapped level is highlighted.
///
/// `approval_details` only carries the approver's employee id (`ecl{n}`), so
/// the names are resolved against the employee directory (`GET /employee`)
/// the first time a sheet is opened, then cached for the session.
class _ApprovalDetailsSheet extends StatefulWidget {
  const _ApprovalDetailsSheet({
    required this.levels,
    required this.initialIndex,
    this.submittedAt,
    this.lastActionAt,
  });

  final List<_ApprovalLevel> levels;
  final int initialIndex;

  /// When the onboarding request was raised (`approval_details.created_at`).
  final DateTime? submittedAt;

  /// When the chain was last acted on (`approval_details.updated_at`).
  final DateTime? lastActionAt;

  @override
  State<_ApprovalDetailsSheet> createState() => _ApprovalDetailsSheetState();
}

class _ApprovalDetailsSheetState extends State<_ApprovalDetailsSheet> {
  /// The employee directory, fetched once per app session and shared by every
  /// sheet. Null until the first successful fetch.
  static _EmployeeDirectory? _directory;

  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    // Only hit the network when a level is actually missing its name.
    final needsNames = widget.levels.any(
      (l) => l.approverName == null && l.approverId != null,
    );
    if (needsNames && _directory == null) {
      _resolving = true;
      _resolveNames();
    }
  }

  Future<void> _resolveNames() async {
    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token;
      if (token == null) return;

      final response = await ApiService.getEmployees(token);
      if (!response.isSuccess || response.data == null) return;

      final data = response.data!;
      final list = (data['data'] ?? data['employees'] ?? const []) as List;
      _directory = _EmployeeDirectory.fromRows(list);
    } catch (e) {
      debugPrint('⚠️ [Onboarding] Could not resolve approver names: $e');
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  /// The approver's name: the one the API sent, else the directory, else the
  /// signed-in user (an approver is often looking at their own pending level).
  /// Never guesses — an unmatched id keeps showing as an id.
  String? _nameFor(_ApprovalLevel level) {
    if (level.approverName != null) return level.approverName;
    final id = level.approverId;
    if (id == null) return null;

    final fromDirectory = _directory?.lookup(id);
    if (fromDirectory != null) return fromDirectory;

    final me = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (me != null && me.id == id) {
      final name = me.fullName.trim();
      if (name.isNotEmpty) return name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final levels = widget.levels;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF3C3C3E)
                      : const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                const Icon(
                  Iconsax.task_square,
                  size: 15,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Approval Levels',
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const Spacer(),
                if (_resolving)
                  const SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: AppColors.primary,
                    ),
                  )
                else
                  Text(
                    '${levels.where((l) => l.isApproved).length}/${levels.length} approved',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textTertiary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: levels.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (_, i) => _approvalDetailTile(
                  isDark,
                  levels[i],
                  name: _nameFor(levels[i]),
                  resolving: _resolving,
                  highlighted: i == widget.initialIndex,
                ).animate().fadeIn(delay: (40 * i).ms, duration: 200.ms),
              ),
            ),
            if (widget.submittedAt != null || widget.lastActionAt != null) ...[
              const SizedBox(height: 8),
              _timestampFooter(isDark),
            ],
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  /// The only real timestamps the backend records for the chain. Per-level
  /// date/time isn't stored, so these sit under the list rather than inside it.
  Widget _timestampFooter(bool isDark) {
    String fmt(DateTime d) =>
        '${DateFormat('dd MMM yyyy').format(d)}, ${DateFormat('hh:mm a').format(d)}';

    final parts = <String>[
      if (widget.submittedAt != null) 'Raised ${fmt(widget.submittedAt!)}',
      if (widget.lastActionAt != null)
        'Last action ${fmt(widget.lastActionAt!)}',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Iconsax.clock,
            size: 12,
            color: AppColors.textTertiary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              parts.join('   ·   '),
              style: GoogleFonts.poppins(
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of the approval-details sheet: role chip, approver name, status
/// and the date/time the action was taken.
Widget _approvalDetailTile(
  bool isDark,
  _ApprovalLevel level, {
  required String? name,
  required bool resolving,
  required bool highlighted,
}) {
  final color = _statusColorOf(level);
  final when = level.actedAt;
  final subtitle = when != null
      ? '${DateFormat('dd MMM yyyy').format(when)} · '
          '${DateFormat('hh:mm a').format(when)}'
      : (level.isApproved ? '' : 'Awaiting approval');

  final displayName = name ??
      (resolving
          ? 'Loading name…'
          : (level.approverId != null
              ? 'Approver #${level.approverId}'
              : 'Name not available'));

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: highlighted
          ? color.withValues(alpha: isDark ? 0.16 : 0.08)
          : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF8F9FA)),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: highlighted
            ? color.withValues(alpha: 0.5)
            : (isDark ? const Color(0xFF3C3C3E) : const Color(0xFFE5E7EB)),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _approvalChipPill(level.role, color, _statusIconOf(level)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: name == null
                      ? AppColors.textTertiary
                      : (isDark ? Colors.white : AppColors.textPrimary),
                ),
              ),
              Text(
                // On a level nobody has acted on yet, the name is the ASSIGNED
                // approver — say so, or it reads as though they approved.
                level.isApproved || level.isRejected
                    ? level.roleName
                    : '${level.roleName} · yet to act',
                style: GoogleFonts.poppins(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(_statusIconOf(level), size: 11, color: color),
                  const SizedBox(width: 3),
                  Text(
                    level.statusLabel,
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  if (subtitle.isNotEmpty) const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      subtitle,
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textTertiary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (level.remark != null) ...[
                const SizedBox(height: 3),
                Text(
                  level.remark!,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

Color _statusColorOf(_ApprovalLevel level) => level.isApproved
    ? AppColors.success
    : level.isRejected
        ? AppColors.error
        : AppColors.warning;

IconData _statusIconOf(_ApprovalLevel level) => level.isApproved
    ? Icons.check_rounded
    : level.isRejected
        ? Icons.close_rounded
        : Icons.hourglass_bottom_rounded;

/// Small filled pill: role label + status icon (e.g. green "PM ✓").
Widget _approvalChipPill(String label, Color color, IconData icon) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(6),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: 0.3),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 3),
        Icon(icon, size: 12, color: Colors.white),
      ],
    ),
  );
}


/// Employee-id → name lookup used to put a name on each approval level.
///
/// `approval_details.ecl{n}` holds an EMPLOYEE id (the signed-in HR user is
/// id 77 and appears as `ecl5: 77` on records awaiting HR), so `emp_id` is
/// authoritative and is tried first; `id` and `user_id` are fallbacks for
/// records shaped differently.
///
/// Each field gets its OWN index on purpose. Folding them into one map lets
/// an id from one space collide with an id from another — employee A's
/// `emp_id` 77 against employee B's `user_id` 77 — and silently show the
/// wrong person's name. `emp_code` is deliberately NOT indexed: codes like
/// 30639 are a different space again, and matching one numerically would
/// name the wrong employee.
class _EmployeeDirectory {
  const _EmployeeDirectory({
    required this.byEmpId,
    required this.byId,
    required this.byUserId,
  });

  final Map<String, String> byEmpId;
  final Map<String, String> byId;
  final Map<String, String> byUserId;

  factory _EmployeeDirectory.fromRows(List<dynamic> rows) {
    final byEmpId = <String, String>{};
    final byId = <String, String>{};
    final byUserId = <String, String>{};

    void put(Map<String, String> index, dynamic key, String name) {
      final id = key?.toString().trim();
      if (id == null || id.isEmpty || id == 'null') return;
      index.putIfAbsent(id, () => name);
    }

    for (final row in rows) {
      if (row is! Map) continue;
      final name = (row['emp_name'] ?? row['name'])?.toString().trim();
      if (name == null || name.isEmpty) continue;

      final company = row['company_details'];
      put(byEmpId, row['emp_id'], name);
      if (company is Map) put(byEmpId, company['emp_id'], name);
      put(byId, row['id'], name);
      put(byUserId, row['user_id'], name);
    }

    return _EmployeeDirectory(
      byEmpId: byEmpId,
      byId: byId,
      byUserId: byUserId,
    );
  }

  /// Most-authoritative index first. Returns null rather than a doubtful name.
  String? lookup(String id) => byEmpId[id] ?? byId[id] ?? byUserId[id];
}

/// One entry of the onboarding approval chain, parsed from `approval_details`.
class _ApprovalLevel {
  const _ApprovalLevel({
    required this.level,
    required this.role,
    required this.roleName,
    required this.status,
    this.approverName,
    this.approverId,
    this.actedAt,
    this.remark,
  });

  /// Chain position (1..6) — matches the backend `ecl{n}` keys.
  final int level;

  /// Short badge label, e.g. "PM".
  final String role;

  /// Long-form role name, e.g. "Project Manager".
  final String roleName;

  /// Raw backend status string, e.g. "Approved" / "Not Initiated".
  final String status;

  final String? approverName;
  final String? approverId;

  /// When the approver acted, if the backend sent a timestamp.
  final DateTime? actedAt;

  final String? remark;

  bool get isApproved => status.trim().toLowerCase() == 'approved';

  bool get isRejected => status.toLowerCase().contains('reject');

  /// Status text for display — falls back to "Pending" when the backend sends
  /// a blank or machine-ish value.
  String get statusLabel {
    final s = status.trim();
    if (s.isEmpty) return 'Pending';
    if (isApproved) return 'Approved';
    if (isRejected) return 'Rejected';
    if (s.toLowerCase() == 'not initiated') return 'Pending';
    return s;
  }
}
