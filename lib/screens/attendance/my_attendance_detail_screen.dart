import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/auth_provider.dart';
import 'regularize_attendance_screen.dart';

class MyAttendanceDetailScreen extends StatefulWidget {
  const MyAttendanceDetailScreen({super.key});

  @override
  State<MyAttendanceDetailScreen> createState() =>
      _MyAttendanceDetailScreenState();
}

class _MyAttendanceDetailScreenState extends State<MyAttendanceDetailScreen> {
  String _dateFilter = 'Last 7 Days';
  String _statusFilter = 'All';
  int? _selectedRecordIndex;
  int? _expandedIndex;
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchData();
    });
  }

  void _fetchData() {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    String apiFilter = 'last_7_days';
    String fromDate = '';
    String toDate = '';

    if (_dateFilter == 'Last 7 Days') {
      apiFilter = 'last_7_days';
    } else if (_dateFilter == 'This Month') {
      apiFilter = 'this_month';
    } else if (_dateFilter == 'Custom' &&
        _customStartDate != null &&
        _customEndDate != null) {
      apiFilter = 'custom';
      fromDate = DateFormat('yyyy-MM-dd').format(_customStartDate!);
      toDate = DateFormat('yyyy-MM-dd').format(_customEndDate!);
    }

    context.read<AttendanceProvider>().fetchMyAttendance(
      token: token,
      filter: apiFilter,
      fromDate: fromDate,
      toDate: toDate,
    );
  }

  List<Map<String, dynamic>> _getFilteredRecords(AttendanceProvider provider) {
    var records = provider.myAttendanceData;

    if (_statusFilter != 'All') {
      records = records.where((h) {
        final s = (h['status'] ?? '').toString().toLowerCase();
        switch (_statusFilter) {
          case 'Present':
            return s.contains('present') || s == 'p';
          case 'Absent':
            return s.contains('absent') || s == 'a';
          case 'Half Day':
            return s.contains('half') || s == 'hd' || s == 'l/p' || s == 'p/l';
          case 'Weekly Off':
            return s.contains('weekly') || s == 'wo';
          case 'Leave':
            return s.contains('leave') || s == 'l';
          case 'Paid Holiday':
            return s.contains('paid') || s == 'ph';
          case 'Late':
            return (h['is_late'] ?? '').toString().toLowerCase() == 'yes';
          default:
            return true;
        }
      }).toList();
    }
    return records;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final provider = context.watch<AttendanceProvider>();
    final filteredRecords = _getFilteredRecords(provider);

    // Extract summary counts from provider
    final summary = provider.myAttendanceSummary;
    final presentCount = summary['present'] ?? 0;
    final absentCount = summary['absent'] ?? 0;
    final halfDayCount = summary['half_day'] ?? 0;
    final weeklyOffCount = summary['weekly_off'] ?? 0;
    final leaveCount = summary['leave'] ?? 0;
    final paidHolidayCount = summary['holiday'] ?? 0;
    // Wait, the API summary might not send 'late' count explicitly, let's keep lateCount as what might exist or compute.
    // the API response example doesn't show late in summary but let's count late from data to be safe:
    final actualLateCount =
        summary['late'] ??
        provider.myAttendanceData
            .where(
              (item) =>
                  (item['is_late'] ?? '').toString().toLowerCase() == 'yes',
            )
            .length;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Attendance Summary",
          style: GoogleFonts.poppins(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          // Padding(
          //   padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          //   child: Text(
          //     "My Attendance",
          //     style: GoogleFonts.poppins(
          //       fontSize: 20,
          //       fontWeight: FontWeight.bold,
          //       color: Colors.black87,
          //     ),
          //   ),
          // ),
          const SizedBox(height: 12),

          // Date filter bar
          _buildDateFilterBar(),
          const SizedBox(height: 10),

          // Status filter chips
          _buildStatusFilterChips(
            presentCount,
            absentCount,
            halfDayCount,
            weeklyOffCount,
            leaveCount,
            paidHolidayCount,
            actualLateCount,
          ),
          const SizedBox(height: 10),

          // Table header
          _buildTableHeader(),
          const SizedBox(height: 4),

          // Attendance rows
          Expanded(
            child: provider.isMyAttendanceLoading || provider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredRecords.isEmpty
                ? Center(
                    child: Text(
                      "No records found",
                      style: GoogleFonts.poppins(
                        color: AppColors.textTertiary,
                        fontSize: 14,
                      ),
                    ),
                  )
                : ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: filteredRecords.length,
                    itemBuilder: (context, index) {
                      return _buildAttendanceRow(filteredRecords[index], index);
                    },
                  ),
          ),

          // Regularize button
          _buildRegularizeButton(filteredRecords),
        ],
      ),
    );
  }

  Widget _buildDateFilterBar() {
    final filters = ['Last 7 Days', 'This Month', 'Custom'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: filters.map((filter) {
          final isSelected = _dateFilter == filter;
          return Expanded(
            child: GestureDetector(
              onTap: () async {
                if (filter == 'Custom') {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: AppConstants.appStartDate,
                    lastDate: DateTime.now(),
                    initialDateRange:
                        _customStartDate != null && _customEndDate != null
                        ? DateTimeRange(
                            start: _customStartDate!,
                            end: _customEndDate!,
                          )
                        : DateTimeRange(
                            start: DateTime.now().subtract(
                              const Duration(days: 30),
                            ),
                            end: DateTime.now(),
                          ),
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.light(
                            primary: Color(0xFF031633),
                            onPrimary: Colors.white,
                            onSurface: Colors.black87,
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (picked != null) {
                    setState(() {
                      _customStartDate = picked.start;
                      _customEndDate = picked.end;
                      _dateFilter = 'Custom';
                      _fetchData();
                    });
                  }
                } else {
                  setState(() => _dateFilter = filter);
                  _fetchData();
                }
              },
              child: Container(
                margin: EdgeInsets.only(right: filter != filters.last ? 8 : 0),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF031633) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF031633)
                        : const Color(0xFFE0E0E0),
                  ),
                ),
                child: Center(
                  child: Text(
                    filter == 'Custom' &&
                            _customStartDate != null &&
                            _customEndDate != null &&
                            isSelected
                        ? '${DateFormat('dd/MM').format(_customStartDate!)} - ${DateFormat('dd/MM').format(_customEndDate!)}'
                        : filter,
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatusFilterChips(
    int presentCount,
    int absentCount,
    int halfDayCount,
    int weeklyOffCount,
    int leaveCount,
    int paidHolidayCount,
    int lateCount,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _buildStatusBadge('All', null, null, null),
          const SizedBox(width: 6),
          _buildStatusBadge(
            'Present',
            presentCount.toString(),
            const Color(0xFF2E7D32),
            const Color(0xFFE8F5E9),
          ),
          const SizedBox(width: 6),
          _buildStatusBadge(
            'Absent',
            absentCount.toString(),
            const Color(0xFFC62828),
            const Color(0xFFFFEBEE),
          ),
          const SizedBox(width: 6),
          _buildStatusBadge(
            'Half Day',
            halfDayCount.toString(),
            const Color(0xFFE65100),
            const Color(0xFFFFF3E0),
          ),
          const SizedBox(width: 6),
          _buildStatusBadge(
            'Weekly Off',
            weeklyOffCount.toString(),
            const Color(0xFF1565C0),
            const Color(0xFFE3F2FD),
          ),
          const SizedBox(width: 6),
          _buildStatusBadge(
            'Leave',
            leaveCount.toString(),
            const Color(0xFF6A1B9A),
            const Color(0xFFF3E5F5),
          ),
          const SizedBox(width: 6),
          _buildStatusBadge(
            'Paid Holiday',
            paidHolidayCount.toString(),
            const Color(0xFFAD1457),
            const Color(0xFFFCE4EC),
          ),
          const SizedBox(width: 6),
          _buildStatusBadge(
            'Late',
            lateCount.toString(),
            const Color(0xFF795548),
            const Color(0xFFEFEBE9),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(
    String label,
    String? count,
    Color? color,
    Color? bgColor,
  ) {
    final isSelected = _statusFilter == label;

    if (label == 'All') {
      return GestureDetector(
        onTap: () => setState(() => _statusFilter = 'All'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF031633) : Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? const Color(0xFF031633) : Colors.grey[300]!,
            ),
          ),
          child: Text(
            "All",
            style: GoogleFonts.poppins(
              color: isSelected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => setState(() => _statusFilter = label),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF031633) : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  color: isSelected ? Colors.white : Colors.black87,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(5),
                  bottomRight: Radius.circular(5),
                ),
                border: Border(left: BorderSide(color: Colors.grey[200]!)),
              ),
              child: Text(
                count ?? '0',
                style: GoogleFonts.poppins(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Check if a status qualifies for regularization (Absent or Half Day)
  bool _isRegularizable(String statusStr) {
    final s = statusStr.toLowerCase();
    return s.contains('absent') ||
        s == 'a' ||
        s.contains('half') ||
        s == 'hd' ||
        s == 'l/p' ||
        s == 'p/l';
  }

  Widget _buildTableHeader() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color.fromARGB(238, 228, 135, 13),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          // Checkbox column spacer
          const SizedBox(width: 32),
          Expanded(
            flex: 4,
            child: Text(
              "Date",
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              "Work Hours",
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              "Status",
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 24),
        ],
      ),
    );
  }

  Map<String, dynamic> _getStatusBadge(String status) {
    final s = status.toLowerCase();
    if (s.contains('present') || s == 'p') {
      return {
        'label': 'P',
        'color': const Color(0xFF2E7D32),
        'bgColor': const Color(0xFFE8F5E9),
      };
    } else if (s.contains('absent') || s == 'a') {
      return {
        'label': 'A',
        'color': const Color(0xFFC62828),
        'bgColor': const Color(0xFFFFEBEE),
      };
    } else if (s.contains('half') || s == 'hd') {
      return {
        'label': 'HD',
        'color': const Color(0xFFE65100),
        'bgColor': const Color(0xFFFFF3E0),
      };
    } else if (s.contains('weekly') || s == 'wo') {
      return {
        'label': 'WO',
        'color': const Color(0xFF1565C0),
        'bgColor': const Color(0xFFE3F2FD),
      };
    } else if (s.contains('leave') || s == 'l') {
      return {
        'label': 'L',
        'color': const Color(0xFF6A1B9A),
        'bgColor': const Color(0xFFF3E5F5),
      };
    } else if (s.contains('paid') || s == 'ph') {
      return {
        'label': 'PH',
        'color': const Color(0xFFAD1457),
        'bgColor': const Color(0xFFFCE4EC),
      };
    } else if (s.contains('late')) {
      return {
        'label': 'Late',
        'color': const Color(0xFF795548),
        'bgColor': const Color(0xFFEFEBE9),
      };
    } else if (s.contains('l/p') ||
        s == 'l/p' ||
        s.contains('p/l') ||
        s == 'p/l') {
      return {
        'label': 'L/P',
        'color': const Color(0xFF00796B),
        'bgColor': const Color(0xFFE0F2F1),
      };
    } else {
      return {
        'label': 'MIS',
        'color': const Color(0xFFE65100),
        'bgColor': const Color(0xFFFFF3E0),
      };
    }
  }

  Widget _buildAttendanceRow(Map<String, dynamic> item, int index) {
    // API fields: status, date, first_in, last_out, work_hours, is_late, is_early
    final statusStr = (item['status'] ?? '').toString();
    var badgeLabel = statusStr;
    if (statusStr.toLowerCase() == 'p' &&
        (item['is_late'] ?? '').toString().toLowerCase() == 'yes') {
      badgeLabel = 'Late';
    }
    final badge = _getStatusBadge(badgeLabel);
    final isSelected = _selectedRecordIndex == index;
    final isExpanded = _expandedIndex == index;
    final workHours = (item['work_hours'] ?? '0.00').toString();
    final dateStr = (item['date'] ?? '').toString();
    final canRegularize = _isRegularizable(statusStr);

    // Parse date if possible, else just use the string
    String displayDate = dateStr;
    try {
      final DateFormat formatter = DateFormat('dd-MM-yyyy');
      final dateTime = formatter.parse(dateStr);
      displayDate = DateFormat('dd MMM yyyy').format(dateTime);
    } catch (_) {
      displayDate = dateStr;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            child: Row(
              children: [
                // Checkbox — only for Absent/Half Day
                if (canRegularize)
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedRecordIndex = index;
                          } else {
                            _selectedRecordIndex = null;
                          }
                        });
                      },
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      side: BorderSide(color: Colors.grey.shade400),
                      activeColor: const Color(0xFF031633),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                else
                  const SizedBox(width: 24),
                const SizedBox(width: 8),

                // Date
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayDate,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),

                // Work Hours
                Expanded(
                  flex: 3,
                  child: Text(
                    workHours,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                // Status badge
                Expanded(
                  flex: 2,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: (badge['bgColor'] as Color),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badge['label'] as String,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: badge['color'] as Color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Expand chevron
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _expandedIndex = isExpanded ? null : index;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.grey,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Expanded details
          if (isExpanded) _buildExpandedDetails(item),
        ],
      ),
    );
  }

  Widget _buildExpandedDetails(Map<String, dynamic> item) {
    final shift = 'Full Time';
    final shiftInTime = '09:00 AM'; // Can be mapped if available via API later
    final shiftOutTime = '06:00 PM';

    final firstIn = (item['first_in'] ?? '-').toString();
    final lastOut = (item['last_out'] ?? '-').toString();

    // Time fields from API

    final actualInTime = firstIn != '-' ? firstIn : 'NA';
    final actualOutTime = lastOut != '-' ? lastOut : 'NA';
    final workHours = (item['work_hours'] ?? '0.00').toString() + ' hrs';
    final isLate = (item['is_late'] ?? '').toString().toLowerCase() == 'yes';
    final isEarly = (item['is_early'] ?? '').toString().toLowerCase() == 'yes';

    // Determine late/early status
    String lateEarlyLabel = '--';
    if (isEarly && isLate)
      lateEarlyLabel = 'Late In & Early Out';
    else if (isLate)
      lateEarlyLabel = 'Late In';
    else if (isEarly)
      lateEarlyLabel = 'Early Out';
    else if ((item['status'] ?? '').toString().toUpperCase() == 'P')
      lateEarlyLabel = 'On Time';

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F9FA),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(10),
          bottomRight: Radius.circular(10),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(10),
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
                Expanded(child: _buildDetailItem('SHIFT', shift)),
                Expanded(child: _buildDetailItem('SHIFT IN TIME', shiftInTime)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildDetailItem('ACTUAL IN TIME', actualInTime),
                ),
                Expanded(
                  child: _buildDetailItem('SHIFT OUT TIME', shiftOutTime),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildDetailItem('ACTUAL OUT TIME', actualOutTime),
                ),
                Expanded(child: _buildDetailItem('WORK HOURS', workHours)),
              ],
            ),
            const SizedBox(height: 8),
            _buildDetailItem('LATE EARLY', lateEarlyLabel),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade500,
            letterSpacing: 0.3,
          ),
        ),
        Text(
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

  Widget _buildRegularizeButton(List<Map<String, dynamic>> filteredRecords) {
    final hasSelection = _selectedRecordIndex != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      color: Colors.white,
      child: ElevatedButton(
        onPressed: hasSelection
            ? () async {
                final selectedRecord = filteredRecords[_selectedRecordIndex!];
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RegularizeAttendanceScreen(
                      attendanceRecord: selectedRecord,
                    ),
                  ),
                );
                if (result == true) {
                  setState(() {
                    _selectedRecordIndex = null;
                  });
                  _fetchData();
                }
              }
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF031633),
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey[300],
          disabledForegroundColor: Colors.grey[500],
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Text(
          "Regularize",
          style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
