import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../models/regularization_request_model.dart';
import '../../services/api_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';

class RegularizationApprovalScreen extends StatefulWidget {
  const RegularizationApprovalScreen({super.key});

  @override
  State<RegularizationApprovalScreen> createState() =>
      _RegularizationApprovalScreenState();
}

class _RegularizationApprovalScreenState
    extends State<RegularizationApprovalScreen> {
  bool _isLoading = true;
  List<RegularizationRequest> _pendingRequests = [];
  int _approvedTodayCount = 0;
  final Set<int> _expandedIndices = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final authProvider = context.read<AuthProvider>();
      final token = authProvider.token;
      if (token != null) {
        final response = await ApiService.getRegularizationApprovals(token);
        if (response.isSuccess && response.data != null) {
          final data = response.data!;
          final bool hasStatusKey = data.containsKey('status');
          final bool apiStatus = hasStatusKey ? data['status'] == true : true;

          if (apiStatus) {
            final dynamic rawData =
                data['data'] ??
                data['pending_requests'] ??
                data['pending'] ??
                [];

            if (rawData is List && rawData.isNotEmpty) {
              _pendingRequests = rawData
                  .map((json) {
                    try {
                      return RegularizationRequest.fromJson(
                        json as Map<String, dynamic>,
                      );
                    } catch (e) {
                      debugPrint('⚠️ Error parsing regularization request: $e');
                      return null;
                    }
                  })
                  .whereType<RegularizationRequest>()
                  .toList();
            } else {
              _pendingRequests = [];
            }

            _approvedTodayCount =
                data['approved_today'] ?? data['approved_count'] ?? 0;
          } else {
            _pendingRequests = [];
          }
        } else {
          _pendingRequests = [];
        }
      }
    } catch (e) {
      debugPrint('Error loading regularization approvals: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateStatus(
    RegularizationRequest request,
    String status,
    String remarks,
  ) async {
    try {
      final authProvider = context.read<AuthProvider>();
      final token = authProvider.token;
      if (token == null) return;

      // Optimistic update
      setState(() {
        _pendingRequests.removeWhere((r) => r.id == request.id);
        if (status.toLowerCase() == 'approved') {
          _approvedTodayCount++;
        }
      });

      final apiResponse = await ApiService.updateRegularizationStatus(
        token: token,
        requestId: request.id.toString(),
        status: status,
        remarks: remarks,
      );

      if (!apiResponse.isSuccess) {
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(apiResponse.error ?? 'Failed to update status'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      } else {
        // Drop the in-app notification for *this specific* regularization so
        // it disappears from the bell list. Two-step:
        //   1) Try the foreign-key path — works once the backend populates
        //      `regularization_id` on the notification row.
        //   2) Fallback heuristic on message text — the body the backend
        //      sends today is
        //      "{employee_name} requested attendance correction for {date}"
        //      (see docs/laravel-notifications-extend-types.md §4b). We
        //      match on employee name + the raw request date scoped to
        //      `regularization_submitted` so we don't remove unrelated rows.
        //   Notifications for other employees / other dates stay intact.
        if (mounted) {
          final notif = context.read<NotificationProvider>();
          notif.removeForRegularization(request.id);
          notif.removeWhere((n) {
            if (n.type != 'regularization_submitted') return false;
            if (n.regularizationId != null) return false; // already handled
            final empName = request.employeeName.trim();
            if (empName.isEmpty) return false;
            if (!n.message.contains(empName)) return false;
            return request.date.isNotEmpty &&
                n.message.contains(request.date);
          });
        }
        if (mounted) {
          final msg = (apiResponse.data is Map
                  ? apiResponse.data!['message']?.toString()
                  : null) ??
              'Regularization $status successfully';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: status == 'Approved'
                  ? AppColors.success
                  : AppColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error updating regularization status: $e');
    }
  }

  /// Unique employee count
  int get _uniqueEmployeeCount {
    final codes = _pendingRequests.map((r) => r.employeeCode).toSet();
    return codes.length;
  }

  @override
  Widget build(BuildContext context) {
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
          'Regularization Approvals',
          style: GoogleFonts.poppins(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 17,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF3F51B5)),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              color: const Color(0xFF3F51B5),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  const SizedBox(height: 8),

                  // Summary Cards
                  _buildSummaryCards(),
                  const SizedBox(height: 20),

                  // Pending Requests Section
                  _buildPendingRequestsSection(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  // ─── Summary Chips ─────────────────────────────────────────────────

  Widget _buildSummaryCards() {
    return Row(
      children: [
        _buildStatChip(
          icon: Iconsax.clipboard_text,
          iconColor: const Color(0xFF3F51B5),
          iconBgColor: const Color(0xFFE8EAF6),
          label: 'Total Pending',
          value: _pendingRequests.length.toString(),
        ),
        const SizedBox(width: 8),
        _buildStatChip(
          icon: Iconsax.tick_circle,
          iconColor: const Color(0xFF4CAF50),
          iconBgColor: const Color(0xFFE8F5E9),
          label: 'Approved Today',
          value: _approvedTodayCount > 0 ? _approvedTodayCount.toString() : '—',
        ),
        const SizedBox(width: 8),
        _buildStatChip(
          icon: Iconsax.people,
          iconColor: const Color(0xFFFFA000),
          iconBgColor: const Color(0xFFFFF8E1),
          label: 'Employees',
          value: _uniqueEmployeeCount.toString(),
        ),
      ],
    ).animate().fadeIn(duration: 500.ms).slideY(begin: -0.1, end: 0);
  }

  Widget _buildStatChip({
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: iconColor, size: 14),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.poppins(
                      fontSize: 8,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    value,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
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

  // ─── Pending Requests Section (Plain Table) ────────────────────────

  Widget _buildPendingRequestsSection() {
    return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Header
            Row(
              children: [
                Icon(Iconsax.clock, size: 16, color: const Color(0xFF1565C0)),
                const SizedBox(width: 8),
                Text(
                  'Pending Requests',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Table Header
            _buildTableHeader(),

            // Divider under header
            Divider(color: Colors.grey.shade300, height: 1),

            // Content
            if (_pendingRequests.isEmpty)
              _buildEmptyState()
            else
              ..._pendingRequests.asMap().entries.map((entry) {
                return _buildRequestCard(entry.value, entry.key);
              }),
          ],
        )
        .animate()
        .fadeIn(delay: 200.ms, duration: 500.ms)
        .slideY(begin: 0.1, end: 0);
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      color: const Color(0xFFF5F6FA),
      child: Row(
        children: [
          _headerCell('EMPLOYEE', flex: 5),
          _headerCell('DATE', flex: 3),
          _headerCell('STATUS', flex: 2),
          _headerCell('ACTIONS', flex: 3),
        ],
      ),
    );
  }

  Widget _headerCell(String text, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 8,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade500,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                size: 48,
                color: Color(0xFF4CAF50),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'All Caught Up!',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'No pending regularization requests for your review.',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Request Card ──────────────────────────────────────────────────

  Widget _buildRequestCard(RegularizationRequest request, int index) {
    final isExpanded = _expandedIndices.contains(index);

    // Status badge colors
    Color statusColor;
    Color statusBg;
    switch (request.originalStatus.toUpperCase()) {
      case 'A':
      case 'ABSENT':
        statusColor = const Color(0xFFC62828);
        statusBg = const Color(0xFFFFEBEE);
        break;
      case 'HD':
      case 'HALF DAY':
        statusColor = const Color(0xFFE65100);
        statusBg = const Color(0xFFFFF3E0);
        break;
      case 'L/P':
      case 'P/L':
        statusColor = const Color(0xFF00796B);
        statusBg = const Color(0xFFE0F2F1);
        break;
      default:
        statusColor = const Color(0xFFE65100);
        statusBg = const Color(0xFFFFF3E0);
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
          ),
          child: Row(
            children: [
              // Tappable toggle zone: Employee + Date + Status (flex 10)
              Expanded(
                flex: 10,
                child: InkWell(
                  onTap: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedIndices.remove(index);
                      } else {
                        _expandedIndices.add(index);
                      }
                    });
                  },
                  child: Row(
                    children: [
                      // Employee (with chevron)
                      Expanded(
                        flex: 5,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            AnimatedRotation(
                              turns: isExpanded ? 0.5 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: Icon(
                                Icons.keyboard_arrow_down,
                                size: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    request.employeeName.isNotEmpty
                                        ? request.employeeName
                                        : 'Unknown',
                                    style: GoogleFonts.poppins(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (request.employeeCode.isNotEmpty)
                                    Text(
                                      '#${request.employeeCode}',
                                      style: GoogleFonts.poppins(
                                        fontSize: 8,
                                        color: Colors.grey.shade500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Date + Day
                      Expanded(
                        flex: 3,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              request.displayDate.isNotEmpty
                                  ? request.displayDate
                                  : '—',
                              style: GoogleFonts.poppins(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            // if (request.day.isNotEmpty)
                            //   Text(
                            //     request.day,
                            //     style: GoogleFonts.poppins(
                            //       fontSize: 8,
                            //       color: Colors.grey.shade500,
                            //     ),
                            //     maxLines: 1,
                            //     overflow: TextOverflow.ellipsis,
                            //   ),
                          ],
                        ),
                      ),

                      // Original Status
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            request.originalStatus.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Actions (outside InkWell so taps never toggle expansion)
              Expanded(
                flex: 3,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _buildActionIcon(
                      icon: Iconsax.close_circle,
                      color: AppColors.error,
                      onTap: () => _showConfirmationDialog(request, 'Rejected'),
                    ),
                    const SizedBox(width: 6),
                    _buildActionIcon(
                      icon: Iconsax.tick_circle,
                      color: AppColors.success,
                      isPrimary: true,
                      onTap: () => _showConfirmationDialog(request, 'Approved'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Expanded details
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: isExpanded
              ? _buildExpandedDetails(request)
              : const SizedBox(width: double.infinity),
        ),
      ],
    ).animate().fadeIn().slideY(begin: 0.05, end: 0);
  }

  Widget _buildExpandedDetails(RegularizationRequest request) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FC),
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _buildDetailItem('DAY', request.day)),
                Expanded(
                  child: _buildDetailItem(
                    'APPLIED ON',
                    request.displayAppliedOn,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildDetailItem(
                    request.isInRegularized ? 'REGULARIZED IN' : 'IN TIME',
                    request.requestedInTime.isNotEmpty
                        ? request.requestedInTime
                        : 'NA',
                    highlight: request.isInRegularized,
                  ),
                ),
                Expanded(
                  child: _buildDetailItem(
                    request.isOutRegularized ? 'REGULARIZED OUT' : 'OUT TIME',
                    request.requestedOutTime.isNotEmpty
                        ? request.requestedOutTime
                        : 'NA',
                    highlight: request.isOutRegularized,
                  ),
                ),
              ],
            ),
            if (request.comments.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildDetailItem('COMMENTS', request.comments),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, {bool highlight = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: highlight ? const Color(0xFFE08A00) : Colors.grey.shade500,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 2),
        highlight
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFC77700),
                  ),
                ),
              )
            : Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
      ],
    );
  }

  Widget _buildActionIcon({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: isPrimary ? color.withOpacity(0.1) : Colors.transparent,
          border: Border.all(color: color.withOpacity(0.5), width: 1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 14, color: color),
      ),
    );
  }

  // ─── Confirmation Dialog ───────────────────────────────────────────

  Future<void> _showConfirmationDialog(
    RegularizationRequest request,
    String status,
  ) async {
    final isApproved = status == 'Approved';
    final actionName = isApproved ? 'Approval' : 'Rejection';
    final verbName = isApproved ? 'approve' : 'reject';
    final color = isApproved ? AppColors.success : AppColors.error;
    final remarksController = TextEditingController(
      text: isApproved ? 'Approved' : '',
    );

    return showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isRemarksEmpty = remarksController.text.trim().isEmpty;
          final canConfirm = isApproved || !isRemarksEmpty;

          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              'Confirm $actionName',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.85,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Text.rich(
                    TextSpan(
                      style: GoogleFonts.poppins(fontSize: 13),
                      children: [
                        TextSpan(
                          text:
                              'Are you sure you want to $verbName the regularization request for ',
                        ),
                        TextSpan(
                          text: request.employeeName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(text: ' on ${request.displayDate}?'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Request details summary
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDialogDetail(
                          'Original Status',
                          request.originalStatus.toUpperCase(),
                        ),
                        const SizedBox(height: 4),
                        _buildDialogDetail(
                          'Requested Times',
                          request.requestedTimesDisplay,
                        ),
                        if (request.reasonType.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          _buildDialogDetail('Reason', request.reasonType),
                        ],
                      ],
                    ),
                  ),
                  // Remarks field for rejection
                  if (!isApproved) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: remarksController,
                      maxLines: 3,
                      style: GoogleFonts.poppins(fontSize: 13),
                      onChanged: (value) {
                        setDialogState(() {});
                      },
                      decoration: InputDecoration(
                        labelText: 'Remarks',
                        hintText: 'Enter reason for rejection...',
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
                          'Remarks are required for rejection',
                          style: GoogleFonts.poppins(
                            color: AppColors.error,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ],
                ),
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            actions: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.poppins(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: ElevatedButton(
                      onPressed: canConfirm
                          ? () {
                              Navigator.pop(context);
                              _updateStatus(
                                request,
                                status,
                                isApproved
                                    ? 'Approved'
                                    : remarksController.text.trim().isNotEmpty
                                    ? remarksController.text.trim()
                                    : 'Rejected',
                              );
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
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
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

  Widget _buildDialogDetail(String label, String value) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade600),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}
