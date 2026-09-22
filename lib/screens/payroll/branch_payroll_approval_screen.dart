import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../models/payroll_request_model.dart';
import '../../widgets/common/custom_loader.dart';
import '../common/document_viewer_screen.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// Branch Payroll Approval
///
/// Mobile card-list view of branch payroll activity requests pending the
/// logged-in approver's action. Supported activity types mirror the web
/// submission form: Resignation, Bank Account Update, Advance, Recovery,
/// Arrears, Hold and Release.
///
/// Data is loaded from the `/branch-payroll-approvals` API. Tapping "View"
/// opens a full-screen [BranchPayrollDetailScreen] that mirrors the web
/// "Request Details" modal (employee info, request details, activity data and
/// the approval timeline) with Approve / Reject actions.
/// ─────────────────────────────────────────────────────────────────────────

/// Activity types available on the Branch Payroll Request form, in display
/// order. Used to build the filter chips.
const List<String> kPayrollActivityTypes = [
  'Resignation',
  'Bank Account Update',
  'Advance',
  'Recovery',
  'Arrears',
  'Hold',
  'Release',
];

class BranchPayrollApprovalScreen extends StatefulWidget {
  const BranchPayrollApprovalScreen({super.key});

  @override
  State<BranchPayrollApprovalScreen> createState() =>
      _BranchPayrollApprovalScreenState();
}

