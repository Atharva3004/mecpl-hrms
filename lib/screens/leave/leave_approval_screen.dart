import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/leave_application_model.dart';
import '../../models/leave_info_model.dart';
import '../../services/api_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../widgets/common/custom_loader.dart';

class LeaveApprovalScreen extends StatefulWidget {
  const LeaveApprovalScreen({super.key});

  @override
  State<LeaveApprovalScreen> createState() => _LeaveApprovalScreenState();
}

class _LeaveApprovalScreenState extends State<LeaveApprovalScreen> {
  bool _isLoading = true;
  List<LeaveApplication> _allLeaves = [];
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
        final leaves = await ApiService.getLeaveApprovals(token);
        // Show only Pending leaves
        _allLeaves = leaves
            .where((l) => l.status.toLowerCase() == 'pending')
            .toList();
        // Sort by date (newest first)
        _allLeaves.sort((a, b) => b.fromDate.compareTo(a.fromDate));
      }
    } catch (e) {
      debugPrint('Error loading approvals: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateStatus(
    LeaveApplication leave,
    String status,
    String remarks,
  ) async {
    try {
      final authProvider = context.read<AuthProvider>();
      final token = authProvider.token;
      if (token == null) return;

      // Optimistic update
      setState(() {
        _allLeaves.removeWhere((l) => l.id == leave.id);
      });

      final success = await ApiService.updateLeaveStatus(
        token: token,
        leaveId: leave.id.toString(),
        status: status,
        remarks: remarks,
      );

      if (!success) {
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to update status')),
          );
        }
      } else {
        // Action complete — drop any in-app notification that was tracking
        // this leave application so the notifications screen stays in sync.
        if (mounted) {
          context.read<NotificationProvider>().removeForLeaveApplication(
            leave.id,
          );
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Leave $status successfully'),
              backgroundColor: status == 'Approved'
                  ? AppColors.success
                  : AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error updating status: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        title: Text(
          'Leave Approvals',
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
              onRefresh: _loadData,
              child: _buildList(_allLeaves, isDark: isDark),
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
              Iconsax.tick_circle,
              size: 64,
              color: AppColors.textTertiary.withOpacity(0.8),
            ),
            const SizedBox(height: 16),
            Text(
              'No pending leave requests',
              style: AppTextStyles.titleMedium.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: leaves.length,
      itemBuilder: (context, index) {
        final leave = leaves[index];
        final isPending = leave.status.toLowerCase() == 'pending';
        return _buildLeaveCard(leave, isPending, isDark);
      },
    );
  }

  Widget _buildLeaveCard(LeaveApplication leave, bool isPending, bool isDark) {
    // const orangeTheme = Color(0xFFF97316);
    const orangeTheme = Color.fromARGB(255, 100, 112, 243);
    const darkBlue = Color(0xFF1E293B);
    final isExpanded = _expandedIndices.contains(leave.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.19),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
        ],
        border: Border.all(
          color: isDark ? AppColors.darkBorder : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header - Very Slim
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(
              color: orangeTheme,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(9),
                topRight: Radius.circular(9),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  leave.leaveType.leaveName,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '#${leave.employee?.employeeId ?? leave.empId}',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),

          // Body Content - Clickable to expand
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedIndices.remove(leave.id);
                } else {
                  _expandedIndices.add(leave.id);
                }
              });
            },
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(10),
              bottomRight: Radius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Name | FromDate - ToDate AND Action Icons
                  Row(
                    children: [
                      // Basic Info (Always Visible)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              leave.employee?.fullName ?? 'Employee',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isDark ? Colors.white : darkBlue,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${_formatDate(leave.fromDate)} - ${_formatDate(leave.toDate)}',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? Colors.white70
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Action Icons (Always Visible)
                      if (isPending) ...[
                        const SizedBox(width: 8),
                        _buildActionButton(
                          icon: Iconsax.close_circle,
                          color: AppColors.error,
                          onPressed: () =>
                              _showConfirmationDialog(leave, 'Rejected'),
                        ),
                        const SizedBox(width: 8),
                        _buildActionButton(
                          icon: Iconsax.tick_circle,
                          color: AppColors.success,
                          isPrimary: true,
                          onPressed: () =>
                              _showConfirmationDialog(leave, 'Approved'),
                        ),
                      ] else ...[
                        const SizedBox(width: 8),
                        _buildStatusChip(leave.status),
                      ],

                      // Expansion Arrow
                      const SizedBox(width: 12),
                      AnimatedRotation(
                        duration: const Duration(milliseconds: 200),
                        turns: isExpanded ? 0.5 : 0,
                        child: Icon(
                          Icons.keyboard_arrow_down,
                          size: 20,
                          color: isDark ? Colors.white54 : Colors.grey[400],
                        ),
                      ),
                    ],
                  ),

                  // Collapsible Rows (Row 2 and Row 3)
                  if (isExpanded) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),

                    // Row 2: Days | Duration (Full/Half)
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.success.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${leave.netLeaveDays.formatDecimal()} Days',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.success,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text('|', style: TextStyle(color: Colors.grey[300])),
                        const SizedBox(width: 12),
                        Text(
                          leave.halfDay.startsWith('Full')
                              ? 'Full Day'
                              : 'Half Day',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? Colors.white70
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Row 3: Reason
                    Text(
                      'Reason: ${leave.reason.isNotEmpty ? leave.reason : "No reason provided"}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: isDark
                            ? Colors.white.withOpacity(0.7)
                            : darkBlue.withOpacity(0.7),
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Row 4: Links
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        InkWell(
                          onTap: () => _showLeaveHistoryPopup(context, leave),
                          child: Text(
                            'Previous History',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                              // decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        InkWell(
                          onTap: () => _showOthersOnLeavePopup(context, leave),
                          child: Text(
                            'Employees on leave',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                              //  color: Colors.blue.withOpacity(0.5),
                              // decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.1, end: 0);
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    bool isPrimary = false,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isPrimary ? color.withOpacity(0.1) : Colors.transparent,
          border: Border.all(color: color.withOpacity(0.5), width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 20, color: color),
      ),
    );
  }

  Future<void> _showConfirmationDialog(
    LeaveApplication leave,
    String status,
  ) async {
    final isApproved = status == 'Approved';
    final actionName = isApproved ? 'Approval' : 'Rejection';
    final verbName = isApproved ? 'approve' : 'reject';
    final color = isApproved ? AppColors.success : AppColors.error;
    final remarksController = TextEditingController(
      text: isApproved ? 'Approved by Manager' : '',
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
              style: AppTextStyles.titleLarge.copyWith(color: color),
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
                              'Are you sure you want to $verbName this leave request for ',
                        ),
                        TextSpan(
                          text: leave.employee?.fullName ?? 'this employee',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const TextSpan(text: '?'),
                      ],
                    ),
                  ),
                  // Show remarks field only for rejection
                  if (!isApproved) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: remarksController,
                      maxLines: 3,
                      style: AppTextStyles.bodyMedium,
                      onChanged: (value) {
                        setDialogState(() {});
                      },
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
                          'Remarks are required for rejection',
                          style: TextStyle(
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
                              Navigator.pop(context);
                              _updateStatus(
                                leave,
                                status,
                                isApproved
                                    ? 'Approved by Manager'
                                    : remarksController.text.trim().isNotEmpty
                                    ? remarksController.text.trim()
                                    : 'Rejected by Manager',
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

  Widget _buildStatusChip(String status) {
    Color color;
    IconData? icon;
    bool showText = true;

    switch (status.toLowerCase()) {
      case 'approved':
        color = AppColors.success;
        icon = Iconsax.tick_circle;
        break;
      case 'rejected':
        color = AppColors.error;
        icon = Iconsax.close_circle;
        break;
      case 'pending':
        color = AppColors.warning;
        icon = Iconsax.clock;
        showText = false; // Show only symbol for pending
        break;
      default:
        color = AppColors.textSecondary;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: showText ? 6 : 4, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: showText
          ? Text(
              status,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            )
          : Icon(icon, color: color, size: 14),
    );
  }

  Future<void> _showLeaveHistoryPopup(
    BuildContext context,
    LeaveApplication currentLeave,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Leave History',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: isDark ? Colors.white70 : Colors.grey,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 10),
              FutureBuilder<LeaveInfoResponse?>(
                future: _fetchLeaveInfo(currentLeave),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Expanded(
                      child: Center(child: CustomLoader(size: 60)),
                    );
                  }

                  if (snapshot.hasError) {
                    debugPrint('Leave history popup error: ${snapshot.error}');
                    return Expanded(
                      child: Center(
                        child: Text(
                          'Failed to load history: ${snapshot.error}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  if (!snapshot.hasData) {
                    return const Expanded(
                      child: Center(child: Text('Failed to load history')),
                    );
                  }

                  final info = snapshot.data!;
                  final history = info.allHistory;
                  if (history.isEmpty) {
                    return const Expanded(
                      child: Center(child: Text('No previous history found')),
                    );
                  }

                  return Expanded(
                    child: ListView.builder(
                      itemCount: history.length,
                      itemBuilder: (context, index) {
                        final h = history[index];
                        return _buildHistoryItem(h, isDark);
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<LeaveInfoResponse?> _fetchLeaveInfo(LeaveApplication leave) async {
    try {
      final authProvider = context.read<AuthProvider>();
      final token = authProvider.token;
      if (token == null) return null;

      return await ApiService.getLeaveInfo(
        token: token,
        leaveId: leave.id.toString(),
      );
    } catch (e) {
      debugPrint('Error fetching leave info: $e');
      return null;
    }
  }

  Widget _buildHistoryItem(LeaveHistoryItem h, bool isDark) {
    Color statusColor;
    switch (h.status.toLowerCase()) {
      case 'approved':
        statusColor = AppColors.success;
        break;
      case 'rejected':
        statusColor = AppColors.error;
        break;
      default:
        statusColor = AppColors.warning;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBackground : Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                h.type,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  h.status,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${h.fromDate} - ${h.toDate} (${h.netLeaveDays.formatDecimal()} Days)',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: isDark ? Colors.white70 : AppColors.textSecondary,
            ),
          ),
          if (h.reason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Reason: ${h.reason}',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showOthersOnLeavePopup(
    BuildContext context,
    LeaveApplication leave,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Others on Leave',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.white
                                : AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Date: ${DateFormat('dd MMM yyyy').format(leave.fromDate)}',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: isDark
                                ? Colors.white70
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: isDark ? Colors.white70 : Colors.grey,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: Text(
                        'NAME',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Colors.white60
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'STATUS',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Colors.white60
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: FutureBuilder<LeaveInfoResponse?>(
                  future: _fetchLeaveInfo(leave),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CustomLoader(size: 60));
                    }

                    if (snapshot.hasError || !snapshot.hasData) {
                      return const Center(
                        child: Text('Failed to load details'),
                      );
                    }

                    final othersOnLeave = snapshot.data!.othersOnLeave;

                    if (othersOnLeave.isEmpty) {
                      return const Center(
                        child: Text('No others on leave on this date'),
                      );
                    }

                    return ListView.builder(
                      itemCount: othersOnLeave.length,
                      itemBuilder: (context, index) {
                        final item = othersOnLeave[index];
                        return _buildTeamMemberItem(item, isDark);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTeamMemberItem(dynamic user, bool isDark) {
    String name = 'Employee';
    String status = 'A';

    if (user is Map) {
      name =
          (user['fullName'] ??
                  user['name'] ??
                  user['emp_name'] ??
                  user['emp_name '] ?? // Handle trailing space if any
                  'Employee')
              .toString();
      status = (user['status'] ?? 'A').toString();
    } else {
      name = user.fullName ?? user.name ?? 'Employee';
      status = user.status ?? 'A';
    }

    Color statusColor;
    switch (status.toUpperCase()) {
      case 'P':
        statusColor = AppColors.success;
        break;
      case 'MIS':
        statusColor = Colors.orange;
        break;
      case 'A':
      case 'L':
      case 'PENDING':
      case 'REJECTED':
        statusColor = AppColors.error;
        break;
      default:
        statusColor = AppColors.textTertiary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkBorder : Colors.grey[200]!,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  status,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd MMM yy').format(date);
  }
}

extension DoubleExtension on double {
  String formatDecimal() {
    try {
      if (truncateToDouble() == this) {
        return toInt().toString();
      }
      return toStringAsFixed(1);
    } catch (e) {
      return toString();
    }
  }
}
