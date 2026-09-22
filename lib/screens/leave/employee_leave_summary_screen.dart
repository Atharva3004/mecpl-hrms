import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/leave_application_model.dart';
import '../../models/branch_model.dart';
import '../../models/user_model.dart';
import '../../models/employee_leaves_list_result.dart';
import '../../services/api_service.dart';
import '../../providers/auth_provider.dart';
import '../../models/role_model.dart';
import '../../widgets/common/custom_loader.dart';
import 'leave_screen.dart';

class EmployeeLeaveSummaryScreen extends StatefulWidget {
  const EmployeeLeaveSummaryScreen({super.key});

  @override
  State<EmployeeLeaveSummaryScreen> createState() =>
      _EmployeeLeaveSummaryScreenState();
}

class _EmployeeLeaveSummaryScreenState
    extends State<EmployeeLeaveSummaryScreen> {
  bool _isLoading = true;
  bool _isPaginating = false;
  List<LeaveApplication> _allLeaves = [];
  List<BranchModel> _preloadedBranches = [];
  List<UserModel> _preloadedEmployees = [];

  // Server-side pagination
  int _currentPage = 1;
  int _lastPage = 1;
  int _totalCount = 0;
  static const int _itemsPerPage = 20;

  // Server-side counts from API (fallback: compute from _allLeaves)
  Map<String, int> _counts = const {};

  // Filter state
  String _statusFilter = ''; // '', Pending, Approved, Rejected, Cancelled
  DateTime? _fromDate;
  DateTime? _toDate;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool resetPage = true}) async {
    // Show the full-screen spinner ONLY when there's nothing on screen yet
    // (first-ever load). Every other reload — filter change, search, page
    // jump, pull-to-refresh — uses the lightweight inline progress bar so
    // the cached list stays visible.
    final hasCachedData = _allLeaves.isNotEmpty;
    setState(() {
      if (resetPage) {
        _currentPage = 1;
      }
      if (hasCachedData) {
        _isPaginating = true;
      } else {
        _isLoading = true;
      }
    });
    try {
      final authProvider = context.read<AuthProvider>();
      final token = authProvider.token;
      if (token == null) return;

      final currentUser = authProvider.currentUser;

      // Branch scoping for onsite admins — send br_id server-side.
      String? brIdParam;
      if (currentUser != null &&
          currentUser.role == UserRole.onSiteAdmin &&
          currentUser.branchId != null) {
        brIdParam = currentUser.branchId.toString();
      }

      final df = DateFormat('yyyy-MM-dd');

      // Leaves list — depends on page + filters, must re-fetch every time.
      final leavesFuture = ApiService.getEmployeeLeavesList(
        token,
        page: _currentPage,
        perPage: _itemsPerPage,
        brId: brIdParam,
        status: _statusFilter,
        fromDate: _fromDate != null ? df.format(_fromDate!) : '',
        toDate: _toDate != null ? df.format(_toDate!) : '',
        search: _searchQuery,
      );

      // Reference data (branches + all employees) is essentially static —
      // only fetch on the very first load. Re-fetching on every filter /
      // page / search was the screen's main bottleneck (two extra API
      // round-trips and a potentially-large employee list parse on each
      // interaction).
      final needsReferenceData =
          _preloadedBranches.isEmpty || _preloadedEmployees.isEmpty;

      late final EmployeeLeavesListResult leavesResult;
      if (needsReferenceData) {
        final results = await Future.wait([
          leavesFuture,
          ApiService.getBranches(token),
          ApiService.getEmployees(token),
        ]);
        leavesResult = results[0] as EmployeeLeavesListResult;
        _preloadedBranches = results[1] as List<BranchModel>;
        final empResponse = results[2] as ApiResponse;
        if (empResponse.isSuccess && empResponse.data != null) {
          _preloadedEmployees = ApiService.parseEmployeesFromResponse(
            empResponse.data!,
          );
        }

        // Onsite-admin scoping for the employee dropdown + branches list used
        // by the "Apply Employee Leave" form. Leaves themselves are already
        // scoped server-side via br_id. Only needed on first load since the
        // lists are cached after that.
        if (currentUser != null &&
            currentUser.role == UserRole.onSiteAdmin &&
            currentUser.branchId != null) {
          final adminBranchId = currentUser.branchId!;
          _preloadedEmployees = _preloadedEmployees
              .where((e) => e.branchId == adminBranchId)
              .toList();
          _preloadedBranches = _preloadedBranches
              .where((b) => b.id == adminBranchId)
              .toList();
        }
      } else {
        // Reference data already cached on State — just hit the leaves API.
        leavesResult = await leavesFuture;
      }

      _allLeaves = leavesResult.leaves;
      _counts = leavesResult.counts;
      _currentPage = leavesResult.currentPage;
      _lastPage = leavesResult.lastPage;
      _totalCount = leavesResult.total;
    } catch (e) {
      debugPrint('Error loading approvals: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isPaginating = false;
        });
      }
    }
  }

  void _applyFilter(VoidCallback mutate) {
    mutate();
    _loadData(resetPage: true);
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: AppConstants.appStartDate,
      lastDate: DateTime(now.year + 1),
      initialDateRange: (_fromDate != null && _toDate != null)
          ? DateTimeRange(
              start: _fromDate!.isBefore(AppConstants.appStartDate)
                  ? AppConstants.appStartDate
                  : _fromDate!,
              end: _toDate!,
            )
          : null,
    );
    if (picked == null) return;
    _applyFilter(() {
      _fromDate = picked.start;
      _toDate = picked.end;
    });
  }

  void _clearDateRange() {
    _applyFilter(() {
      _fromDate = null;
      _toDate = null;
    });
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd MMM').format(date);
  }

  int _countFromApi(String key) =>
      _counts[key.toLowerCase()] ??
      _allLeaves
          .where((l) => l.status.toLowerCase() == key.toLowerCase())
          .length;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final pendingCount = _countFromApi('pending');
    final approvedCount = _countFromApi('approved');
    final rejectedCount = _countFromApi('rejected');
    final totalCount = _counts['total'] ?? _totalCount;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        title: Text(
          'Leave Summary',
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
          : RefreshIndicator(
              onRefresh: () => _loadData(resetPage: false),
              child: Column(
                children: [
                  _buildStatCards(
                    isDark,
                    totalCount,
                    pendingCount,
                    approvedCount,
                    rejectedCount,
                  ),
                  _buildFilterBar(isDark),
                  // Thin progress bar — only visible while a partial reload
                  // is in flight (filter / search / page change). Sits above
                  // the list so the cached items stay fully visible and the
                  // screen never goes blank.
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    child: _isPaginating
                        ? LinearProgressIndicator(
                            minHeight: 2,
                            backgroundColor:
                                AppColors.primary.withOpacity(0.1),
                            valueColor:
                                AlwaysStoppedAnimation(AppColors.primary),
                          )
                        : const SizedBox(height: 0),
                  ),
                  Expanded(
                    child: _buildList(_allLeaves, isDark: isDark),
                  ),
                  _buildPaginationControls(isDark),
                  if (context.watch<AuthProvider>().currentUser?.role ==
                      UserRole.onSiteAdmin)
                    _buildApplyButton(isDark),
                ],
              ),
            ),
    );
  }

  Widget _buildFilterBar(bool isDark) {
    final hasDateRange = _fromDate != null && _toDate != null;
    final statuses = ['', 'Pending', 'Approved', 'Rejected', 'Cancelled'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Search + date range
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onSubmitted: (v) =>
                      _applyFilter(() => _searchQuery = v.trim()),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search employee / reason',
                    hintStyle: GoogleFonts.inter(fontSize: 12),
                    prefixIcon:
                        const Icon(Iconsax.search_normal, size: 18),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              _applyFilter(() => _searchQuery = '');
                            },
                          ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  style: GoogleFonts.inter(fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _pickDateRange,
                icon: const Icon(Iconsax.calendar_1, size: 16),
                label: Text(
                  hasDateRange
                      ? '${DateFormat('dd MMM').format(_fromDate!)} – ${DateFormat('dd MMM').format(_toDate!)}'
                      : 'Dates',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              if (hasDateRange)
                IconButton(
                  tooltip: 'Clear dates',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: _clearDateRange,
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Status chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: statuses.map((s) {
                final label = s.isEmpty ? 'All' : s;
                final selected = _statusFilter == s;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? Colors.white
                            : (isDark ? Colors.white70 : AppColors.textPrimary),
                      ),
                    ),
                    selected: selected,
                    onSelected: (_) =>
                        _applyFilter(() => _statusFilter = s),
                    selectedColor: AppColors.primary,
                    backgroundColor:
                        isDark ? AppColors.darkSurface : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: selected
                            ? AppColors.primary
                            : (isDark
                                ? AppColors.darkBorder
                                : Colors.grey.shade300),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCards(
    bool isDark,
    int total,
    int pending,
    int approved,
    int rejected,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          Expanded(child: _buildStatCard('Total', total, Colors.blue, isDark)),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              'Pending',
              pending,
              AppColors.warning,
              isDark,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              'Approved',
              approved,
              AppColors.success,
              isDark,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              'Rejected',
              rejected,
              AppColors.error,
              isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, int count, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
        ],
        border: Border.all(
          color: isDark ? AppColors.darkBorder : Colors.grey[200]!,
        ),
      ),
      child: Column(
        children: [
          Text(
            count.toString(),
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : AppColors.textSecondary,
              height: 1.2,
            ),
          ),
        ],
      ),
    ).animate().fadeIn().scale(delay: 100.ms);
  }

  Widget _buildApplyButton(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkBorder : Colors.grey[200]!,
          ),
        ),
      ),
      child: Center(
        // child: SizedBox(
        // height: 40, // Reduced height
        child: ElevatedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LeaveApplicationForm(
                  leaveTypes: const [],
                  isApplyingForOther: true,
                  preloadedBranches: _preloadedBranches,
                  preloadedEmployees: _preloadedEmployees,
                ),
              ),
            ).then((_) {
              _loadData();
            });
          },
          icon: const Icon(Iconsax.add, size: 18),
          label: Text(
            'Apply Employee Leave',
            style: GoogleFonts.poppins(
              fontSize: 13, // Reduced font size
              fontWeight: FontWeight.w600,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 0,
          ),
        ),
        // ),
      ),
    );
  }

  Widget _buildList(List<LeaveApplication> leaves, {required bool isDark}) {
    if (leaves.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Iconsax.document_text,
              size: 64,
              color: AppColors.textTertiary.withOpacity(0.8),
            ),
            const SizedBox(height: 16),
            Text(
              'No leave records found',
              style: AppTextStyles.titleMedium.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : Colors.grey.shade200,
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTableHeader(isDark),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: List.generate(
                      leaves.length,
                      (index) =>
                          _buildTableRow(leaves[index], isDark, index),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaginationControls(bool isDark) {
    if (_lastPage <= 1 && _totalCount == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildPaginationButton(
            icon: Icons.chevron_left,
            label: 'Previous',
            isEnabled: _currentPage > 1,
            onPressed: () {
              _currentPage--;
              _loadData(resetPage: false);
            },
            isDark: isDark,
          ),
          Text(
            'Page $_currentPage of $_lastPage  ($_totalCount total)',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : AppColors.textSecondary,
            ),
          ),
          _buildPaginationButton(
            icon: Icons.chevron_right,
            label: 'Next',
            isEnabled: _currentPage < _lastPage,
            onPressed: () {
              _currentPage++;
              _loadData(resetPage: false);
            },
            isDark: isDark,
            isRightIcon: true,
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationButton({
    required IconData icon,
    required String label,
    required bool isEnabled,
    required VoidCallback onPressed,
    required bool isDark,
    bool isRightIcon = false,
  }) {
    return TextButton(
      onPressed: isEnabled ? onPressed : null,
      style: TextButton.styleFrom(
        foregroundColor: isDark ? Colors.white : AppColors.primary,
        disabledForegroundColor: isDark
            ? Colors.white24
            : AppColors.textTertiary,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Row(
        children: [
          if (!isRightIcon) Icon(icon, size: 18),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          if (isRightIcon) Icon(icon, size: 18),
        ],
      ),
    );
  }

  Widget _buildTableHeader(bool isDark) {
    return Container(
      color: Colors.blueAccent.shade400,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeaderCell('Name', 140, isExpanded: true),
          _buildHeaderCell('Dates', 120),
          _buildHeaderCell('Action', 60),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(
    String text,
    double width, {
    bool isExpanded = false,
  }) {
    final cell = SizedBox(
      width: width,
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w600,
          color: Colors.white,
          fontSize: 11,
          letterSpacing: 0.5,
        ),
      ),
    );
    return isExpanded ? Expanded(child: cell) : cell;
  }

  Widget _buildTableRow(LeaveApplication leave, bool isDark, int index) {
    Color statusColor;
    switch (leave.status.toLowerCase()) {
      case 'approved':
        statusColor = const Color(0xFF10B981);
        break;
      case 'rejected':
        statusColor = const Color(0xFFEF4444);
        break;
      case 'pending':
        statusColor = const Color(0xFFF59E0B);
        break;
      default:
        statusColor = AppColors.textSecondary;
    }

    final Color rowBgColor = isDark ? Colors.transparent : Colors.white;

    return Container(
      color: rowBgColor,
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    // Name & ID
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            leave.employee?.fullName ?? 'Employee',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white
                                  : AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '#${leave.employee?.employeeId ?? leave.empId}',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w400,
                              color: isDark
                                  ? Colors.white54
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Dates
                    SizedBox(
                      width: 110,
                      child: Text(
                        '${_formatDate(leave.fromDate)} - ${_formatDate(leave.toDate)}',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? Colors.white54
                              : const Color(0xFF64748B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Action
                    SizedBox(
                      width: 60,
                      child: IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Color(0xFFEF4444),
                          size: 20,
                        ),
                        onPressed: () {
                          final currentUser = context
                              .read<AuthProvider>()
                              .currentUser;
                          if (currentUser?.role == UserRole.onSiteAdmin) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'You do not have access to cancel this leave.',
                                ),
                                backgroundColor: AppColors.error,
                                duration: Duration(seconds: 4),
                              ),
                            );
                            return;
                          }
                          _showDeleteConfirmation(leave);
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ),
                  ],
                ),
              ),
              if (index < _allLeaves.length - 1)
                Divider(
                  height: 1,
                  indent: 12,
                  color: isDark ? AppColors.darkBorder : Colors.grey.shade100,
                ),
            ],
          ),
          // Straight Vertical Ribbon
          Positioned(
            left: 0,
            top: 4,
            bottom: 4,
            child: Container(
              width: 5,
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(4),
                  bottomRight: Radius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(LeaveApplication leave) {
    bool isDeleting = false;
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Delete Leave'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Are you sure you want to cancel this leave application for ${leave.employee?.fullName ?? 'this employee'}?',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Reason for cancellation (Optional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isDeleting ? null : () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              ElevatedButton(
                onPressed: isDeleting
                    ? null
                    : () async {
                        setState(() => isDeleting = true);

                        final authProvider = context.read<AuthProvider>();
                        final token = authProvider.token;

                        if (token == null) {
                          setState(() => isDeleting = false);
                          return;
                        }

                        final response = await ApiService.deleteEmployeeLeave(
                          token: token,
                          leaveId: leave.id.toString(),
                          deleteReason: reasonController.text.isEmpty
                              ? 'Deleted by admin'
                              : reasonController.text,
                        );

                        if (mounted) {
                          Navigator.pop(dialogContext); // Close dialog

                          if (response.isSuccess) {
                            final Map<String, dynamic> data =
                                (response.data is Map<String, dynamic>)
                                    ? response.data as Map<String, dynamic>
                                    : <String, dynamic>{};
                            String snackMsg = 'Leave deleted successfully.';
                            final apiMsg = data['message']?.toString();
                            if (apiMsg != null && apiMsg.isNotEmpty) {
                              snackMsg = apiMsg;
                            }
                            if (data['balance_restored'] == true) {
                              final days = data['restored_days'];
                              snackMsg +=
                                  ' Balance restored${days != null ? ' ($days day${days == 1 ? '' : 's'})' : ''}.';
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(snackMsg),
                                backgroundColor: AppColors.success,
                              ),
                            );
                            _loadData(); // Refresh list
                          } else {
                            // Show the explicit error reason (e.g., "You do not have access...")
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  response.error ?? 'Unknown error occurred',
                                ),
                                backgroundColor: AppColors.error,
                                duration: const Duration(seconds: 4),
                              ),
                            );
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                ),
                child: isDeleting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Text(
                        'Delete',
                        style: TextStyle(color: Colors.white),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