class _BranchPayrollApprovalScreenState
    extends State<BranchPayrollApprovalScreen> {
  List<PayrollRequest> _requests = [];
  bool _isLoading = true;

  /// Activity-type filter chip currently selected ('All' shows everything).
  String _activeFilter = 'All';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final token = context.read<AuthProvider>().token;
      if (token != null) {
        final requests = await ApiService.getBranchPayrollApprovals(token);
        _requests = requests;
      }
    } catch (e) {
      debugPrint('Error loading branch payroll approvals: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Case-insensitive activity-type match (API sends e.g. "RELEASE" while the
  /// filter chips use the canonical display labels in [kPayrollActivityTypes]).
  bool _matchesType(PayrollRequest r, String type) =>
      r.activityType.trim().toLowerCase() == type.trim().toLowerCase();

  int _countFor(String type) => type == 'All'
      ? _requests.length
      : _requests.where((r) => _matchesType(r, type)).length;

  /// Filter chips are driven by the activity types actually present in the
  /// data. Known types use their canonical label (from [kPayrollActivityTypes]);
  /// any unexpected type from the API still gets a chip (title-cased).
  List<String> get _filterTypes {
    final seen = <String, String>{}; // lowercase key -> display label
    for (final r in _requests) {
      final raw = r.activityType.trim();
      if (raw.isEmpty) continue;
      final key = raw.toLowerCase();
      seen.putIfAbsent(
        key,
        () => kPayrollActivityTypes.firstWhere(
          (t) => t.toLowerCase() == key,
          orElse: () => _titleCase(raw),
        ),
      );
    }
    final present = seen.values.toList()
      ..sort((a, b) {
        int rank(String s) {
          final i = kPayrollActivityTypes.indexWhere(
            (t) => t.toLowerCase() == s.toLowerCase(),
          );
          return i == -1 ? 999 : i;
        }

        return rank(a).compareTo(rank(b));
      });
    return ['All', ...present];
  }

  String _titleCase(String s) => s
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');

  List<PayrollRequest> get _visibleRequests {
    if (_activeFilter == 'All') return _requests;
    return _requests.where((r) => _matchesType(r, _activeFilter)).toList();
  }

  // ── Approve / Reject ────────────────────────────────────────────────────

  /// Removes a request from the list locally (after a successful API call,
  /// either from the tick/cross here or returned from the detail screen).
  void _removeLocally(PayrollRequest request, String decision) {
    setState(() {
      _requests.removeWhere((r) => r.id == request.id);
      if (!_filterTypes.contains(_activeFilter)) _activeFilter = 'All';
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${request.activityType} request for ${request.empName} '
          '$decision successfully',
        ),
        backgroundColor: decision == 'Approved'
            ? AppColors.success
            : AppColors.error,
      ),
    );
  }

  /// Calls the approve/reject API, then removes the row on success.
  Future<void> _submitDecision(
    PayrollRequest request,
    String decision,
    String remarks,
  ) async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CustomLoader(size: 50)),
    );

    final res = await ApiService.postBranchPayrollApproval(
      token: token,
      requestId: request.id,
      action: payrollActionToken(decision),
      remarks: remarks,
      level: payrollLevelOf(request),
    );

    if (!mounted) return;
    Navigator.pop(context); // dismiss loader

    if (res.success) {
      _removeLocally(request, decision);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res.message.isNotEmpty
                ? res.message
                : 'Failed to ${decision.toLowerCase()} request',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _openDetails(PayrollRequest request) async {
    final result = await Navigator.push<Map<String, String>>(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) =>
            BranchPayrollDetailScreen(request: request),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
    if (result != null) {
      // The detail screen already called the API; just sync the list.
      _removeLocally(request, result['decision'] ?? 'Approved');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        title: Text(
          'Branch Payroll Approval',
          style: AppTextStyles.headlineMedium.copyWith(
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
      body: _isLoading
          ? const Center(child: CustomLoader(size: 60))
          : Column(
              children: [
                _buildSummaryCard(isDark),
                _buildFilterChips(isDark),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadData,
                    child: _buildList(isDark),
                  ),
                ),
              ],
            ),
    );
  }

  // ── Total pending summary ───────────────────────────────────────────────
  Widget _buildSummaryCard(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
        ],
        border: Border.all(
          color: isDark ? AppColors.darkBorder : Colors.grey[200]!,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Iconsax.shield_tick,
              color: AppColors.primary,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${_requests.length}',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Total Pending Requests',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: isDark ? Colors.white70 : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: -0.2, end: 0);
  }

  // ── Activity-type filter chips ──────────────────────────────────────────
  Widget _buildFilterChips(bool isDark) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: _filterTypes.map((type) {
          final isActive = _activeFilter == type;
          final count = _countFor(type);
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => setState(() => _activeFilter = type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.primary
                      : (isDark ? AppColors.darkSurface : Colors.white),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: isActive
                        ? AppColors.primary
                        : (isDark ? AppColors.darkBorder : Colors.grey[300]!),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$type ($count)',
                  style: GoogleFonts.poppins(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: isActive
                        ? Colors.white
                        : (isDark ? Colors.white70 : AppColors.textSecondary),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildList(bool isDark) {
    final items = _visibleRequests;
    if (items.isEmpty) {
      // Scrollable so pull-to-refresh still works on the empty state.
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.28),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Iconsax.tick_circle,
                size: 64,
                color: AppColors.textTertiary.withOpacity(0.8),
              ),
              const SizedBox(height: 16),
              Text(
                'No pending payroll requests',
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      itemCount: items.length,
      itemBuilder: (context, index) =>
          _buildRequestCard(items[index], isDark, index),
    );
  }

  Widget _buildRequestCard(PayrollRequest request, bool isDark, int index) {
    const headerColor = Color.fromARGB(
      255,
      100,
      112,
      243,
    ); // indigo, matching Leave Approvals

    return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(9),
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: Colors.black.withOpacity(0.10),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
            ],
            border: Border.all(
              color: isDark ? AppColors.darkBorder : Colors.grey[200]!,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: const BoxDecoration(
                  color: headerColor,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(8),
                    topRight: Radius.circular(8),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        request.empName,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _activityChip(request.activityType),
                  ],
                ),
              ),

              // Body
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 7, 8, 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _miniInfo('Emp Code', request.empCode, isDark),
                              _miniInfo('Branch', request.branch, isDark),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              _miniInfo(
                                'Month/Year',
                                request.monthYear,
                                isDark,
                              ),
                              _miniInfo(
                                'Applied',
                                _shortDate(request.appliedDate),
                                isDark,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Actions
                    _iconAction(
                      icon: Iconsax.eye,
                      color: AppColors.primary,
                      onPressed: () => _openDetails(request),
                    ),
                    _iconAction(
                      icon: Iconsax.close_circle,
                      color: AppColors.error,
                      onPressed: () => _confirmAndApply(request, 'Rejected'),
                    ),
                    _iconAction(
                      icon: Iconsax.tick_circle,
                      color: AppColors.success,
                      filled: true,
                      onPressed: () => _confirmAndApply(request, 'Approved'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(duration: 220.ms, delay: (40 * index).ms)
        .slideX(begin: 0.08, end: 0, curve: Curves.easeOut);
  }

  /// Shows the confirmation alert from the list (tick/cross), then submits.
  Future<void> _confirmAndApply(PayrollRequest request, String status) async {
    final result = await showPayrollDecisionDialog(context, request, status);
    if (result != null) {
      await _submitDecision(
        request,

        result['decision']!,
        result['remarks'] ?? '',
      );
    }
  }

  Widget _miniInfo(String label, String value, bool isDark) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 8,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: isDark ? Colors.white54 : AppColors.textTertiary,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _activityChip(String type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.25),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        type.toUpperCase(),
        style: GoogleFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _iconAction({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    bool filled = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 5),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: filled ? color.withOpacity(0.10) : Colors.transparent,
            border: Border.all(color: color.withOpacity(0.5), width: 1),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }

  String _shortDate(String fullDate) => fullDate.split(' ').first;
}

// ─────────────────────────────────────────────────────────────────────────
// Request Details — full screen (mirrors the web modal)
// ─────────────────────────────────────────────────────────────────────────

class BranchPayrollDetailScreen extends StatefulWidget {
  final PayrollRequest request;

  const BranchPayrollDetailScreen({super.key, required this.request});

  @override
  State<BranchPayrollDetailScreen> createState() =>
      _BranchPayrollDetailScreenState();
}

class _BranchPayrollDetailScreenState extends State<BranchPayrollDetailScreen> {
  /// Starts as the summary passed in, then upgrades to the full detail once
  /// the `/branch-payroll-request-detail/{id}` call returns.
  late PayrollRequest request;
  bool _loadingDetail = true;

  @override
  void initState() {
    super.initState();
    request = widget.request;
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    try {
      final token = context.read<AuthProvider>().token;
      if (token != null) {
        final detail = await ApiService.getBranchPayrollRequestDetail(
          token,
          widget.request.id,
          // Preserve the level bucket — the detail endpoint omits it.
          levelKey: widget.request.levelKey,
        );
        if (detail != null && mounted) setState(() => request = detail);
      }
    } catch (e) {
      debugPrint('Error loading payroll request detail: $e');
    } finally {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const headerColor = Color(0xFFE05B5B); // red header, matching design

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header bar
            Container(
              color: headerColor,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  const Icon(
                    Iconsax.document_text,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Request Details',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),

            // Thin loader while the full detail is being fetched.
            if (_loadingDetail)
              const LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Color(0xFFF3C9C9),
                valueColor: AlwaysStoppedAnimation(Color(0xFFE05B5B)),
              ),

            // Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _card(isDark, [
                      _sectionHeader(
                        Iconsax.user,
                        'Employee Information',
                        isDark,
                      ),
                      const SizedBox(height: 8),
                      // Name with the employee code as a #-prefixed subtitle.
                      _nameCell(request.empName, request.empCode, isDark),
                      const SizedBox(height: 8),
                      // Designation / Department / DOJ on a three-column row.
                      // Department gets extra width so long names fit on one line.
                      _detailRow3(
                        [
                          _DetailPair('Designation', request.designation),
                          _DetailPair('Department', request.department),
                          _DetailPair('DOJ', _toDdMmYy(request.doj)),
                        ],
                        isDark,
                        flex: [4, 5, 3],
                      ),
                      // Branch on the left, Mobile aligned under DOJ (col 3).
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _detailCell(
                                _DetailPair('Branch', request.branch),
                                isDark,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(child: SizedBox()),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _detailCell(
                                _DetailPair('Mobile', request.mobile),
                                isDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    _card(isDark, [
                      Row(
                        children: [
                          Icon(
                            Iconsax.note_text,
                            size: 14,
                            color: const Color(0xFFE05B5B),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Request Details',
                            softWrap: false,
                            overflow: TextOverflow.visible,
                            style: GoogleFonts.poppins(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Colors.white
                                  : AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _activityChipColored(request.activityType),
                            ),
                          ),
                          const SizedBox(width: 6),
                          _statusBadge(request.status),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _detailGrid([
                        _DetailPair('Month/Year', request.monthYear),
                        _DetailPair('Applied Date', request.appliedDate),
                      ], isDark),
                    ]),
                    // Activity Data — only when the backend supplies it.
                    // File references (e.g. the qualification PDF) are pulled
                    // out of the text grid and shown as tappable viewer tiles.
                    if (request.activityData.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _card(isDark, [
                        _sectionHeader(
                          Iconsax.task_square,
                          'Activity Data',
                          isDark,
                        ),
                        const SizedBox(height: 8),

                        // _detailGrid(
                        //   request.activityData.entries
                        //       .where((e) => !isDocumentReference(e.value))
                        //       .map(
                        //         (e) => _DetailPair(
                        //           _activityLabel(e.key),
                        //           _toDdMmYy(e.value),
                        //         ),
                        //       )
                        //       .toList(),
                        //   isDark,
                        // ),

                        //               _buildActivityData(request.activityData, isDark),
                        //                ]),
                        //                ],
                        //               for (final e in request.activityData.entries.where(
                        //                 (e) => isDocumentReference(e.value),
                        //               ))
                        //                 _documentCell(_activityLabel(e.key), e.value, isDark),
                        //             ]),
                        // ],
                        _buildActivityData(request.activityData, isDark),
                      ]),
                    ],

                    // Approval timeline — only when the backend supplies it.
                    if (request.timeline.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _card(isDark, [
                        _sectionHeader(
                          Iconsax.clock,
                          'Approval Timeline',
                          isDark,
                        ),
                        const SizedBox(height: 10),
                        _buildTimeline(request.timeline, isDark),
                      ]),
                    ],
                  ],
                ),
              ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.04, end: 0),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.white,
                border: Border(
                  top: BorderSide(
                    color: isDark ? AppColors.darkBorder : Colors.grey[200]!,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _decide('Rejected'),
                      icon: const Icon(Iconsax.close_circle, size: 16),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: BorderSide(color: AppColors.error),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _decide('Approved'),
                      icon: const Icon(Iconsax.tick_circle, size: 16),
                      label: const Text('Approve'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _decide(String status) async {
    final result = await showPayrollDecisionDialog(context, request, status);
    if (result == null || !mounted) return;

    final token = context.read<AuthProvider>().token;
    if (token == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CustomLoader(size: 50)),
    );

    final res = await ApiService.postBranchPayrollApproval(
      token: token,
      requestId: request.id,
      action: payrollActionToken(result['decision']!),
      remarks: result['remarks'] ?? '',
      level: payrollLevelOf(request),
    );

    if (!mounted) return;
    Navigator.pop(context); // dismiss loader

    if (res.success) {
      // Return the decision so the list removes the row + shows a snackbar.
      Navigator.pop(context, result);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res.message.isNotEmpty
                ? res.message
                : 'Failed to ${status.toLowerCase()} request',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  /// Compact section container used for each block of the details screen.
  Widget _card(bool isDark, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _sectionHeader(
    IconData icon,
    String title,
    bool isDark, {
    bool expand = true,
  }) {
    return Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFFE05B5B)),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  /// Two-column responsive label/value grid. Pairs with an empty value are
  /// skipped (the list API omits fields like DOJ / Mobile).
  Widget _detailGrid(List<_DetailPair> rawPairs, bool isDark) {
    final pairs = rawPairs.where((p) => p.value.trim().isNotEmpty).toList();
    if (pairs.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (int i = 0; i < pairs.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _detailCell(pairs[i], isDark)),
                const SizedBox(width: 10),
                Expanded(
                  child: i + 1 < pairs.length
                      ? _detailCell(pairs[i + 1], isDark)
                      : const SizedBox(),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Name value with the employee code shown as a `#`-prefixed subtitle.
  Widget _nameCell(String name, String code, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'NAME',
          style: GoogleFonts.inter(
            fontSize: 8.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: isDark ? Colors.white54 : AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 1),
        // Name followed inline by the #-prefixed employee code.
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: name,
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
              ),
              if (code.trim().isNotEmpty)
                TextSpan(
                  text: '  #$code',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white54 : AppColors.textTertiary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Three-column label/value row. Pairs with an empty value are skipped so the
  /// remaining cells share the width. Optional [flex] weights let a column
  /// (e.g. a long Department name) take more horizontal room than its siblings.
  Widget _detailRow3(
    List<_DetailPair> rawPairs,
    bool isDark, {
    List<int>? flex,
  }) {
    final kept = <MapEntry<_DetailPair, int>>[];
    for (int i = 0; i < rawPairs.length; i++) {
      if (rawPairs[i].value.trim().isEmpty) continue;
      kept.add(
        MapEntry(rawPairs[i], flex != null && i < flex.length ? flex[i] : 1),
      );
    }
    if (kept.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < kept.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              flex: kept[i].value,
              child: _detailCell(kept[i].key, isDark),
            ),
          ],
        ],
      ),
    );
  }

  /// Display-label overrides for Activity Data keys. The backend key is
  /// prettified (e.g. `ncp_days` → `Ncp Days`); here we swap in the
  /// business-facing wording. `_detailCell` upper-cases the result.
  String _activityLabel(String key) {
    switch (key.trim().toLowerCase()) {
      case 'ncp days':
        return 'Loss of Pay(LOP)';
      case 'last working date':
        return 'Last Working Date Up To';
      case 'qualification pdf':
      case 'qualification document':
        return 'Qualification';
      default:
        return key;
    }
  } // ============================================================
  // ACTIVITY DATA BUILDER
  // ============================================================

  // Widget _buildActivityData(dynamic data, bool isDark) {
  //   if (data == null) {
  //     return const SizedBox.shrink();
  //   }

  //   final widgets = <Widget>[];

  //   // ----------------------------------------------------------
  //   // Activity Data is a Map
  //   // ----------------------------------------------------------
  //   if (data is Map) {
  //     for (final entry in data.entries) {
  //       final key = entry.key.toString();
  //       final value = entry.value;

  //       if (value == null) {
  //         continue;
  //       }

  //       // ------------------------------------------------------
  //       // Nested Map
  //       // ------------------------------------------------------
  //       if (value is Map) {
  //         widgets.add(
  //           _buildFamilyMemberCard(
  //             value,
  //             int.tryParse(key) ?? widgets.length + 1,
  //             isDark,
  //           ),
  //         );

  //         continue;
  //       }

  //       final stringValue = value.toString().trim();

  //       if (stringValue.isEmpty) {
  //         continue;
  //       }

  //       // ------------------------------------------------------
  //       // Family Details stored as String
  //       // ------------------------------------------------------
  //       if (_looksLikeFamilyData(stringValue)) {
  //         final familyWidgets = _buildFamilyMembersFromString(
  //           stringValue,
  //           isDark,
  //         );

  //         if (familyWidgets.isNotEmpty) {
  //           widgets.addAll(familyWidgets);
  //           continue;
  //         }
  //       }

  //       // ------------------------------------------------------
  //       // Document
  //       // ------------------------------------------------------
  //       if (isDocumentReference(stringValue)) {
  //         widgets.add(_documentCell(_activityLabel(key), stringValue, isDark));

  //         continue;
  //       }

  //       // ------------------------------------------------------
  //       // Normal Activity Data
  //       // ------------------------------------------------------
  //       widgets.add(
  //         Padding(
  //           padding: const EdgeInsets.only(bottom: 10),
  //           child: _detailCell(
  //             _DetailPair(_activityLabel(key), _toDdMmYy(stringValue)),
  //             isDark,
  //           ),
  //         ),
  //       );
  //     }
  //   }

  //   // ----------------------------------------------------------
  //   // No Activity Data
  //   // ----------------------------------------------------------
  //   if (widgets.isEmpty) {
  //     return Text(
  //       'No activity data available.',
  //       style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textTertiary),
  //     );
  //   }

  //   return Column(
  //     crossAxisAlignment: CrossAxisAlignment.start,
  //     children: widgets,
  //   );
  // }

  // // ============================================================
  // // CHECK WHETHER VALUE CONTAINS FAMILY DATA
  // // ============================================================

  // bool _looksLikeFamilyData(String value) {
  //   final lower = value.toLowerCase();

  //   return lower.contains('member_name') &&
  //       lower.contains('relation') &&
  //       lower.contains('dob');
  // }

  // // ============================================================
  // // PARSE FAMILY MEMBERS FROM STRING
  // // ============================================================

  // List<Widget> _buildFamilyMembersFromString(String value, bool isDark) {
  //   final widgets = <Widget>[];

  //   final memberRegex = RegExp(r'(\d+)\s*:\s*\{([^{}]*)\}');

  //   final matches = memberRegex.allMatches(value);

  //   int memberNumber = 1;

  //   for (final match in matches) {
  //     final memberData = match.group(2) ?? '';

  //     final member = <String, String>{};

  //     final fields = memberData.split(',');

  //     for (final field in fields) {
  //       final separatorIndex = field.indexOf(':');

  //       if (separatorIndex == -1) {
  //         continue;
  //       }

  //       final key = field.substring(0, separatorIndex).trim();

  //       final fieldValue = field.substring(separatorIndex + 1).trim();

  //       if (key.isNotEmpty) {
  //         member[key] = fieldValue;
  //       }
  //     }

  //     if (member.isNotEmpty) {
  //       widgets.add(_buildFamilyMemberCard(member, memberNumber, isDark));

  //       memberNumber++;
  //     }
  //   }

  //   return widgets;
  // }

  // // ============================================================
  // // FAMILY MEMBER CARD
  // // ============================================================

  // Widget _buildFamilyMemberCard(Map member, int memberNumber, bool isDark) {
  //   final name = _cleanActivityValue(member['member_name']);

  //   final gender = _formatGender(_cleanActivityValue(member['gender']));

  //   final relation = _cleanActivityValue(member['relation']);

  //   final dob = _toDdMmYyyy(_cleanActivityValue(member['dob']));

  //   return Container(
  //     width: double.infinity,
  //     margin: const EdgeInsets.only(bottom: 10),
  //     padding: const EdgeInsets.all(10),
  //     decoration: BoxDecoration(
  //       color: isDark ? AppColors.darkBackground : Colors.grey.shade50,
  //       borderRadius: BorderRadius.circular(8),
  //       border: Border.all(
  //         color: isDark ? AppColors.darkBorder : Colors.grey.shade200,
  //       ),
  //     ),
  //     child: Column(
  //       crossAxisAlignment: CrossAxisAlignment.start,
  //       children: [
  //         // Member name
  //         Row(
  //           children: [
  //             Container(
  //               width: 24,
  //               height: 24,
  //               alignment: Alignment.center,
  //               decoration: BoxDecoration(
  //                 color: const Color(0xFFE05B5B).withOpacity(0.12),
  //                 borderRadius: BorderRadius.circular(6),
  //               ),
  //               child: Text(
  //                 '$memberNumber',
  //                 style: GoogleFonts.poppins(
  //                   fontSize: 10,
  //                   fontWeight: FontWeight.bold,
  //                   color: const Color(0xFFE05B5B),
  //                 ),
  //               ),
  //             ),

  //             const SizedBox(width: 8),

  //             Expanded(
  //               child: Text(
  //                 name.isEmpty ? 'Family Member $memberNumber' : name,
  //                 style: GoogleFonts.poppins(
  //                   fontSize: 11.5,
  //                   fontWeight: FontWeight.w700,
  //                   color: isDark ? Colors.white : AppColors.textPrimary,
  //                 ),
  //               ),
  //             ),
  //           ],
  //         ),

  //         const SizedBox(height: 10),

  //         // Relation + Gender
  //         Row(
  //           crossAxisAlignment: CrossAxisAlignment.start,
  //           children: [
  //             Expanded(
  //               child: _detailCell(
  //                 _DetailPair('Relation', relation.isEmpty ? '-' : relation),
  //                 isDark,
  //               ),
  //             ),

  //             const SizedBox(width: 10),

  //             Expanded(
  //               child: _detailCell(
  //                 _DetailPair('Gender', gender.isEmpty ? '-' : gender),
  //                 isDark,
  //               ),
  //             ),
  //           ],
  //         ),

  //         const SizedBox(height: 10),

  //         // Date of Birth
  //         _detailCell(
  //           _DetailPair('Date of Birth', dob.isEmpty ? '-' : dob),
  //           isDark,
  //         ),
  //       ],
  //     ),
  //   );
  // }

  // // ============================================================
  // // CLEAN ACTIVITY VALUE
  // // ============================================================

  // String _cleanActivityValue(dynamic value) {
  //   if (value == null) {
  //     return '';
  //   }

  //   String result = value.toString().trim();

  //   if (result.length >= 2 &&
  //       ((result.startsWith('"') && result.endsWith('"')) ||
  //           (result.startsWith("'") && result.endsWith("'")))) {
  //     result = result.substring(1, result.length - 1);
  //   }

  //   return result.trim();
  // }

  // // ============================================================
  // // FORMAT GENDER
  // // ============================================================

  // String _formatGender(String value) {
  //   switch (value.trim().toLowerCase()) {
  //     case 'f':
  //     case 'female':
  //       return 'Female';

  //     case 'm':
  //     case 'male':
  //       return 'Male';

  //     default:
  //       return value;
  //   }
  // }

  // // ============================================================
  // // DATE FORMAT - DD-MM-YYYY
  // // ============================================================

  // String _toDdMmYyyy(String raw) {
  //   final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw.trim());

  //   if (match == null) {
  //     return raw;
  //   }

  //   return '${match.group(3)}-'
  //       '${match.group(2)}-'
  //       '${match.group(1)}';
  // }
  // ============================================================
  // ACTIVITY DATA BUILDER
  // ============================================================

  // Widget _buildActivityData(dynamic data, bool isDark) {
  //   if (data == null) {
  //     return const SizedBox.shrink();
  //   }

  //   final widgets = <Widget>[];
  //   final familyMembers = <Map>[];

  //   if (data is Map) {
  //     for (final entry in data.entries) {
  //       final key = entry.key.toString();
  //       final value = entry.value;

  //       if (value == null) {
  //         continue;
  //       }

  //       // Nested family member data
  //       if (value is Map && value.containsKey('member_name')) {
  //         familyMembers.add(value);
  //         continue;
  //       }

  //       final stringValue = value.toString().trim();

  //       if (stringValue.isEmpty) {
  //         continue;
  //       }

  //       // Family details stored as String
  //       if (_looksLikeFamilyData(stringValue)) {
  //         final parsedMembers = _parseFamilyMembersFromString(stringValue);

  //         if (parsedMembers.isNotEmpty) {
  //           familyMembers.addAll(parsedMembers);
  //           continue;
  //         }
  //       }

  //       // Document
  //       if (isDocumentReference(stringValue)) {
  //         widgets.add(_documentCell(_activityLabel(key), stringValue, isDark));
  //         continue;
  //       }

  //       // Normal activity data
  //       widgets.add(
  //         Padding(
  //           padding: const EdgeInsets.only(bottom: 10),
  //           child: _detailCell(
  //             _DetailPair(_activityLabel(key), _toDdMmYy(stringValue)),
  //             isDark,
  //           ),
  //         ),
  //       );
  //     }
  //   }

  //   // One compact card for all family members
  //   if (familyMembers.isNotEmpty) {
  //     widgets.insert(0, _buildFamilyMembersCard(familyMembers, isDark));
  //   }

  //   if (widgets.isEmpty) {
  //     return Text(
  //       'No activity data available.',
  //       style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textTertiary),
  //     );
  //   }

  //   return Column(
  //     crossAxisAlignment: CrossAxisAlignment.start,
  //     children: widgets,
  //   );
  // }

  // // ============================================================
  // // CHECK FAMILY DATA
  // // ============================================================

  // bool _looksLikeFamilyData(String value) {
  //   final lower = value.toLowerCase();

  //   return lower.contains('member_name') &&
  //       lower.contains('relation') &&
  //       lower.contains('dob');
  // }

  // // ============================================================
  // // PARSE FAMILY MEMBERS FROM STRING
  // // ============================================================

  // List<Map> _parseFamilyMembersFromString(String value) {
  //   final members = <Map>[];

  //   final memberRegex = RegExp(r'(\d+)\s*:\s*\{([^{}]*)\}');

  //   final matches = memberRegex.allMatches(value);

  //   for (final match in matches) {
  //     final memberData = match.group(2) ?? '';

  //     final member = <String, String>{};

  //     final fields = memberData.split(',');

  //     for (final field in fields) {
  //       final separatorIndex = field.indexOf(':');

  //       if (separatorIndex == -1) {
  //         continue;
  //       }

  //       final key = field.substring(0, separatorIndex).trim();

  //       final fieldValue = field.substring(separatorIndex + 1).trim();

  //       if (key.isNotEmpty) {
  //         member[key] = fieldValue;
  //       }
  //     }

  //     if (member.isNotEmpty) {
  //       members.add(member);
  //     }
  //   }

  //   return members;
  // }

  // // ============================================================
  // // ONE CARD FOR ALL FAMILY MEMBERS
  // // ============================================================

  // Widget _buildFamilyMembersCard(List<Map> members, bool isDark) {
  //   return Container(
  //     width: double.infinity,
  //     margin: const EdgeInsets.only(bottom: 10),
  //     padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  //     decoration: BoxDecoration(
  //       color: isDark ? AppColors.darkBackground : Colors.grey.shade50,
  //       borderRadius: BorderRadius.circular(8),
  //       border: Border.all(
  //         color: isDark ? AppColors.darkBorder : Colors.grey.shade200,
  //       ),
  //     ),
  //     child: Column(
  //       children: [
  //         for (int i = 0; i < members.length; i++) ...[
  //           _buildCompactFamilyMember(members[i], i + 1, isDark),

  //           if (i != members.length - 1)
  //             Divider(
  //               height: 18,
  //               thickness: 0.7,
  //               color: isDark ? AppColors.darkBorder : Colors.grey.shade200,
  //             ),
  //         ],
  //       ],
  //     ),
  //   );
  // }

  // // ============================================================
  // // COMPACT FAMILY MEMBER
  // // ============================================================

  // Widget _buildCompactFamilyMember(Map member, int memberNumber, bool isDark) {
  //   final name = _cleanActivityValue(member['member_name']);

  //   final gender = _formatGender(_cleanActivityValue(member['gender']));

  //   final relation = _cleanActivityValue(member['relation']);

  //   final dob = _toDdMmYyyy(_cleanActivityValue(member['dob']));

  //   return Padding(
  //     padding: const EdgeInsets.symmetric(vertical: 6),
  //     child: Column(
  //       crossAxisAlignment: CrossAxisAlignment.start,
  //       children: [
  //         // Name
  //         Row(
  //           children: [
  //             Container(
  //               width: 24,
  //               height: 24,
  //               alignment: Alignment.center,
  //               decoration: BoxDecoration(
  //                 color: const Color(0xFFE05B5B).withOpacity(0.12),
  //                 borderRadius: BorderRadius.circular(6),
  //               ),
  //               child: Text(
  //                 '$memberNumber',
  //                 style: GoogleFonts.poppins(
  //                   fontSize: 10,
  //                   fontWeight: FontWeight.bold,
  //                   color: const Color(0xFFE05B5B),
  //                 ),
  //               ),
  //             ),

  //             const SizedBox(width: 8),

  //             Expanded(
  //               child: Text(
  //                 name.isEmpty ? 'Family Member $memberNumber' : name,
  //                 maxLines: 1,
  //                 overflow: TextOverflow.ellipsis,
  //                 style: GoogleFonts.poppins(
  //                   fontSize: 11.5,
  //                   fontWeight: FontWeight.w700,
  //                   color: isDark ? Colors.white : AppColors.textPrimary,
  //                 ),
  //               ),
  //             ),
  //           ],
  //         ),

  //         const SizedBox(height: 7),

  //         // Relation / Gender / DOB
  //         Row(
  //           crossAxisAlignment: CrossAxisAlignment.start,
  //           children: [
  //             Expanded(
  //               child: _compactFamilyDetail(
  //                 'Relation',
  //                 relation.isEmpty ? '-' : relation,
  //                 isDark,
  //               ),
  //             ),

  //             const SizedBox(width: 8),

  //             Expanded(
  //               child: _compactFamilyDetail(
  //                 'Gender',
  //                 gender.isEmpty ? '-' : gender,
  //                 isDark,
  //               ),
  //             ),

  //             const SizedBox(width: 8),

  //             Expanded(
  //               child: _compactFamilyDetail(
  //                 'DOB',
  //                 dob.isEmpty ? '-' : dob,
  //                 isDark,
  //               ),
  //             ),
  //           ],
  //         ),
  //       ],
  //     ),
  //   );
  // }

  // // ============================================================
  // // COMPACT FAMILY DETAIL
  // // ============================================================

  // Widget _compactFamilyDetail(String label, String value, bool isDark) {
  //   return Column(
  //     crossAxisAlignment: CrossAxisAlignment.start,
  //     children: [
  //       Text(
  //         label.toUpperCase(),
  //         maxLines: 1,
  //         overflow: TextOverflow.ellipsis,
  //         style: GoogleFonts.inter(
  //           fontSize: 7.5,
  //           fontWeight: FontWeight.w600,
  //           letterSpacing: 0.3,
  //           color: isDark ? Colors.white54 : AppColors.textTertiary,
  //         ),
  //       ),

  //       const SizedBox(height: 1),

  //       Text(
  //         value,
  //         maxLines: 1,
  //         overflow: TextOverflow.ellipsis,
  //         style: GoogleFonts.poppins(
  //           fontSize: 10.5,
  //           fontWeight: FontWeight.w600,
  //           color: isDark ? Colors.white : AppColors.textPrimary,
  //         ),
  //       ),
  //     ],
  //   );
  // }

  // // ============================================================
  // // CLEAN ACTIVITY VALUE
  // // ============================================================

  // String _cleanActivityValue(dynamic value) {
  //   if (value == null) {
  //     return '';
  //   }

  //   String result = value.toString().trim();

  //   if (result.length >= 2 &&
  //       ((result.startsWith('"') && result.endsWith('"')) ||
  //           (result.startsWith("'") && result.endsWith("'")))) {
  //     result = result.substring(1, result.length - 1);
  //   }

  //   return result.trim();
  // }

  // // ============================================================
  // // FORMAT GENDER
  // // ============================================================

  // String _formatGender(String value) {
  //   switch (value.trim().toLowerCase()) {
  //     case 'f':
  //     case 'female':
  //       return 'Female';

  //     case 'm':
  //     case 'male':
  //       return 'Male';

  //     default:
  //       return value;
  //   }
  // }

  // // ============================================================
  // // DATE FORMAT - DD-MM-YYYY
  // // ============================================================

  // String _toDdMmYyyy(String raw) {
  //   final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw.trim());

  //   if (match == null) {
  //     return raw;
  //   }

  //   return '${match.group(3)}-'
  //       '${match.group(2)}-'
  //       '${match.group(1)}';
  // }

  Widget _buildActivityData(dynamic data, bool isDark) {
    if (data == null) {
      return const SizedBox.shrink();
    }

    final familyMembers = <Map<String, dynamic>>[];
    final normalWidgets = <Widget>[];

    // ----------------------------------------------------------
    // Collect family members from ANY common structure
    // ----------------------------------------------------------
    void collect(dynamic value) {
      if (value == null) return;

      // Map
      if (value is Map) {
        // Direct family member
        if (_isFamilyMember(value)) {
          familyMembers.add(Map<String, dynamic>.from(value));
          return;
        }

        // Nested map
        for (final entry in value.entries) {
          collect(entry.value);
        }

        return;
      }

      // List
      if (value is List) {
        for (final item in value) {
          collect(item);
        }

        return;
      }

      // String
      if (value is String) {
        final text = value.trim();

        if (text.isEmpty) return;

        // Try JSON first
        try {
          final decoded = jsonDecode(text);

          if (decoded is Map || decoded is List) {
            collect(decoded);
            return;
          }
        } catch (_) {
          // Not valid JSON. Continue with normal parser.
        }

        // Handle Dart Map/List string format
        if (_looksLikeFamilyData(text)) {
          final parsed = _parseFamilyMembersFromString(text);

          if (parsed.isNotEmpty) {
            familyMembers.addAll(parsed);
            return;
          }
        }
      }
    }

    // ----------------------------------------------------------
    // First collect all family members
    // ----------------------------------------------------------
    if (data is Map) {
      for (final entry in data.entries) {
        final key = entry.key.toString();
        final value = entry.value;

        if (value == null) continue;

        if (_isFamilyMember(value)) {
          collect(value);
          continue;
        }

        if (value is List) {
          final before = familyMembers.length;

          collect(value);

          if (familyMembers.length > before) {
            continue;
          }
        }

        if (value is Map) {
          final before = familyMembers.length;

          collect(value);

          if (familyMembers.length > before) {
            continue;
          }
        }

        final stringValue = value.toString().trim();

        if (stringValue.isEmpty) continue;

        if (_looksLikeFamilyData(stringValue)) {
          final before = familyMembers.length;

          collect(stringValue);

          if (familyMembers.length > before) {
            continue;
          }
        }

        // Document
        if (isDocumentReference(stringValue)) {
          normalWidgets.add(
            _documentCell(_activityLabel(key), stringValue, isDark),
          );

          continue;
        }

        // Normal activity field
        normalWidgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _detailCell(
              _DetailPair(_activityLabel(key), _toDdMmYy(stringValue)),
              isDark,
            ),
          ),
        );
      }
    } else {
      collect(data);
    }

    final widgets = <Widget>[];

    // ----------------------------------------------------------
    // ONE FAMILY CARD
    // ----------------------------------------------------------
    if (familyMembers.isNotEmpty) {
      widgets.add(_buildFamilyMembersCard(familyMembers, isDark));
    }

    // ----------------------------------------------------------
    // NORMAL ACTIVITY DATA
    // ----------------------------------------------------------
    widgets.addAll(normalWidgets);

    // ----------------------------------------------------------
    // EMPTY
    // ----------------------------------------------------------
    if (widgets.isEmpty) {
      return Text(
        'No activity data available.',
        style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textTertiary),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  // ============================================================
  // CHECK FAMILY MEMBER
  // ============================================================

  bool _isFamilyMember(dynamic value) {
    if (value is! Map) {
      return false;
    }

    final keys = value.keys.map((e) => e.toString().toLowerCase()).toSet();

    return keys.contains('member_name') ||
        (keys.contains('relation') && keys.contains('dob'));
  }

  // ============================================================
  // CHECK FAMILY DATA STRING
  // ============================================================

  bool _looksLikeFamilyData(String value) {
    final lower = value.toLowerCase();

    return lower.contains('member_name') &&
        (lower.contains('relation') ||
            lower.contains('dob') ||
            lower.contains('gender'));
  }

  // ============================================================
  // PARSE FAMILY MEMBERS FROM STRING
  // ============================================================

  List<Map<String, dynamic>> _parseFamilyMembersFromString(String value) {
    final members = <Map<String, dynamic>>[];

    // Remove outer list brackets
    String text = value.trim();

    if (text.startsWith('[') && text.endsWith(']')) {
      text = text.substring(1, text.length - 1);
    }

    // ----------------------------------------------------------
    // Find every {...} block
    // ----------------------------------------------------------
    final matches = RegExp(r'\{([^{}]*)\}').allMatches(text);

    for (final match in matches) {
      final content = match.group(1) ?? '';

      final member = _parseSingleFamilyMember(content);

      if (member.isNotEmpty) {
        members.add(member);
      }
    }

    return members;
  }

  // ============================================================
  // PARSE SINGLE FAMILY MEMBER
  // ============================================================

  Map<String, dynamic> _parseSingleFamilyMember(String content) {
    final member = <String, dynamic>{};

    // Handles:
    //
    // member_name: ABC,
    // gender: Male,
    // relation: SELF,
    // dob: 2002-04-30
    //
    final regex = RegExp(
      r'([a-zA-Z_]+)\s*:\s*'
      r'([^,}]+)',
    );

    for (final match in regex.allMatches(content)) {
      final key = match.group(1)?.trim() ?? '';

      final value = match.group(2)?.trim() ?? '';

      if (key.isNotEmpty) {
        member[key] = value;
      }
    }

    return member;
  }

  // ============================================================
  // ONE CARD FOR ALL FAMILY MEMBERS
  // ============================================================

  Widget _buildFamilyMembersCard(
    List<Map<String, dynamic>> members,
    bool isDark,
  ) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBackground : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          for (int i = 0; i < members.length; i++) ...[
            _buildCompactFamilyMember(members[i], i + 1, isDark),

            if (i < members.length - 1)
              Divider(
                height: 18,
                thickness: 0.7,
                color: isDark ? AppColors.darkBorder : Colors.grey.shade200,
              ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // COMPACT FAMILY MEMBER
  // ============================================================

  Widget _buildCompactFamilyMember(
    Map<String, dynamic> member,
    int number,
    bool isDark,
  ) {
    final name = _cleanActivityValue(member['member_name']);

    final relation = _cleanActivityValue(member['relation']);

    final gender = _formatGender(_cleanActivityValue(member['gender']));

    final dob = _toDdMmYyyy(_cleanActivityValue(member['dob']));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFE05B5B).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$number',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFE05B5B),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: Text(
                  name.isEmpty ? 'Family Member $number' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 7),

          Row(
            children: [
              Expanded(
                child: _compactFamilyDetail(
                  'Relation',
                  relation.isEmpty ? '-' : relation,
                  isDark,
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: _compactFamilyDetail(
                  'Gender',
                  gender.isEmpty ? '-' : gender,
                  isDark,
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: _compactFamilyDetail(
                  'DOB',
                  dob.isEmpty ? '-' : dob,
                  isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // COMPACT DETAIL
  // ============================================================

  Widget _compactFamilyDetail(String label, String value, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            fontSize: 7.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: isDark ? Colors.white54 : AppColors.textTertiary,
          ),
        ),

        const SizedBox(height: 1),

        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // CLEAN VALUE
  // ============================================================

  String _cleanActivityValue(dynamic value) {
    if (value == null) {
      return '';
    }

    String result = value.toString().trim();

    if (result.length >= 2 &&
        ((result.startsWith('"') && result.endsWith('"')) ||
            (result.startsWith("'") && result.endsWith("'")))) {
      result = result.substring(1, result.length - 1);
    }

    return result.trim();
  }

  // ============================================================
  // FORMAT GENDER
  // ============================================================

  String _formatGender(String value) {
    switch (value.trim().toLowerCase()) {
      case 'f':
      case 'female':
        return 'Female';

      case 'm':
      case 'male':
        return 'Male';

      default:
        return value;
    }
  }

  // ============================================================
  // DATE FORMAT
  // ============================================================

  String _toDdMmYyyy(String raw) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw.trim());

    if (match == null) {
      return raw;
    }

    return '${match.group(3)}-'
        '${match.group(2)}-'
        '${match.group(1)}';
  }

  /// Activity-data row whose value is a file reference. Instead of printing
  /// the raw URL, we show a tappable tile that opens the document in the
  /// in-app viewer (PDF pages / pinch-zoom image), so the approver never
  /// leaves the app to check an attachment.
  Widget _documentCell(String label, String rawValue, bool isDark) {
    final isPdf = documentExtension(rawValue) == 'pdf';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 8.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: isDark ? Colors.white54 : AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 4),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(7),
              onTap: () => _openDocument(label, rawValue),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE05B5B).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: const Color(0xFFE05B5B).withOpacity(0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPdf ? Iconsax.document_text : Iconsax.gallery,
                      size: 13,
                      color: const Color(0xFFE05B5B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isPdf ? 'View PDF' : 'View Document',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFE05B5B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openDocument(String label, String rawValue) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentViewerScreen(
          url: resolveFileUrl(rawValue),
          title: label,
          authToken: context.read<AuthProvider>().token,
        ),
      ),
    );
  }

  Widget _detailCell(_DetailPair pair, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          pair.label.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 8.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: isDark ? Colors.white54 : AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          pair.value,
          style: GoogleFonts.poppins(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _activityChipColored(String type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        type.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.poppins(
          fontSize: 8,
          fontWeight: FontWeight.bold,
          color: AppColors.success,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: GoogleFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  // ── Vertical approval timeline — compact, fits in one view ───────────────
  Widget _buildTimeline(List<ApprovalStep> steps, bool isDark) {
    // Skip levels with no approver assigned.
    final assigned = steps
        .where((s) => s.name.trim().toLowerCase() != 'not assigned')
        .toList();

    if (assigned.isEmpty) {
      return Text(
        'No approval levels assigned.',
        style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textTertiary),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < assigned.length; i++)
          _timelineStep(assigned[i], i, i == assigned.length - 1),
      ],
    );
  }

  Widget _timelineStep(ApprovalStep step, int index, bool isLast) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _statusColor(step.status);
    final lineColor = isDark ? AppColors.darkBorder : Colors.grey[300]!;
    final icon = _statusIcon(step.status);

    return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Dot + vertical connector line
              Column(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 10, color: Colors.white),
                  ),
                  if (!isLast)
                    Expanded(child: Container(width: 2, color: lineColor)),
                ],
              ),
              const SizedBox(width: 10),
              // Role — manager name — status (one row per level)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: 1, bottom: isLast ? 0 : 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _roleLabel(step.level),
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          step.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? Colors.white70
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          step.status,
                          style: GoogleFonts.poppins(
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(duration: 220.ms, delay: (70 * index).ms)
        .slideX(begin: 0.06, end: 0, curve: Curves.easeOut);
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Icons.check_rounded;
      case 'rejected':
        return Icons.close_rounded;
      default:
        return Icons.hourglass_bottom_rounded;
    }
  }

  /// Strips the "L1 - " / "L2 - " level prefix, leaving just the role
  /// (e.g. "L1 - PM" → "PM"). Falls back to the original if nothing remains.
  String _roleLabel(String level) {
    final stripped = level
        .replaceFirst(RegExp(r'^\s*L\d+\s*[-–—]\s*'), '')
        .trim();
    return stripped.isEmpty ? level : stripped;
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Shared confirmation alert (approve / reject)
//
// Returns {'decision': 'Approved'|'Rejected', 'remarks': '...'} on confirm,
// or null if the user cancels.
// ─────────────────────────────────────────────────────────────────────────

Future<Map<String, String>?> showPayrollDecisionDialog(
  BuildContext context,
  PayrollRequest request,
  String status,
) {
  final isApproved = status == 'Approved';
  final actionName = isApproved ? 'Approval' : 'Rejection';
  final verbName = isApproved ? 'approve' : 'reject';
  final color = isApproved ? AppColors.success : AppColors.error;
  final remarksController = TextEditingController();

  return showDialog<Map<String, String>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        final isRemarksEmpty = remarksController.text.trim().isEmpty;
        // A remark is mandatory for both approve and reject.
        final canConfirm = !isRemarksEmpty;

        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                isApproved ? Iconsax.tick_circle : Iconsax.close_circle,
                color: color,
                size: 24,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Confirm $actionName',
                  style: AppTextStyles.titleLarge.copyWith(color: color),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.85,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    style: AppTextStyles.bodyMedium,
                    children: [
                      TextSpan(
                        text:
                            'Are you sure you want to $verbName the '
                            '${request.activityType} request for ',
                      ),
                      TextSpan(
                        text: request.empName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const TextSpan(text: '?'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: remarksController,
                  maxLines: 3,
                  autofocus: true,
                  style: AppTextStyles.bodyMedium,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Remarks',
                    hintText: 'Enter your remarks...',
                    labelStyle: TextStyle(color: color),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: color),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: color, width: 2),
                    ),
                  ),
                ),
                if (isRemarksEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      'Remarks are required to $verbName',
                      style: TextStyle(
                        color: AppColors.error,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: Text(
                    'Cancel',
                    style: AppTextStyles.labelLarge.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: ElevatedButton(
                    onPressed: canConfirm
                        ? () {
                            Navigator.pop(context, {
                              'decision': status,
                              'remarks': remarksController.text.trim(),
                            });
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canConfirm ? color : Colors.grey[300],
                      foregroundColor: canConfirm
                          ? Colors.white
                          : Colors.grey[600],
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Confirm $status',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

Color _statusColor(String status) {
  switch (status.toLowerCase()) {
    case 'approved':
      return AppColors.success;
    case 'rejected':
      return AppColors.error;
    case 'pending':
      return const Color(0xFFD9A406);
    default:
      return AppColors.textSecondary;
  }
}

/// The approval level number to submit for a request. Taken from the level
/// bucket key (e.g. `level5` → `5`); falls back to the pending step in the
/// timeline (e.g. `L5 - HR/Admin` → `5`).
String payrollLevelOf(PayrollRequest r) {
  final fromKey = RegExp(r'(\d+)').firstMatch(r.levelKey);
  if (fromKey != null) return fromKey.group(1)!;
  for (final s in r.timeline) {
    if (s.status.toLowerCase() == 'pending') {
      final m = RegExp(r'(\d+)').firstMatch(s.level);
      if (m != null) return m.group(1)!;
    }
  }
  return '';
}

/// Maps the UI decision to the exact action token the backend expects:
/// 'Approved' / 'Rejected' (capitalised). Verified against the live API —
/// these process the request; lowercase variants match 0 rows.
String payrollActionToken(String decision) =>
    decision.toLowerCase().startsWith('app') ? 'Approved' : 'Rejected';

// ─────────────────────────────────────────────────────────────────────────
// Detail-grid helper
// ─────────────────────────────────────────────────────────────────────────

class _DetailPair {
  final String label;
  final String value;
  const _DetailPair(this.label, this.value);
}

/// Reformats an ISO date (`YYYY-MM-DD`, optionally followed by a time) to
/// `DD-MM-YY`. Non-date values are returned unchanged so mixed activity-data
/// fields (reasons, counts, remarks) pass through untouched.
String _toDdMmYy(String raw) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw.trim());
  if (m == null) return raw;
  return '${m.group(3)}-${m.group(2)}-${m.group(1)!.substring(2)}';
}
