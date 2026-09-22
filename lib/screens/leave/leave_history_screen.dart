import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mecpl_flutter/screens/leave/leave_approval_screen.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import '../../core/theme/app_colors.dart';
import '../../models/leave_application_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/common/logo_loader.dart';

class LeaveHistoryScreen extends StatefulWidget {
  final String? empId;
  const LeaveHistoryScreen({super.key, this.empId});

  @override
  State<LeaveHistoryScreen> createState() => _LeaveHistoryScreenState();
}

class _LeaveHistoryScreenState extends State<LeaveHistoryScreen> {
  List<LeaveApplication> _leaveHistory = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchLeaveHistory();
  }

  Future<void> _fetchLeaveHistory() async {
    try {
      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;
      final token = authProvider.token;

      if (token != null && token.isNotEmpty) {
        final targetEmpId = widget.empId ?? currentUser?.id.toString();
        if (targetEmpId == null) {
          if (mounted) setState(() => _isLoading = false);
          return;
        }

        final history = await ApiService.getLeaveHistory(
          token: token,
          empId: targetEmpId,
        );

        if (mounted) {
          setState(() {
            // Sort by date descending (newest first)
            _leaveHistory = history.sorted(
              (a, b) => b.fromDate.compareTo(a.fromDate),
            );
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error fetching leave history: $e');
      if (mounted) {
        setState(() {
          _error = 'Failed to load history';
          _isLoading = false;
        });
      }
    }
  }

  Map<String, List<LeaveApplication>> _groupLeavesByMonth() {
    final Map<String, List<LeaveApplication>> grouped = {};
    for (var leave in _leaveHistory) {
      final monthKey = DateFormat('MMM yyyy').format(leave.fromDate);
      if (!grouped.containsKey(monthKey)) {
        grouped[monthKey] = [];
      }
      grouped[monthKey]!.add(leave);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final groupedLeaves = _groupLeavesByMonth();

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.chevron_left,
            color: isDark ? Colors.white : Colors.black,
            size: 28,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Leave History',
          style: GoogleFonts.poppins(
            color: isDark ? Colors.white70 : Colors.black87,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
        titleSpacing: 0,
      ),
      body: _isLoading
          ? const Center(child: LogoLoader())
          : _error != null
          ? Center(
              child: Text(_error!, style: TextStyle(color: AppColors.error)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  if (_leaveHistory.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 50.0),
                        child: Text(
                          'No leave history found',
                          style: GoogleFonts.poppins(
                            color: AppColors.textTertiary,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    )
                  else
                    ...groupedLeaves.entries.map((entry) {
                      return _buildMonthGroup(entry.key, entry.value, isDark);
                    }).toList(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildMonthGroup(
    String monthTitle,
    List<LeaveApplication> leaves,
    bool isDark,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurface
            : const Color(0xFFF9FAFB), // Light gray bg for card container
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.09),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Orange Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: const BoxDecoration(
              color: Color.fromARGB(255, 109, 13, 236), // Orange from design
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Text(
              monthTitle,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ),

          // List Items
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(0),
            itemCount: leaves.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              color: isDark
                  ? AppColors.darkBorder
                  : Colors.grey.withOpacity(0.1),
            ),
            itemBuilder: (context, index) {
              return _buildLeaveItem(leaves[index], isDark);
            },
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.1, end: 0);
  }

  Widget _buildLeaveItem(LeaveApplication leave, bool isDark) {
    // Determine status color/text
    Color statusBgColor;
    Color statusTextColor;
    String statusText = leave.status; // e.g., 'Approved', 'Pending'

    switch (leave.status.toLowerCase()) {
      case 'approved':
        statusBgColor = const Color(0xFFD1FAE5); // Light green
        statusTextColor = const Color(0xFF059669); // Dark green
        statusText =
            'Completed'; // Design uses 'Completed' for approved usually
        break;
      case 'rejected':
        statusBgColor = const Color(0xFFFEE2E2); // Light red
        statusTextColor = const Color(0xFFDC2626); // Dark red
        break;
      case 'pending':
      default:
        statusBgColor = const Color(0xFFFEF3C7); // Light yellow
        statusTextColor = const Color(0xFFD97706); // Dark orange
        break;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showLeaveDetails(context, leave, isDark),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    leave.leaveType.leaveName.toUpperCase(),
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: statusBgColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      statusText,
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: statusTextColor,
                      ),
                    ),
                  ),
                ],
              ),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatDateRange(leave.fromDate, leave.toDate),
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF1F2937),
                          ),
                        ),

                        Text(
                          leave.reason.isNotEmpty
                              ? leave.reason
                              : 'No reason provided',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                            fontWeight: FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const SizedBox(height: 8), // Align with date roughly
                      Row(
                        children: [
                          Text(
                            '${leave.netLeaveDays.formatDecimal()}d',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: AppColors.textTertiary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: AppColors.textTertiary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLeaveDetails(
    BuildContext context,
    LeaveApplication leave,
    bool isDark,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Leave Details',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(leave.status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    leave.status.toUpperCase(),
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(leave.status),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildDetailRow('Leave Type', leave.leaveType.leaveName, isDark),
            _buildDetailRow(
              'Duration',
              '${_formatDateRange(leave.fromDate, leave.toDate)} (${leave.netLeaveDays.formatDecimal()} Days)',
              isDark,
            ),
            _buildDetailRow('Half Day', leave.halfDay, isDark),
            _buildDetailRow(
              'Applied On',
              DateFormat('d MMM yyyy').format(leave.createdAt),
              isDark,
            ),
            const SizedBox(height: 16),
            Text(
              'Reason',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkBackground
                    : const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                leave.reason.isNotEmpty ? leave.reason : 'No reason provided',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
            if (leave.status.toLowerCase() == 'rejected' &&
                (leave.rejectionReason?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 16),
              Text(
                'Rejection Reason',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: AppColors.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.error.withOpacity(0.2)),
                ),
                child: Text(
                  leave.rejectionReason!,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return const Color(0xFF059669);
      case 'rejected':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFFD97706);
    }
  }

  String _formatDateRange(DateTime from, DateTime to) {
    if (from.year == to.year && from.month == to.month && from.day == to.day) {
      return DateFormat('d MMM').format(from);
    } else if (from.year == to.year && from.month == to.month) {
      return '${DateFormat('d').format(from)} - ${DateFormat('d MMM').format(to)}';
    } else {
      return '${DateFormat('d MMM').format(from)} - ${DateFormat('d MMM').format(to)}';
    }
  }
}
