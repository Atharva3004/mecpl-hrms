// Requisition Summary — read-only list of pending manpower requisitions,
// grouped per project (mirrors the web admin requisition table).
//
// Shows: Project, Designation, Department, Required count, and Req-By date.
//
// Data is loaded from the `/pending-requisitions` API (page 1 only). The
// top-level `stats` block drives the summary header.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/requisition_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';

class RequisitionSummaryScreen extends StatefulWidget {
  const RequisitionSummaryScreen({super.key});

  @override
  State<RequisitionSummaryScreen> createState() =>
      _RequisitionSummaryScreenState();
}

class _RequisitionSummaryScreenState extends State<RequisitionSummaryScreen> {
  /// Selected branch (project) filter; null = All branches.
  String? _selectedBranch;

  // ---- API-backed state --------------------------------------------------
  List<RequisitionItem> _items = [];
  RequisitionStats _stats = RequisitionStats.empty;
  bool _isLoading = true;

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
        final result = await ApiService.getPendingRequisitions(token);
        _items = result.items;
        _stats = result.stats;
      }
    } catch (e) {
      debugPrint('Error loading pending requisitions: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<RequisitionItem> get _filtered {
    if (_selectedBranch == null) return _items;
    return _items.where((r) => r.project == _selectedBranch).toList();
  }

  /// Distinct branches (projects) present in the data, each with its pending
  /// requisition count. Sorted alphabetically. Drives the branch filter sheet.
  List<({String project, int count})> get _branchOptions {
    final counts = <String, int>{};
    for (final r in _items) {
      counts[r.project] = (counts[r.project] ?? 0) + 1;
    }
    final list = counts.entries
        .map((e) => (project: e.key, count: e.value))
        .toList()
      ..sort((a, b) => a.project.compareTo(b.project));
    return list;
  }

  // Opens a searchable bottom sheet to pick a branch. 'All branches' clears the
  // filter. Sets [_selectedBranch] on selection.
  Future<void> _openBranchFilter() async {
    final options = _branchOptions;
    final selected = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _BranchFilterSheet(
        options: options,
        selected: _selectedBranch,
      ),
    );
    // A null result means the sheet was dismissed without choosing; the sheet
    // returns the sentinel '' to mean "All branches".
    if (selected != null) {
      setState(() => _selectedBranch = selected.isEmpty ? null : selected);
    }
  }

  // Filtered requisitions grouped by branch (project), preserving first-seen
  // order. Each entry is one branch with all its pending requisition rows.
  Map<String, List<RequisitionItem>> get _grouped {
    final map = <String, List<RequisitionItem>>{};
    for (final r in _filtered) {
      map.putIfAbsent(r.project, () => []).add(r);
    }
    return map;
  }

  // Opens the branch's requisition details on a fresh screen with a
  // slide-from-right + fade transition.
  void _openBranch(String project, List<RequisitionItem> rows) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, _, _) =>
            BranchRequisitionDetailScreen(project: project, rows: rows),
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    final totalRequired = list.fold<int>(0, (sum, r) => sum + r.required);
    final groups = _grouped;
    final branchKeys = groups.keys.toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Requisition Summary',
          style: GoogleFonts.poppins(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 17,
          ),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          // Branch filter selector
          if (!_isLoading) _branchFilterBar(),
          // Stats summary header (from the API `stats` block)
          if (!_isLoading) _statsHeader(),
          // Pending summary banner (reflects the currently filtered list)
          if (!_isLoading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Text(
                    '${branchKeys.length} branch${branchKeys.length == 1 ? '' : 'es'} · ${list.length} pending',
                    style: AppTextStyles.labelMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Required: $totalRequired',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? _buildSkeleton()
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: list.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.5,
                                child: Center(
                                  child: Text(
                                    'No pending requisitions',
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: branchKeys.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final project = branchKeys[index];
                              return _buildBranchCard(
                                project,
                                groups[project]!,
                                index,
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  // Shimmering skeleton placeholder shown while the (multi-page) data loads —
  // mirrors the real layout: filter bar, stats tiles, banner and branch cards.
  Widget _buildSkeleton() {
    Widget box(double w, double h, {double r = 8}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(r),
          ),
        );

    Widget skeletonCard() => Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border(left: BorderSide(color: Colors.grey.shade200, width: 4)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    box(170, 12),
                    const SizedBox(height: 9),
                    box(95, 10),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              box(74, 22, r: 8),
            ],
          ),
        );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Filter bar placeholder
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: box(double.infinity, 42, r: 14),
        ),
        // Stats tiles placeholder
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
          child: Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: box(double.infinity, 52, r: 12)),
              ],
            ],
          ),
        ),
        // Pending banner placeholder
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [box(140, 12), const Spacer(), box(80, 20, r: 8)],
          ),
        ),
        // Branch card placeholders
        for (var i = 0; i < 7; i++)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: skeletonCard(),
          ),
      ],
    );

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: content,
    ).animate(onPlay: (c) => c.repeat()).shimmer(
          duration: 1100.ms,
          color: Colors.white,
        );
  }

  // Branch filter button: shows the selected branch (or 'All branches') and
  // opens the searchable picker. Includes a quick clear (×) when a branch is
  // selected.
  Widget _branchFilterBar() {
    final hasFilter = _selectedBranch != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _openBranchFilter,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: hasFilter
                  ? AppColors.primary.withOpacity(0.06)
                  : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasFilter ? AppColors.primary : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Iconsax.buildings,
                  size: 16,
                  color: hasFilter ? AppColors.primary : AppColors.textTertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedBranch ?? 'All branches',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontWeight:
                          hasFilter ? FontWeight.w600 : FontWeight.w500,
                      color: hasFilter
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
                if (hasFilter)
                  GestureDetector(
                    onTap: () => setState(() => _selectedBranch = null),
                    child: const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(Icons.close,
                          size: 16, color: AppColors.textSecondary),
                    ),
                  )
                else
                  const Icon(Icons.keyboard_arrow_down,
                      size: 20, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Stats driven by the API `stats` block, shown as compact chips on a single
  // line: Total, Completed, Closure and Pending counts.
  Widget _statsHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: _statChip('Total', _stats.totalRequisitions,
                AppColors.primary),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _statChip('Completed', _stats.completed, AppColors.success),
          ),
          const SizedBox(width: 6),
          Expanded(
            child:
                _statChip('Closure', _stats.closureCount, AppColors.warning),
          ),
          const SizedBox(width: 6),
          Expanded(
            child:
                _statChip('Pending', _stats.pendingBalance, AppColors.error),
          ),
        ],
      ),
    );
  }

  // A pill chip: colored dot + label + count, tinted by [color]. Content is
  // wrapped in a FittedBox so all four chips always fit on one line.
  Widget _statChip(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppTextStyles.labelSmall.copyWith(
                fontSize: 10.5,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '$value',
              style: AppTextStyles.labelSmall.copyWith(
                fontSize: 11.5,
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // One branch (project) card: a tappable summary showing the pending count +
  // total required. Tapping opens the branch's requisition detail screen.
  Widget _buildBranchCard(
    String project,
    List<RequisitionItem> rows,
    int index,
  ) {
    final branchRequired = rows.fold<int>(0, (s, r) => s + r.required);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: AppColors.primary, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openBranch(project, rows),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project,
                        style: AppTextStyles.titleSmall.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${rows.length} pending requisition'
                        '${rows.length == 1 ? '' : 's'}',
                        style: AppTextStyles.bodySmall.copyWith(
                          fontSize: 10.5,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Required: $branchRequired',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate(delay: (index * 40).ms).fadeIn(duration: 250.ms).slideY(
          begin: 0.05,
          end: 0,
          duration: 250.ms,
        );
  }
}

// Detail screen for a single branch (project): lists all of its pending
// requisitions. Reached from the Requisition Summary with a slide transition.
class BranchRequisitionDetailScreen extends StatelessWidget {
  final String project;
  final List<RequisitionItem> rows;

  const BranchRequisitionDetailScreen({
    super.key,
    required this.project,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final totalRequired = rows.fold<int>(0, (s, r) => s + r.required);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          project,
          style: GoogleFonts.poppins(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 17,
          ),
        ),
      ),
      body: Column(
        children: [
          // Summary banner
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Text(
                  '${rows.length} pending requisition'
                  '${rows.length == 1 ? '' : 's'}',
                  style: AppTextStyles.labelMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Required: $totalRequired',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _detailCard(rows[index], index),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailCard(RequisitionItem r, int index) {
    final replacement = r.requisitionType.toLowerCase() == 'replacement';
    final typeColor = replacement ? AppColors.warning : AppColors.success;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: typeColor, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.title,
                    style: AppTextStyles.titleSmall.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  // Department — only when the API provides it (null in the
                  // current response).
                  if (r.department.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(Iconsax.briefcase,
                            size: 12, color: AppColors.textTertiary),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            r.department,
                            style: AppTextStyles.bodySmall.copyWith(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (r.reqBy != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Iconsax.calendar,
                            size: 12, color: AppColors.textTertiary),
                        const SizedBox(width: 5),
                        Text(
                          'Req by: ${DateFormat('dd-MM-yyyy').format(r.reqBy!)}',
                          style: AppTextStyles.bodySmall.copyWith(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                  // Update remarks (e.g. the "replaced with…" note) when present.
                  if (r.remarks != null) ...[
                    const SizedBox(height: 5),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Iconsax.note_text,
                            size: 12, color: AppColors.textTertiary),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            r.remarks!,
                            style: AppTextStyles.bodySmall.copyWith(
                              fontSize: 10.5,
                              fontStyle: FontStyle.italic,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _countLine('Existing', r.existing, AppColors.textSecondary),
                const SizedBox(height: 3),
                _countLine('Required', r.required, AppColors.textSecondary),
                const SizedBox(height: 3),
                _countLine('Balance', r.balance, AppColors.error),
                const SizedBox(height: 5),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    r.requisitionType,
                    style: AppTextStyles.labelSmall.copyWith(
                      fontSize: 9.5,
                      color: typeColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate(delay: (index * 50).ms).fadeIn(duration: 280.ms).slideX(
          begin: 0.08,
          end: 0,
          duration: 280.ms,
          curve: Curves.easeOutCubic,
        );
  }

  // Small "Label: value" line used in the stacked counts column.
  Widget _countLine(String label, int value, Color color) {
    return Text(
      '$label: $value',
      style: AppTextStyles.labelSmall.copyWith(
        fontSize: 10.5,
        color: color,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

// Searchable branch picker shown as a modal bottom sheet. Returns the selected
// project name via Navigator.pop, or '' for "All branches" (null = dismissed).
class _BranchFilterSheet extends StatefulWidget {
  final List<({String project, int count})> options;
  final String? selected;

  const _BranchFilterSheet({required this.options, required this.selected});

  @override
  State<_BranchFilterSheet> createState() => _BranchFilterSheetState();
}

class _BranchFilterSheetState extends State<_BranchFilterSheet> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.options
        : widget.options
            .where((o) => o.project.toLowerCase().contains(q))
            .toList();
    final totalPending =
        widget.options.fold<int>(0, (s, o) => s + o.count);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (context, scrollController) {
          return Column(
            children: [
              // Grab handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    Text(
                      'Select Branch',
                      style: AppTextStyles.titleSmall.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${widget.options.length} branches',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _controller,
                  autofocus: false,
                  onChanged: (v) => setState(() => _query = v),
                  style: AppTextStyles.bodySmall,
                  decoration: InputDecoration(
                    hintText: 'Search branch…',
                    hintStyle: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                    ),
                    prefixIcon: const Icon(Iconsax.search_normal, size: 16),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    // "All branches" option (only when not searching)
                    if (q.isEmpty)
                      _branchTile(
                        label: 'All branches',
                        count: totalPending,
                        isSelected: widget.selected == null,
                        onTap: () => Navigator.pop(context, ''),
                      ),
                    if (filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: Text(
                            'No matching branch',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                      ),
                    for (final o in filtered)
                      _branchTile(
                        label: o.project,
                        count: o.count,
                        isSelected: widget.selected == o.project,
                        onTap: () => Navigator.pop(context, o.project),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _branchTile({
    required String label,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: isSelected ? AppColors.primary.withOpacity(0.06) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: isSelected ? AppColors.primary : AppColors.textTertiary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
